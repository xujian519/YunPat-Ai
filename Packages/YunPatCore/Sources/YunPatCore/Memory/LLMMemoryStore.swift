import Foundation

// MARK: - LLM-Accessible Memory Store

/// 面向 LLM 可访问的持久化记忆存储
///
/// 设计参考 Agent-main (macOS26/Agent) 的 MemoryStore:
/// - YAML-style frontmatter + markdown body 的 .md 文件格式
/// - 4 种记忆类型: user(偏好) / feedback(行为指引) / project(项目上下文) / reference(外部指针)
/// - 文件路径: ~/Documents/YunPat/memory/<type>/<id>.md
/// - 索引文件: ~/Documents/YunPat/memory/MEMORY.md
///
/// LLM 可通过 read_file / write_file 工具直接读写这些 .md 文件,
/// 无需专门的 memory tool 即可操作。
public final class LLMMemoryStore: @unchecked Sendable {
    public static let shared: LLMMemoryStore = LLMMemoryStore()
    private let lock: NSRecursiveLock = NSRecursiveLock()
    /// 记忆目录
    public static let memoryDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Documents/YunPat/memory")
    }()

    /// 索引文件
    public static let indexPath: URL = {
        memoryDir.appendingPathComponent("MEMORY.md")
    }()

    private init() {
        ensureDirectories()
    }

    // MARK: - Directory Setup

    private func ensureDirectories() {
        let fileManager: FileManager = FileManager.default
        for type in MemoryEntryType.allCases {
            let dir = Self.memoryDir.appendingPathComponent(type.rawValue)
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - CRUD

    /// 列出所有条目
    public func listAll() -> [MemoryEntryMetadata] {
        lock.lock()
        defer { lock.unlock() }
        var entries: [MemoryEntryMetadata] = []
        let fileManager: FileManager = FileManager.default
        for type in MemoryEntryType.allCases {
            let dir = Self.memoryDir.appendingPathComponent(type.rawValue)
            guard let files = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
                continue
            }
            for url in files where url.pathExtension == "md" && url.lastPathComponent != "MEMORY.md" {
                let id = url.deletingPathExtension().lastPathComponent
                if let entry = loadMetadata(id: id, type: type) {
                    entries.append(entry)
                }
            }
        }
        return entries.sorted { $0.id < $1.id }
    }

    /// 列出指定类型的条目
    public func list(type: MemoryEntryType) -> [MemoryEntryMetadata] {
        listAll().filter { $0.type == type }
    }

    /// 加载指定条目
    public func load(id: String, type: MemoryEntryType) -> MemoryEntry? {
        lock.lock()
        defer { lock.unlock() }
        let url = Self.url(for: id, type: type)
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return MemoryEntry.parse(id: id, type: type, raw: raw)
    }

    /// 按 ID 查找 (搜索所有类型)
    public func load(id: String) -> MemoryEntry? {
        for type in MemoryEntryType.allCases {
            if let entry = load(id: id, type: type) {
                return entry
            }
        }
        return nil
    }

    /// 保存或更新条目
    @discardableResult
    public func save(_ entry: MemoryEntry) -> Bool {
        lock.lock()
        let url = Self.url(for: entry.id, type: entry.type)
        let content = entry.serialize()
        var success: Bool = false
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            success = true
        } catch {
            print("[LLMMemoryStore] Failed to save \(entry.id): \(error)")
        }
        lock.unlock()
        if success { rebuildIndex() }
        return success
    }

    /// 删除条目
    public func delete(id: String, type: MemoryEntryType) -> Bool {
        lock.lock()
        let url = Self.url(for: id, type: type)
        var success: Bool = false
        do {
            try FileManager.default.removeItem(at: url)
            success = true
        } catch {
            print("[LLMMemoryStore] Failed to delete \(id): \(error)")
        }
        lock.unlock()
        if success { rebuildIndex() }
        return success
    }

    // MARK: - LLM-Friendly Access

    /// 生成 manifest 摘要 (供 LLM 理解有哪些记忆)
    public func manifest() -> String {
        let entries = listAll()
        if entries.isEmpty { return "（无记忆条目）" }
        return entries.map { $0.manifestLine }.joined(separator: "\n")
    }

    /// 全文搜索 (简单 substring 匹配)
    public func search(_ query: String) -> [MemoryEntryMetadata] {
        listAll().filter { meta in
            meta.description.localizedCaseInsensitiveContains(query)
                || meta.name.localizedCaseInsensitiveContains(query)
                || meta.id.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: - Private Helpers

    private func loadMetadata(id: String, type: MemoryEntryType) -> MemoryEntryMetadata? {
        guard let entry = load(id: id, type: type) else { return nil }
        return MemoryEntryMetadata(
            id: entry.id,
            name: entry.name,
            description: entry.description,
            type: entry.type
        )
    }

    private func rebuildIndex() {
        let entries = listAll()
        var lines: [String] = ["# YunPat Memory Index", "", "| 类型 | ID | 名称 | 描述 |", "|------|-----|------|------|"]
        for entry in entries {
            lines.append("| \(entry.type.rawValue) | \(entry.id) | \(entry.name) | \(entry.description) |")
        }
        try? lines.joined(separator: "\n").write(to: Self.indexPath, atomically: true, encoding: .utf8)
    }

    static func url(for id: String, type: MemoryEntryType) -> URL {
        memoryDir.appendingPathComponent(type.rawValue).appendingPathComponent("\(id).md")
    }
}

// MARK: - Memory Entry Types

/// 记忆条目类型
public enum MemoryEntryType: String, CaseIterable, Sendable {
    /// 用户偏好 — 角色、目标、风格
    case user
    /// 行为指引 — 成功模式、避免事项
    case feedback
    /// 项目上下文 — 在办案件、进度、决策
    case project
    /// 外部指针 — 法条编号、判例索引、链接
    case reference
}

// MARK: - Memory Entry Metadata (for listing)

/// 记忆条目元数据 (不包含 body 内容，用于列表展示)
public struct MemoryEntryMetadata: Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let type: MemoryEntryType

    /// 一行 manifest 摘要
    public var manifestLine: String {
        "[\(type.rawValue)] \(id) — \(description.prefix(120))"
    }
}

