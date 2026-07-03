import Foundation

/// 案件级规则文件系统
///
/// 设计 §12.9：不同案件类型需要不同规则
/// 优先级：案件级 > 客户级 > 事务所级 > 知识库
public actor CaseRuleLoader {
    public static let shared = CaseRuleLoader()
    private var cache: [String: [CaseRule]] = [:]
    private var watchedPaths: Set<String> = []

    public init() {}

    /// 加载案件级规则
    public func loadRules(for workspaceURL: URL) async -> [CaseRule] {
        let rulesDir = workspaceURL.appendingPathComponent(".yunpat/rules")
        let cacheKey = rulesDir.path

        if let cached = cache[cacheKey] { return cached }

        var rules: [CaseRule] = []
        guard FileManager.default.fileExists(atPath: rulesDir.path) else { return rules }

        do {
            let files = try FileManager.default.contentsOfDirectory(at: rulesDir, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "md" {
                let content: String
                do {
                    content = try String(contentsOf: file, encoding: .utf8)
                } catch {
                    print("[CaseRuleLoader] Failed to read \(file.lastPathComponent): \(error)")
                    continue
                }
                let fileName = file.deletingPathExtension().lastPathComponent
                let priority: Int =
                    fileName.hasPrefix("01")
                    ? 1
                    : fileName.hasPrefix("02")
                        ? 2
                        : fileName.hasPrefix("03")
                            ? 3
                            : fileName.hasPrefix("04") ? 4 : 5

                rules.append(
                    CaseRule(
                        name: fileName,
                        content: content,
                        priority: priority,
                        source: file
                    ))
            }
        } catch {
            print("[CaseRuleLoader] Failed to load rules from \(rulesDir.path): \(error)")
        }

        rules.sort { $0.priority < $1.priority }
        cache[cacheKey] = rules
        return rules
    }

    /// 将规则注入为 LLM 可读文本
    public func injectableRules(for workspaceURL: URL, maxTokens: Int = 5000) async -> String {
        let rules = await loadRules(for: workspaceURL)
        guard !rules.isEmpty else { return "" }

        var parts: [String] = ["【案件级规则】"]
        var tokenCount: Int = 0

        for rule in rules {
            let text: String = "## \(rule.name)\n\(rule.content.prefix(500))"
            let estimated = text.count / 2  // CJK approx
            if tokenCount + estimated > maxTokens {
                parts.append("…（\(rules.count - parts.count + 1) 条规则已折叠）")
                break
            }
            parts.append(text)
            tokenCount += estimated
        }
        return parts.joined(separator: "\n\n")
    }

    /// 使缓存失效（文件变更时调用）
    public func invalidateCache(for workspaceURL: URL) {
        cache.removeValue(forKey: workspaceURL.appendingPathComponent(".yunpat/rules").path)
    }
}

public struct CaseRule: Sendable {
    public let name: String
    public let content: String
    public let priority: Int
    public let source: URL
    public init(name: String, content: String, priority: Int, source: URL) {
        self.name = name
        self.content = content
        self.priority = priority
        self.source = source
    }
}
