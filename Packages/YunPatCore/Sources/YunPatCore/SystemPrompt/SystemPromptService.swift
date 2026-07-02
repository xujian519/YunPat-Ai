import Foundation

/// 管理可编辑的系统提示词文件，存储于 ~/Documents/YunPat/system/
///
/// 设计参考 Agent-main (macOS26/Agent) 的 SystemPromptService:
/// - 版本化磁盘文件: 每次构建更新时自动刷新默认模板
/// - READONLY / CUSTOM header: 保护用户自定义不被覆盖
/// - {userName}/{userHome}/{projectFolder} 占位符替换
/// - 专利专用反幻觉规则 + 高效行动规则
///
/// 线程安全: 从 class + NSLock 迁移为 actor，利用 Swift 6 原生并发隔离。
/// 所有 public 方法在 actor 上下文中串行执行，无需显式锁。
public actor SystemPromptService {
    public static let shared: SystemPromptService = SystemPromptService()

    /// 系统提示词目录
    private static let systemDir: URL = {
        let home: URL = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Documents/YunPat/system")
    }()

    /// 通用系统提示词文件名
    public static let commonFileName: String = "system_prompt.txt"

    /// 版本 header 前缀
    private static let versionPrefix: String = "// YunPat v"
    /// 用户自定义 header 前缀 (防止自动覆盖)
    private static let customPrefix: String = "// YunPat custom v"
    /// 只读 header 前缀 (永不自动覆盖)
    private static let readOnlyPrefix: String = "// YunPat READ ONLY v"

    /// 组合版本戳: <marketing>.<build>
    private static let appVersion: String = {
        let info: [String: Any]? = Bundle.main.infoDictionary
        let marketing: String = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build: String = info?["CFBundleVersion"] as? String ?? "0"
        return "\(marketing).\(build)"
    }()

    // MARK: - 专利专用反幻觉规则

    /// 专利场景反幻觉规则 — 基于 Agent-main 的 antiHallucinationRules 改写
    public static let patentAntiHallucinationRules: String = """
        【反幻觉规则 — 最高优先级，覆盖所有其他指令】
        - 禁止凭空编造、推测或臆断。你所做的每个引用必须来自实际工具调用结果。
        - 引用法条时必须标注来源，如「审查指南 第二部分 第三章 §3.2.1」。
          未通过 search/retrieve 工具实际读取的法条，不得引用。
        - 引用专利文献时必须标注公开号。未通过实际检索获取的专利号、申请日、
          法律状态等信息，不得编造。
        - 「可能是」「通常」「一般来说」是编造信号。出现此类措辞时，立即停止，
          发起实际检索，或诚实告知不确定性。
        - 从零散证据拼凑出完整结论是严格禁止的行为——宁可只报告已确认事实，
          也不可填补空白。
        - 若前一次工具调用失败或返回模糊结果，不得重新解释或外推。重新指定
          更精确的输入再次调用，或选择放弃该项分析。
        - 不可声称执行了某项操作(检索、打开、点击、运行)除非实际调用了工具
          并收到了确认返回。
        """

    /// 高效行动规则 — 防止过度分析和重复读取
    public static let patentEfficientActionRules: String = """
        【高效行动规则 — 高优先级】
        - 不过度分析。快速做决定，持续前进。
        - 同一文件不重复阅读。若文件已修改，可重新读取。
        - 逐文件操作：完成当前文件的修改后再处理下一个文件。
        - 简洁表达：不写多段前言、不重述任务、不总结「即将」做什么——直接执行。
        - 证据足够时立刻行动。修改完成后立即调用 task_complete。

        【承诺规则 — 硬约束】
        - 「找到问题所在」「明确了根因」「已掌握全貌」等声明是承诺，不是叙事。
          此类声明之后的第一个工具调用必须是编辑工具(edit_file/write_file)。
          声明后继续读取文件是违反承诺的行为。
        - 若不能立即编辑，就不要声称找到了问题。要么继续无声调查，要么
          调用 task_complete 诚实报告未知项。
        - 十次读取零次编辑 = 失败。宁可两次读取加一次错误编辑(下轮可改正)，
          也好过连续读取毫无产出。
        """

    private init() {}

    // MARK: - 默认内容

    /// 生成专利场景默认系统提示词
    public static func defaultPrompt() -> String {
        """
        你是一个面向中国专利代理人和专利律师的 AI 智能体 (YunPat-Ai)，运行于 macOS。

        【用户信息】
        - 用户名: {userName}
        - 用户目录: {userHome}
        - 项目目录: {projectFolder}

        【能力范围】
        - 专利文献检索与分析 (Google Patents / CNIPA)
        - 权利要求解析与四层对比分析
        - 创造性判断 (专利法第22条第3款三步法)
        - 审查意见答复策略制定与答复书撰写
        - 专利撰写 (权利要求布局 + 五部分说明书)
        - 法律状态查询

        【工作原则】
        - 始终以中国专利法律体系为准 (中国专利法、审查指南、司法解释)
        - 输出格式遵循 CNIPA 规范
        - 保守评估：不确定时明确告知，不强行给出不可靠结论
        - 每个分析步骤标注所依据的法律条款或审查指南章节

        """ + patentAntiHallucinationRules + "\n\n" + patentEfficientActionRules
    }

    /// 简洁版提示词 (用于 token 受限场景)
    public static func defaultCompactPrompt() -> String {
        """
        你是面向中国专利代理人的 AI 智能体。以中国专利法/审查指南为准。
        基于实际检索结果回答，不可凭空编造。
        """ + patentAntiHallucinationRules
    }

    // MARK: - 磁盘文件管理

    /// 确保 system/ 目录存在，并按版本写入默认提示词
    public func ensureDefaults() {
        let fileManager: FileManager = FileManager.default
        try? fileManager.createDirectory(at: Self.systemDir, withIntermediateDirectories: true)
        writeIfNeeded(
            fileName: Self.commonFileName,
            defaultContent: Self.defaultPrompt()
        )
    }

    /// 按需写入提示词文件 (不存在或版本变更时)
    private func writeIfNeeded(fileName: String, defaultContent: String) {
        let fileManager: FileManager = FileManager.default
        let url: URL = Self.systemDir.appendingPathComponent(fileName)
        let needsWrite: Bool
        if !fileManager.fileExists(atPath: url.path) {
            needsWrite = true
        } else if let existing: String = try? String(contentsOf: url, encoding: .utf8),
            let firstLine: String = existing.components(separatedBy: "\n").first {
            if firstLine.hasPrefix(Self.readOnlyPrefix) {
                needsWrite = false
            } else if firstLine.hasPrefix(Self.customPrefix) {
                let fileVersion: String = String(firstLine.dropFirst(Self.customPrefix.count))
                needsWrite = fileVersion != Self.appVersion
            } else if firstLine.hasPrefix(Self.versionPrefix) {
                let fileVersion: String = String(firstLine.dropFirst(Self.versionPrefix.count))
                needsWrite = fileVersion != Self.appVersion
            } else {
                needsWrite = true
            }
        } else {
            needsWrite = true
        }

        if needsWrite {
            let versioned: String = Self.versionPrefix + Self.appVersion + "\n" + defaultContent
            do {
                try versioned.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("[SystemPrompt] Failed to write \(url.lastPathComponent): \(error)")
            }
        }
    }

    /// 读取磁盘上的提示词，替换占位符。去除版本注释行后返回。
    public func prompt(
        userName: String = NSUserName(),
        userHome: String = NSHomeDirectory(),
        projectFolder: String = ""
    ) -> String {
        ensureDefaults()
        let url: URL = Self.systemDir.appendingPathComponent(Self.commonFileName)
        guard let template: String = try? String(contentsOf: url, encoding: .utf8) else {
            return Self.defaultPrompt()
        }
        let content: String = Self.stripVersionLine(template)
        let folder: String = projectFolder.isEmpty ? userHome : projectFolder
        return
            content
            .replacingOccurrences(of: "{userName}", with: userName)
            .replacingOccurrences(of: "{userHome}", with: userHome)
            .replacingOccurrences(of: "{projectFolder}", with: folder)
    }

    /// 去除版本注释行
    private static func stripVersionLine(_ text: String) -> String {
        if text.hasPrefix(readOnlyPrefix) || text.hasPrefix(customPrefix) || text.hasPrefix(versionPrefix) {
            let lines: [String] = text.components(separatedBy: "\n")
            return lines.dropFirst().joined(separator: "\n")
        }
        return text
    }

    /// 读取原始模板 (含占位符)，供编辑界面使用
    public func rawTemplate() -> String {
        ensureDefaults()
        let url: URL = Self.systemDir.appendingPathComponent(Self.commonFileName)
        let raw: String = (try? String(contentsOf: url, encoding: .utf8)) ?? Self.defaultPrompt()
        return Self.stripVersionLine(raw)
    }

    /// 保存用户编辑的模板，前置 custom header 防止自动覆盖
    public func saveTemplate(_ content: String) {
        let url: URL = Self.systemDir.appendingPathComponent(Self.commonFileName)
        let stripped: String = Self.stripVersionLine(content)
        let trimmed: String = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let isReadOnly: Bool = trimmed.hasPrefix("READ ONLY") || trimmed.hasPrefix("// READ ONLY")
        let header: String = isReadOnly ? Self.readOnlyPrefix : Self.customPrefix
        let versioned: String = header + Self.appVersion + "\n" + stripped
        do {
            try versioned.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            print("[SystemPrompt] Failed to save template: \(error)")
        }
    }

    /// 重置为默认提示词
    public func resetToDefault() {
        let url: URL = Self.systemDir.appendingPathComponent(Self.commonFileName)
        let content: String = Self.defaultPrompt()
        let versioned: String = Self.versionPrefix + Self.appVersion + "\n" + content
        do {
            try versioned.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            print("[SystemPrompt] Failed to reset: \(error)")
        }
    }

    /// 是否只读
    public func isReadOnly() -> Bool {
        let url: URL = Self.systemDir.appendingPathComponent(Self.commonFileName)
        guard let existing: String = try? String(contentsOf: url, encoding: .utf8),
            let firstLine: String = existing.components(separatedBy: "\n").first
        else {
            return false
        }
        return firstLine.hasPrefix(Self.readOnlyPrefix)
    }
}