// MARK: - Memory Entry

/// 单个记忆条目 — YAML frontmatter + markdown body
public struct MemoryEntry: Sendable {
    public let id: String
    public var name: String
    public var description: String
    public var type: MemoryEntryType
    public var content: String

    // MARK: - Parsing

    /// 解析 YAML-style frontmatter + markdown body
    /// 格式:
    /// ---
    /// name: 撰写风格
    /// description: 用户偏好的权利要求撰写风格指引
    /// ---
    /// <markdown body>
    public static func parse(id: String, type: MemoryEntryType, raw: String) -> MemoryEntry? {
        guard raw.hasPrefix("---") else { return nil }
        let parts = raw.components(separatedBy: "---")
        guard parts.count >= 3 else { return nil }

        let frontmatter = parts[1]
        let body = parts.dropFirst(2).joined(separator: "---")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var name = id
        var description: String = ""
        for line in frontmatter.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("name:") {
                name = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("description:") {
                description = String(trimmed.dropFirst(12)).trimmingCharacters(in: .whitespaces)
            }
        }

        return MemoryEntry(id: id, name: name, description: description, type: type, content: body)
    }

    // MARK: - Serialization

    /// 序列化为 .md 文件格式
    public func serialize() -> String {
        """
        ---
        name: \(sanitizeFrontmatter(name))
        description: \(sanitizeFrontmatter(description))
        type: \(type.rawValue)
        id: \(id)
        ---
        \(content)
        """
    }

    private func sanitizeFrontmatter(_ value: String) -> String {
        value.replacingOccurrences(of: "---", with: "\\-\\-\\-")
    }
}
