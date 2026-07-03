import Foundation

// MARK: - Article Step Definition

/// A single step within an article-based legal reasoning framework.
public struct ArticleStepDefinition: Sendable, Codable {
    public let id: String
    public let order: Int
    public let name: String
    public let ruleRef: String
    public let inputHint: String

    public init(id: String, order: Int, name: String, ruleRef: String, inputHint: String) {
        self.id = id
        self.order = order
        self.name = name
        self.ruleRef = ruleRef
        self.inputHint = inputHint
    }
}

// MARK: - Article Framework

/// A YAML-style article framework template that encodes stepped legal reasoning
/// under a specific patent law article.
public struct ArticleFramework: Sendable, Codable {
    public let articleId: String
    public let name: String
    public let lawRef: String
    public let guidelineRef: String?
    public let steps: [ArticleStepDefinition]
    public let applicableTo: [CaseType]

    public init(
        articleId: String,
        name: String,
        lawRef: String,
        guidelineRef: String? = nil,
        steps: [ArticleStepDefinition],
        applicableTo: [CaseType]
    ) {
        self.articleId = articleId
        self.name = name
        self.lawRef = lawRef
        self.guidelineRef = guidelineRef
        self.steps = steps
        self.applicableTo = applicableTo
    }
}

// MARK: - Step Result

/// Result of executing a single framework step.
public struct ArticleStepResult: Sendable {
    public let stepId: String
    public let completed: Bool
    public let output: [String: String]

    public init(stepId: String, completed: Bool, output: [String: String]) {
        self.stepId = stepId
        self.completed = completed
        self.output = output
    }
}

// MARK: - Framework Judgment

/// Complete judgment produced by running all steps of an article framework.
/// Named `ArticleFrameworkJudgment` to avoid collision with FactBlackboard's
/// simpler `ArticleJudgment` (which has articleId/name/conclusion/reasoning).
public struct ArticleFrameworkJudgment: Sendable {
    public let articleId: String
    public let articleName: String
    public let stepResults: [String: ArticleStepResult]
    public let conclusion: String
    public let confidence: String  // "high", "medium", or "low"

    public init(
        articleId: String,
        articleName: String,
        stepResults: [String: ArticleStepResult],
        conclusion: String,
        confidence: String
    ) {
        self.articleId = articleId
        self.articleName = articleName
        self.stepResults = stepResults
        self.conclusion = conclusion
        self.confidence = confidence
    }
}

// MARK: - Framework Engine Actor

/// Loads YAML-based article frameworks and orchestrates LLM-driven
/// step-by-step legal judgments.
public actor FrameworkEngine {

    private var frameworks: [String: ArticleFramework] = [:]
    private var promptExecutor: (@Sendable (String) async throws -> String)?

    public init() {
        for framework in FrameworkEngine.builtinFrameworks {
            frameworks[framework.articleId] = framework
        }
    }

    /// 配置 LLM 执行器 — App 启动时注入 ModelRouter.chat
    public func configurePromptExecutor(_ executor: @Sendable @escaping (String) async throws -> String) {
        promptExecutor = executor
    }

    /// Three hardcoded frameworks for MVP.
    public static let builtinFrameworks: [ArticleFramework] = [
        makePatentLaw22_2(),
        makePatentLaw22_3(),
        makePatentLaw26_4()
    ]

    // MARK: - Framework 1: 新颖性 (Article 22.2)

    private static func makePatentLaw22_2() -> ArticleFramework {
        ArticleFramework(
            articleId: "patentLaw22_2",
            name: "新颖性判断",
            lawRef: "专利法第22条第2款",
            guidelineRef: "审查指南第二部分第三章",
            steps: [
                ArticleStepDefinition(
                    id: "22_2_step1",
                    order: 1,
                    name: "确定现有技术范围",
                    ruleRef: "专利法22.2",
                    inputHint: "提供申请日、现有技术文献的公开日期和技术内容"
                ),
                ArticleStepDefinition(
                    id: "22_2_step2",
                    order: 2,
                    name: "技术方案对比",
                    ruleRef: "审查指南第二部分第三章2.1",
                    inputHint: "逐项对比权利要求的技术特征与现有技术公开的内容"
                ),
                ArticleStepDefinition(
                    id: "22_2_step3",
                    order: 3,
                    name: "判断新颖性",
                    ruleRef: "审查指南第二部分第三章3.1",
                    inputHint: "基于对比结果判断是否属于现有技术，给出新颖性结论"
                )
            ],
            applicableTo: [.noveltySearch, .patentability]
        )
    }

    // MARK: - Framework 2: 创造性/三步法 (Article 22.3)

    private static func makePatentLaw22_3() -> ArticleFramework {
        ArticleFramework(
            articleId: "patentLaw22_3",
            name: "创造性判断（三步法）",
            lawRef: "专利法第22条第3款",
            guidelineRef: "审查指南第二部分第四章",
            steps: [
                ArticleStepDefinition(
                    id: "22_3_step1",
                    order: 1,
                    name: "确定最接近的现有技术",
                    ruleRef: "审查指南第二部分第四章2.1",
                    inputHint: "从现有技术文献中选择与本申请技术领域相同、技术效果最接近的对比文件"
                ),
                ArticleStepDefinition(
                    id: "22_3_step2",
                    order: 2,
                    name: "确定区别特征和实际解决的技术问题",
                    ruleRef: "审查指南第二部分第四章3.2.1",
                    inputHint: "列出区别技术特征，基于区别特征确定发明实际解决的技术问题"
                ),
                ArticleStepDefinition(
                    id: "22_3_step3",
                    order: 3,
                    name: "判断是否显而易见",
                    ruleRef: "审查指南第二部分第四章3.2.2",
                    inputHint: "判断要求保护的发明对本领域技术人员来说是否显而易见（motivation-suggestion-test）"
                )
            ],
            applicableTo: [.patentability]
        )
    }

    // MARK: - Framework 3: 清楚/不支持 (Article 26.4)

    private static func makePatentLaw26_4() -> ArticleFramework {
        ArticleFramework(
            articleId: "patentLaw26_4",
            name: "权利要求清楚与支持判断",
            lawRef: "专利法第26条第4款",
            guidelineRef: "审查指南第二部分第二章",
            steps: [
                ArticleStepDefinition(
                    id: "26_4_step1",
                    order: 1,
                    name: "判断权利要求是否清楚",
                    ruleRef: "审查指南第二部分第二章2.2.6",
                    inputHint: "检查权利要求用语是否清楚、无歧义，保护范围边界是否明确"
                ),
                ArticleStepDefinition(
                    id: "26_4_step2",
                    order: 2,
                    name: "判断是否得到说明书支持",
                    ruleRef: "审查指南第二部分第二章3.3",
                    inputHint: "判断权利要求的技术方案是否能够得到说明书充分公开内容的支持"
                ),
                ArticleStepDefinition(
                    id: "26_4_step3",
                    order: 3,
                    name: "综合判断与结论",
                    ruleRef: "审查指南第二部分第二章2.1",
                    inputHint: "综合前两步分析，给出权利要求是否清楚、是否得到支持的最终结论"
                )
            ],
            applicableTo: [.invalidation]
        )
    }

    // MARK: - Loading

    /// Load frameworks from a directory path. For MVP, this returns the
    /// in-memory cache of built-in frameworks regardless of the directory.
    /// Future: parse YAML framework definitions from disk.
    public func loadFromDirectory(dirPath: String) -> [String: ArticleFramework] {
        if frameworks.isEmpty {
            for framework in FrameworkEngine.builtinFrameworks {
                frameworks[framework.articleId] = framework
            }
        }
        return frameworks
    }

    /// Load a single framework, returning a copy with steps sorted by order.
    public func loadFrameworkSync(framework: ArticleFramework) -> ArticleFramework {
        let sortedSteps: [ArticleStepDefinition] = framework.steps.sorted { $0.order < $1.order }
        return ArticleFramework(
            articleId: framework.articleId,
            name: framework.name,
            lawRef: framework.lawRef,
            guidelineRef: framework.guidelineRef,
            steps: sortedSteps,
            applicableTo: framework.applicableTo
        )
    }

    /// List frameworks applicable to a given case type.
    public func listApplicable(caseType: CaseType) -> [ArticleFramework] {
        if frameworks.isEmpty {
            for framework in FrameworkEngine.builtinFrameworks {
                frameworks[framework.articleId] = framework
            }
        }
        return frameworks.values.filter { $0.applicableTo.contains(caseType) }
    }

    // MARK: - Execution

    /// Execute a single step of a framework against the provided facts.
    ///
    /// Builds an LLM prompt from the framework template and facts.
    /// MVP: returns a placeholder result with the prompt text as output.
    public func executeStep(
        framework: ArticleFramework,
        stepId: String,
        facts: [String]
    ) async throws -> ArticleStepResult {
        guard let stepDef = framework.steps.first(where: { $0.id == stepId }) else {
            throw FrameworkEngineError.stepNotFound(stepId: stepId)
        }

        let prompt: String = buildPrompt(framework: framework, step: stepDef, facts: facts)

        var result: [String: String] = ["prompt": prompt]
        if let executor = promptExecutor {
            let llmOutput: String = try await executor(prompt)
            result["analysis"] = llmOutput
            result["status"] = "completed"
        } else {
            result["status"] = "LLM 未配置 — 仅返回提示词"
        }

        return ArticleStepResult(
            stepId: stepId,
            completed: true,
            output: result
        )
    }

    // MARK: - Prompt Building

    private func buildPrompt(
        framework: ArticleFramework,
        step: ArticleStepDefinition,
        facts: [String]
    ) -> String {
        let factsSection: String = facts.enumerated()
            .map { "  \($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")

        return """
            ## 法律框架: \(framework.name)
            ### 法律依据: \(framework.lawRef)
            ### 审查指南参考: \(framework.guidelineRef ?? "无")

            ## 当前步骤: \(step.name)
            ### 适用法条: \(step.ruleRef)
            ### 输入指引: \(step.inputHint)

            ## 案件事实:
            \(factsSection)

            ## 任务:
            请基于上述法律框架和案件事实，完成"\(step.name)"步骤的法律判断。
            请输出结构化的分析结果，包括：
            - 适用的法律条款及解释
            - 事实与法律的对应分析
            - 该步骤的初步结论
            """
    }
}

// MARK: - Errors

public enum FrameworkEngineError: Error, Sendable {
    case stepNotFound(stepId: String)
    case frameworkNotFound(articleId: String)
}
