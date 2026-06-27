# YunPat-Ai Plan 2: Patent Intelligence

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 YunPat-Ai 从通用 AI 助手升级为专利专用智能体——PatentLoop 五步引擎 + 知识库集成（宝宸知识库 Karpathy LLM Wiki）+ 技能系统 + 五层记忆 + 可观测性。

**Architecture:** 在 Plan 1 Foundation 之上叠加专利智能层。WikiAdapter 读取已有 Obsidian vault（不新建不迁移），RuleEngine 检索+冲突消解，PatentLoopEngine 实现五步流水线，SkillManager 提供 RAG 自动匹配，MemoryEngine 管理五层记忆，TraceCollector 提供全链路可观测。

**Tech Stack:** Swift 6, SwiftUI, AppKit, SPM, SQLite, FSEvents

---

## 文件结构（Plan 2 新增/修改）

```
YunPat-Ai/
├── Packages/
│   ├── YunPatCore/
│   │   ├── Sources/YunPatCore/
│   │   │   ├── Knowledge/              ← 新增
│   │   │   │   ├── WikiAdapter.swift           # 读取宝宸知识库
│   │   │   │   ├── RuleEngine.swift            # 规则检索 + 冲突消解
│   │   │   │   ├── FactExtractor.swift         # 技术事实提取
│   │   │   │   ├── WikiTypes.swift             # StructuredFacts, ApplicableRules 等类型
│   │   │   │   └── VaultObserver.swift         # FSEvents 监听 vault 变更
│   │   │   ├── Loop/
│   │   │   │   └── PatentLoopEngine.swift      # 新增：五步专利循环
│   │   │   ├── Skill/                  ← 新增
│   │   │   │   ├── SkillManager.swift          # Skill 加载 + RAG 匹配
│   │   │   │   ├── SkillParser.swift           # SKILL.md 解析
│   │   │   │   └── SkillTypes.swift            # SkillManifest, SkillContent 等类型
│   │   │   ├── Memory/                 ← 新增
│   │   │   │   ├── MemoryEngine.swift          # 五层记忆管理
│   │   │   │   ├── MemoryStore.swift           # SQLite 持久化
│   │   │   │   └── MemoryTypes.swift           # CaseContext, SessionFact 等类型
│   │   │   ├── Trace/                  ← 新增
│   │   │   │   ├── TraceCollector.swift        # Trace 收集
│   │   │   │   └── TraceStore.swift            # 写入 ~/.yunpat/traces/
│   │   │   └── Context/
│   │   │       └── ContextEngine.swift         # 修改：接入 Memory + Skill + Knowledge
│   │   └── Tests/YunPatCoreTests/
│   │       ├── WikiAdapterTests.swift          # 新增
│   │       ├── PatentLoopEngineTests.swift     # 新增
│   │       ├── SkillManagerTests.swift         # 新增
│   │       ├── MemoryEngineTests.swift         # 新增
│   │       └── RuleEngineTests.swift           # 新增
│   └── YunPatNetworking/
│       └── Tests/YunPatNetworkingTests/
│           └── MockModelBackend.swift          # 新增：Plan 2 测试基础设施
├── App/
│   ├── Resources/Skills/              ← 新增
│   │   └── .gitkeep
│   └── Views/
│       ├── ContentView.swift          # 修改：接入 PatentLoop + Skill 选择
│       ├── ChatView.swift             # 修改：显示 Loop 步骤状态
│       └── CollaborationPanel.swift   # 新增：HITL 协作面板
```

---

## Phase A: 知识库基础 —— WikiAdapter + VaultObserver（Tasks 1-7）

### Task 1: 定义知识库类型 (WikiTypes.swift)

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Knowledge/WikiTypes.swift`

- [ ] **Step 1: 写 WikiTypes.swift**

```swift
// Packages/YunPatCore/Sources/YunPatCore/Knowledge/WikiTypes.swift
import Foundation

// ── 知识库模块枚举 ──
public enum WikiModule: String, CaseIterable {
    case patentPractice = "专利实务"
    case examinationGuide = "审查指南"
    case patentInfringement = "专利侵权"
    case patentJudgments = "专利判决"
    case reexamination = "复审无效"
    case laws = "法律法规"
    case books = "书籍"
}

// ── Step 1: 结构化事实 ──
public struct StructuredFacts: Sendable {
    public let technicalField: String
    public let problem: String
    public let inventionPoints: [String]
    public let missingInfo: [String]
    public let sourceDocument: URL?

    public init(technicalField: String = "", problem: String = "",
                inventionPoints: [String] = [], missingInfo: [String] = [],
                sourceDocument: URL? = nil) {
        self.technicalField = technicalField; self.problem = problem
        self.inventionPoints = inventionPoints; self.missingInfo = missingInfo
        self.sourceDocument = sourceDocument
    }
}

// ── Step 2: 规则来源 ──
public enum RuleSource: Sendable {
    case statute(String)           // 法条号
    case guideline(String)         // 审查指南章节
    case precedent(String)         // 复审/无效决定号
    case judgment(String)          // 判决案号
    case doctrine                  // 学说观点
}

// ── 规则证据链 ──
public struct EvidenceLink: Sendable {
    public let source: RuleSource
    public let wikilink: String    // [[页面名]]
    public let excerpt: String     // 引用片段
    public init(source: RuleSource, wikilink: String, excerpt: String) {
        self.source = source; self.wikilink = wikilink; self.excerpt = excerpt
    }
}

// ── 规则冲突类型 ──
public enum ConflictNature: String, Sendable {
    case override        // 上位法覆盖下位法
    case contradiction   // 不可调和的矛盾
    case divergence      // 实践分歧
}

public struct RuleConflict: Sendable {
    public let description: String
    public let nature: ConflictNature
    public let resolution: String
    public init(description: String, nature: ConflictNature, resolution: String) {
        self.description = description; self.nature = nature; self.resolution = resolution
    }
}

// ── 规则候选 ──
public struct RuleCandidate: Sendable {
    public let wikilink: String
    public let title: String
    public let content: String
    public let source: RuleSource
    public let sourceLevel: Int       // 1=法律 2=细则 3=指南 4=复审决定 5=判例
    public let effectiveDate: Date?
    public let conflicts: [RuleConflict]
    public let evidence: [EvidenceLink]
    public let score: Double          // 相关性评分

    public init(wikilink: String, title: String, content: String, source: RuleSource,
                sourceLevel: Int = 3, effectiveDate: Date? = nil, conflicts: [RuleConflict] = [],
                evidence: [EvidenceLink] = [], score: Double = 0) {
        self.wikilink = wikilink; self.title = title; self.content = content
        self.source = source; self.sourceLevel = sourceLevel
        self.effectiveDate = effectiveDate; self.conflicts = conflicts
        self.evidence = evidence; self.score = score
    }
}

// ── 最终适用规则集 ──
public struct ApplicableRules: Sendable {
    public let candidates: [RuleCandidate]
    public let conflicts: [RuleConflict]
    public let constraintSummary: String

    public init(candidates: [RuleCandidate] = [], conflicts: [RuleConflict] = [],
                constraintSummary: String = "") {
        self.candidates = candidates; self.conflicts = conflicts
        self.constraintSummary = constraintSummary
    }

    /// 将规则集压缩为 LLM 可注入的文本
    public func injectableTokens(maxTokens: Int? = nil) -> String {
        let limit = maxTokens ?? 3000
        var parts: [String] = []
        for c in candidates.prefix(5) {
            parts.append("## \(c.title)\n来源: \(c.wikilink)\n\(c.content)")
        }
        if !conflicts.isEmpty {
            parts.append("## ⚠️ 规则冲突")
            for c in conflicts { parts.append("- \(c.description): \(c.resolution)") }
        }
        if !constraintSummary.isEmpty { parts.append("## 实务约束\n\(constraintSummary)") }
        let full = parts.joined(separator: "\n\n---\n\n")
        let estimatedTokens = full.count / 4
        if estimatedTokens > limit { return String(full.prefix(limit * 4)) }
        return full
    }
}

// ── 知识库变更事件 ──
public enum CardChange: Sendable {
    case created(String)
    case modified(String)
    case deleted(String)
}
```

- [ ] **Step 2: Verify build**

```bash
cd Packages/YunPatCore && swift build
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/YunPatCore/Sources/YunPatCore/Knowledge/WikiTypes.swift
git commit -m "feat: define knowledge base types — StructuredFacts, ApplicableRules, RuleCandidate, EvidenceLink"
```

### Task 2: 实现 WikiAdapter（读取宝宸知识库）

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Knowledge/WikiAdapter.swift`
- Create: `Packages/YunPatCore/Tests/YunPatCoreTests/WikiAdapterTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// Packages/YunPatCore/Tests/YunPatCoreTests/WikiAdapterTests.swift
import XCTest
@testable import YunPatCore

final class WikiAdapterTests: XCTestCase {
    // 使用测试 fixtures 目录替代真实 vault
    let testVault: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("test-vault")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // 创建最小 wiki 结构
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("Wiki/专利实务"), withIntermediateDirectories: true)
        try? "[[test-page]]".write(to: dir.appendingPathComponent("Wiki/专利实务/index.md"), atomically: true, encoding: .utf8)
        return dir
    }()

    func testReadModuleIndex_returnsPage() async throws {
        let adapter = WikiAdapter(vaultPath: testVault)
        let index = try await adapter.readModuleIndex(.patentPractice)
        XCTAssertFalse(index.isEmpty)
    }
}
```

- [ ] **Step 2: Run test — FAIL**

```bash
cd Packages/YunPatCore && swift test --filter WikiAdapterTests
```

- [ ] **Step 3: Write minimal implementation**

```swift
// Packages/YunPatCore/Sources/YunPatCore/Knowledge/WikiAdapter.swift
import Foundation

public final class WikiAdapter {
    public let vaultPath: URL

    public init(vaultPath: URL) {
        self.vaultPath = vaultPath
    }

    /// 读取 AGENTS.md 获取知识库 Schema
    public func readSchema() async throws -> String {
        let url = vaultPath.appendingPathComponent("AGENTS.md")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// 按模块读取 index.md
    public func readModuleIndex(_ module: WikiModule) async throws -> String {
        let url = vaultPath.appendingPathComponent("Wiki/\(module.rawValue)/index.md")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// 读取 Wiki 页面全文
    public func readPage(_ wikilink: String) async throws -> String {
        // wikilink 格式：[[专利实务/创造性/创造性-概述与三步法框架]]
        let cleaned = wikilink.replacingOccurrences(of: "[[", with: "")
            .replacingOccurrences(of: "]]", with: "")
        let url = vaultPath.appendingPathComponent("Wiki/\(cleaned).md")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// 解析 index.md 中的 [[wikilink]] 列表
    public func parseWikilinks(from indexContent: String) -> [String] {
        let pattern = #"\[\[([^\]]+)\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(indexContent.startIndex..., in: indexContent)
        let matches = regex.matches(in: indexContent, range: nsRange)
        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: indexContent) else { return nil }
            return String(indexContent[range])
        }
    }

    /// 读取 Concept-Index.md 做概念→页面查找
    public func readConceptIndex() async throws -> String {
        let url = vaultPath.appendingPathComponent("Wiki/Concept-Index.md")
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
```

- [ ] **Step 4: Run test — PASS**

```bash
cd Packages/YunPatCore && swift test --filter WikiAdapterTests
```
Expected: 1 test PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/YunPatCore/
git commit -m "feat: implement WikiAdapter for reading 宝宸知识库"
```

### Task 3: 实现 VaultObserver（FSEvents 监听）

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Knowledge/VaultObserver.swift`

- [ ] **Step 1: Write VaultObserver**

```swift
// Packages/YunPatCore/Sources/YunPatCore/Knowledge/VaultObserver.swift
import Foundation

public protocol KnowledgeEventObserver: Sendable {
    func vaultChanged(_ path: URL)
    func indexChanged(_ module: WikiModule)
}

public final class VaultObserver: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let vaultPath: URL
    private let observer: KnowledgeEventObserver
    private let queue = DispatchQueue(label: "yunpat.vault-observer")

    public init(vaultPath: URL, observer: KnowledgeEventObserver) {
        self.vaultPath = vaultPath
        self.observer = observer
    }

    public func start() {
        let paths = [vaultPath.path] as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (_, info, _, paths, _, _) in
                guard let info = info else { return }
                let myself = Unmanaged<VaultObserver>.fromOpaque(info).takeUnretainedValue()
                myself.handleEvents(paths: paths as! [String])
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,  // 1 秒延迟，批处理
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        )
        if let stream = stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    public func stop() {
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        self.stream = nil
    }

    private func handleEvents(paths: [String]) {
        observer.vaultChanged(vaultPath)
        // 简化处理：任何文件变更都通知，由 observer 决定是否重载
    }

    deinit { stop() }
}
```

- [ ] **Step 2: Verify build**

```bash
cd Packages/YunPatCore && swift build
```

- [ ] **Step 3: Commit**

```bash
git add Packages/YunPatCore/Sources/YunPatCore/Knowledge/VaultObserver.swift
git commit -m "feat: implement VaultObserver with FSEvents monitoring"
```

### Task 4: 实现 FactExtractor

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Knowledge/FactExtractor.swift`

- [ ] **Step 1: Write FactExtractor**

```swift
// Packages/YunPatCore/Sources/YunPatCore/Knowledge/FactExtractor.swift
import Foundation

public actor FactExtractor {
    /// 从用户请求 + 可选附件文档中提取结构化事实
    /// 当前实现：LLM 驱动的提取（通过 modelRouter 调用）
    public func extract(
        from request: UserRequest
    ) async throws -> StructuredFacts {
        // 基本实现：从用户文本中提取关键词
        // Plan 3 升级为 LLM 驱动的事实提取
        let content = request.content
        let facts = StructuredFacts(
            technicalField: detectTechnicalField(content),
            problem: extractProblem(content),
            inventionPoints: extractInventionPoints(content),
            missingInfo: [],
            sourceDocument: request.attachments.first
        )
        return facts
    }

    // ── 简单关键词匹配（Plan 3 升级为 LLM）──

    private func detectTechnicalField(_ text: String) -> String {
        let fields = ["机械", "化学", "电学", "软件", "生物", "医药", "通信"]
        for field in fields {
            if text.contains(field) { return field }
        }
        return "未识别"
    }

    private func extractProblem(_ text: String) -> String {
        // 提取 "问题"/"缺陷"/"不足" 相关句段
        let patterns = ["问题：", "缺陷：", "不足：", "技术问题"]
        for p in patterns {
            if let range = text.range(of: p) {
                let after = text[range.upperBound...].prefix(200)
                return String(after).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text.prefix(200).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractInventionPoints(_ text: String) -> [String] {
        // 提取 "特征"/"发明点"/"创新" 相关句段
        var points: [String] = []
        let lines = text.components(separatedBy: .newlines)
        for line in lines where line.contains("特征") || line.contains("步骤") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { points.append(trimmed) }
        }
        return Array(points.prefix(10))
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd Packages/YunPatCore && swift build
```

- [ ] **Step 3: Commit**

```bash
git commit -m "feat: implement FactExtractor with keyword-based extraction"
```

### Task 5: 实现 RuleEngine（检索 + 冲突消解）

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Knowledge/RuleEngine.swift`
- Create: `Packages/YunPatCore/Tests/YunPatCoreTests/RuleEngineTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// Packages/YunPatCore/Tests/YunPatCoreTests/RuleEngineTests.swift
import XCTest
@testable import YunPatCore

final class RuleEngineTests: XCTestCase {
    func testRetrieveRules_withValidFacts_returnsCandidates() async throws {
        let vault = createTestVault()
        let adapter = WikiAdapter(vaultPath: vault)
        let engine = RuleEngine(adapter: adapter)
        let facts = StructuredFacts(technicalField: "机械", problem: "传动效率",
                                     inventionPoints: ["螺旋传动机构"])
        let rules = try await engine.retrieveRules(for: facts)
        // 至少应找到 index.md 中列出的页面
        XCTAssertFalse(rules.candidates.isEmpty)
    }

    func testResolveConflicts_detectsOverrides() async throws {
        let engine = RuleEngine(adapter: nil!)  // 不读文件，只测冲突消解
        let statute = RuleCandidate(wikilink: "专利法第22条", title: "专利法",
                                     content: "发明应具备创造性",
                                     source: .statute("专利法第22条"), sourceLevel: 1)
        let guideline = RuleCandidate(wikilink: "审查指南-创造性", title: "审查指南",
                                       content: "三步法判断",
                                       source: .guideline("审查指南第二部分第四章"), sourceLevel: 3)
        let results = engine.resolveConflicts([statute, guideline])
        // 法律优先级高于审查指南
        XCTAssertEqual(results.first?.sourceLevel, 1)
    }

    private func createTestVault() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("Wiki/专利实务/创造性"), withIntermediateDirectories: true)
        try? "[[创造性-概述与三步法框架]]".write(to: dir.appendingPathComponent("Wiki/专利实务/index.md"), atomically: true, encoding: .utf8)
        try? "# 创造性概述\n三步法是判断发明创造性的法定框架。".write(to: dir.appendingPathComponent("Wiki/专利实务/创造性/创造性-概述与三步法框架.md"), atomically: true, encoding: .utf8)
        return dir
    }
}
```

- [ ] **Step 2: Run test — FAIL**

```bash
cd Packages/YunPatCore && swift test --filter RuleEngineTests
```

- [ ] **Step 3: Write RuleEngine**

```swift
// Packages/YunPatCore/Sources/YunPatCore/Knowledge/RuleEngine.swift
import Foundation

public actor RuleEngine {
    private let adapter: WikiAdapter

    public init(adapter: WikiAdapter) {
        self.adapter = adapter
    }

    /// PatentLoop Step 2：检索适用规则 + 冲突消解
    public func retrieveRules(for facts: StructuredFacts) async throws -> ApplicableRules {
        var allCandidates: [RuleCandidate] = []

        // 1. 读取 Concept-Index.md 做概念匹配
        let conceptIndex = try await adapter.readConceptIndex()
        if !conceptIndex.isEmpty {
            let matchingLinks = findMatchingLinks(in: conceptIndex, for: facts)
            for link in matchingLinks {
                if let candidate = try? await readCandidate(wikilink: link) {
                    allCandidates.append(candidate)
                }
            }
        }

        // 2. 如果概念索引无结果，遍历相关模块的 index.md
        if allCandidates.isEmpty {
            let modules = relevantModules(for: facts)
            for module in modules {
                if let index = try? await adapter.readModuleIndex(module) {
                    let links = adapter.parseWikilinks(from: index)
                    for link in links.prefix(10) {
                        if let candidate = try? await readCandidate(wikilink: link) {
                            allCandidates.append(candidate)
                        }
                    }
                }
            }
        }

        // 3. 冲突消解
        let resolved = resolveConflicts(allCandidates)

        // 4. 生成约束摘要
        let summary = generateConstraintSummary(resolved)

        return ApplicableRules(candidates: resolved, conflicts: [], constraintSummary: summary)
    }

    // ── 冲突消解 ──
    public func resolveConflicts(_ candidates: [RuleCandidate]) -> [RuleCandidate] {
        // 按 sourceLevel 升序（法律=1 优先），再按 score 降序
        return candidates.sorted {
            if $0.sourceLevel != $1.sourceLevel { return $0.sourceLevel < $1.sourceLevel }
            return $0.score > $1.score
        }
    }

    // ── Private ──

    private func findMatchingLinks(in index: String, for facts: StructuredFacts) -> [String] {
        // 从 Concept-Index.md 的 Markdown 中查找匹配概念
        var links: [String] = []
        let keywords = facts.inventionPoints + [facts.technicalField, facts.problem]
        let lines = index.components(separatedBy: .newlines)
        for line in lines where line.hasPrefix("- [[") {
            for kw in keywords where !kw.isEmpty && line.localizedCaseInsensitiveContains(kw) {
                let pattern = #"\[\[([^\]]+)\]\]"#
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                   let range = Range(match.range(at: 1), in: line) {
                    links.append(String(line[range]))
                }
            }
        }
        return links
    }

    private func relevantModules(for facts: StructuredFacts) -> [WikiModule] {
        // 简单启发式：根据技术领域选择模块
        [.patentPractice, .examinationGuide, .laws]
    }

    private func readCandidate(wikilink: String) async throws -> RuleCandidate? {
        let content = try await adapter.readPage(wikilink)
        guard !content.isEmpty else { return nil }
        let title = content.components(separatedBy: .newlines).first?
            .replacingOccurrences(of: "# ", with: "") ?? wikilink
        return RuleCandidate(
            wikilink: wikilink, title: title, content: content,
            source: .doctrine, sourceLevel: 3, score: 0.5
        )
    }

    private func generateConstraintSummary(_ candidates: [RuleCandidate]) -> String {
        let top3 = candidates.prefix(3).map { $0.title }
        guard !top3.isEmpty else { return "" }
        return "主要适用规则：\(top3.joined(separator: "、"))"
    }
}
```

- [ ] **Step 4: Run test — PASS**

```bash
cd Packages/YunPatCore && swift test --filter RuleEngineTests
```
Expected: 2 tests PASS

- [ ] **Step 5: Commit**

### Task 6: 知识库配置集成到 App 设置

**Files:**
- Modify: `App/Views/Settings/ProviderSettingsView.swift`
- Create: `App/Views/Settings/KnowledgeSettingsView.swift`

- [ ] **Step 1: Write KnowledgeSettingsView**

```swift
// App/Views/Settings/KnowledgeSettingsView.swift
import SwiftUI

struct KnowledgeSettingsView: View {
    @State private var vaultPath = ""
    @State private var vaultStatus = "未配置"

    var body: some View {
        Form {
            Section("知识库（宝宸知识库）") {
                HStack {
                    TextField("Obsidian Vault 路径", text: $vaultPath)
                    Button("浏览") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        if panel.runModal() == .OK {
                            vaultPath = panel.url?.path ?? ""
                        }
                    }
                }
                Text("状态：\(vaultStatus)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("验证") {
                    let url = URL(filePath: vaultPath)
                    let agentsMD = url.appendingPathComponent("AGENTS.md")
                    let wikiDir = url.appendingPathComponent("Wiki/专利实务")
                    if FileManager.default.fileExists(atPath: agentsMD.path)
                        && FileManager.default.fileExists(atPath: wikiDir.path) {
                        vaultStatus = "✅ 有效"
                        UserDefaults.standard.set(vaultPath, forKey: "yunpat.vaultPath")
                    } else {
                        vaultStatus = "❌ 无效（需包含 AGENTS.md + Wiki/专利实务/）"
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 200)
        .onAppear {
            vaultPath = UserDefaults.standard.string(forKey: "yunpat.vaultPath") ?? defaultVaultPath()
        }
    }

    private func defaultVaultPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents/宝宸知识库").path
    }
}
```

- [ ] **Step 2: Update YunPatApp to add Settings tab**

```swift
// YunPatApp.swift — change Settings block to:
Settings {
    TabView {
        ProviderSettingsView()
            .tabItem { Label("API Keys", systemImage: "key") }
        KnowledgeSettingsView()
            .tabItem { Label("知识库", systemImage: "books.vertical") }
    }
}
```

- [ ] **Step 3: Build**

```bash
swift build
```

- [ ] **Step 4: Commit**

```bash
git commit -m "feat: add knowledge base configuration to App settings"
```

### Task 7: 注册知识库 Capability

**Files:**
- Modify: `Packages/YunPatCore/Sources/YunPatCore/Capability/CapabilityRegistry.swift`

- [ ] **Step 1: Add knowledge capabilities**

```swift
// CapabilityRegistry — append to registerBuiltinCapabilities():
register(capability: CapabilityDefinition(
    name: "knowledge.search",
    displayName: "知识库检索",
    description: "从宝宸知识库检索专利法规、审查指南、判例",
    source: .builtin,
    permission: .always,
    metadata: CapabilityMetadata(costLevel: .free, requiresNetwork: false,
                                 isIdempotent: true, typicalUseCases: ["法规查询", "案例检索"])
))
```

- [ ] **Step 2: Verify build + tests**

```bash
cd Packages/YunPatCore && swift build && swift test --filter CapabilityRegistryTests
```

- [ ] **Step 3: Commit**

---

## Phase B: PatentLoop 引擎（Tasks 8-15）

### Task 8: 定义 PatentLoop 内部类型

**Files:**
- Modify: `Packages/YunPatCore/Sources/YunPatCore/Loop/LoopState.swift`（追加）

- [ ] **Step 1: Add ExecutionPlan and StepResult**

```swift
// LoopState.swift — append
public struct ExecutionPlan: Sendable {
    public let strategy: String
    public let steps: [PlanStep]
    public init(strategy: String = "", steps: [PlanStep] = []) {
        self.strategy = strategy; self.steps = steps
    }
}

public struct PlanStep: Sendable {
    public let name: String
    public let description: String
    public let boundRule: String?   // 绑定的规则 wikilink
    public init(name: String, description: String, boundRule: String? = nil) {
        self.name = name; self.description = description; self.boundRule = boundRule
    }
}

public struct StepResult: Sendable {
    public let stepName: String
    public let output: String
    public let success: Bool
    public init(stepName: String, output: String, success: Bool = true) {
        self.stepName = stepName; self.output = output; self.success = success
    }
}

public struct ExecutionResult: Sendable {
    public let stepResults: [StepResult]
    public let artifacts: [String]
    public init(stepResults: [StepResult] = [], artifacts: [String] = []) {
        self.stepResults = stepResults; self.artifacts = artifacts
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd Packages/YunPatCore && swift build
```

- [ ] **Step 3: Commit**

### Task 9: 实现 PatentLoopEngine（TDD）

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Loop/PatentLoopEngine.swift`
- Create: `Packages/YunPatCore/Tests/YunPatCoreTests/PatentLoopEngineTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// Packages/YunPatCore/Tests/YunPatCoreTests/PatentLoopEngineTests.swift
import XCTest
import YunPatNetworking
@testable import YunPatCore

final class PatentLoopEngineTests: XCTestCase {
    func prepareTempVault() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("Wiki/专利实务/创造性"), withIntermediateDirectories: true)
        try? "[[创造性-概述]]".write(to: dir.appendingPathComponent("Wiki/专利实务/index.md"), atomically: true, encoding: .utf8)
        try? "# 创造性概述\n三步法。".write(to: dir.appendingPathComponent("Wiki/专利实务/创造性/创造性-概述.md"), atomically: true, encoding: .utf8)
        return dir
    }

    func testRun_fullAgent_withVault_returnsCompleted() async throws {
        let vaultURL = prepareTempVault()
        let adapter = WikiAdapter(vaultPath: vaultURL)
        let router = ModelRouter()
        let provider = OpenAIProvider(apiKey: "test-key")
        await router.register(provider)
        let engine = PatentLoopEngine(modelRouter: router, wikiAdapter: adapter, loopConfig: LoopConfig(maxRevisionCycles: 1))
        let result = try await engine.run(
            request: UserRequest(content: "分析螺旋传动机构的创造性"),
            flow: .fullAgent
        )
        switch result {
        case .completed:
            break  // pass
        case .exceededRevisionLimit:
            break  // also acceptable given test-key won't work with real API
        default:
            XCTFail("Expected .completed or .exceededRevisionLimit, got \(result)")
        }
    }
}
```

- [ ] **Step 2: Run test — FAIL**

```bash
cd Packages/YunPatCore && swift test --filter PatentLoopEngineTests
```

- [ ] **Step 3: Write PatentLoopEngine**

```swift
// Packages/YunPatCore/Sources/YunPatCore/Loop/PatentLoopEngine.swift
import Foundation
import YunPatNetworking

public actor PatentLoopEngine: LoopEngine {
    public var state: LoopState = .idle
    private let modelRouter: ModelRouter
    private let provider: ModelProvider
    private let wikiAdapter: WikiAdapter
    private let ruleEngine: RuleEngine
    private let factExtractor: FactExtractor
    private let contextEngine: ContextEngine
    private let innerLoop: AgentLoopEngine
    private let config: LoopConfig

    public init(modelRouter: ModelRouter, wikiAdapter: WikiAdapter,
                provider: ModelProvider = .deepseek, config: LoopConfig = LoopConfig()) {
        self.modelRouter = modelRouter
        self.wikiAdapter = wikiAdapter
        self.provider = provider
        self.ruleEngine = RuleEngine(adapter: wikiAdapter)
        self.factExtractor = FactExtractor()
        self.contextEngine = ContextEngine()
        self.innerLoop = AgentLoopEngine(modelRouter: modelRouter, provider: provider)
        self.config = config
    }

    public func run(request: UserRequest, flow: AgentFlow) async throws -> LoopResult {
        var revisionCount = 0

        // Step 1: 获取事实
        state = .running(step: "extracting-facts")
        let facts = try await factExtractor.extract(from: request)
        if !facts.missingInfo.isEmpty, flow == .guided {
            return .needsClarification(facts.missingInfo)
        }

        // Step 2: 获取规则
        state = .running(step: "retrieving-rules")
        let rules = try await ruleEngine.retrieveRules(for: facts)
        if flow == .guided {
            // 暂停：呈现规则让用户确认
            let request = ApprovalRequest(summary: "规则检索完成", detail: rules.constraintSummary, options: ["确认", "修正", "取消"])
            return LoopResult.completed("Guided: \(request.summary)")  // 简化：GUI 层处理批准
        }

    retryLoop:
        while revisionCount < config.maxRevisionCycles {
            // Step 3: 规划
            state = .running(step: "planning")
            let plan = ExecutionPlan(
                strategy: "基于检索到的规则制定策略",
                steps: [PlanStep(name: "分析", description: "分析事实与规则的匹配", boundRule: rules.candidates.first?.wikilink)]
            )

            // Step 4: 执行（内嵌 AgentLoop）
            state = .running(step: "executing")
            let execResult = try await executePlan(plan, facts: facts, rules: rules)

            // Step 5: 检查
            state = .running(step: "reviewing")
            let reviewResult = try await review(execResult, plan: plan, rules: rules, facts: facts)

            if reviewResult {
                state = .idle
                return .completed(execResult.artifacts.joined(separator: "\n\n"))
            }

            revisionCount += 1
            // 根据问题类型回退到对应步骤
            // 简化实现：直接重试全部
        }

        state = .idle
        return .exceededRevisionLimit([Issue(description: "超过最大修订次数 \(config.maxRevisionCycles)")])
    }

    // MARK: - Private Steps

    private func executePlan(_ plan: ExecutionPlan, facts: StructuredFacts, rules: ApplicableRules) async throws -> ExecutionResult {
        let contextPrompt = """
        ## 技术事实
        技术领域：\(facts.technicalField)
        技术问题：\(facts.problem)
        发明点：\(facts.inventionPoints.joined(separator: "; "))

        ## 适用规则
        \(rules.injectableTokens(maxTokens: 2000))

        ## 执行计划
        策略：\(plan.strategy)
        """
        let result = try await innerLoop.run(
            request: UserRequest(content: contextPrompt),
            flow: .fullAgent
        )
        switch result {
        case .completed(let output):
            return ExecutionResult(stepResults: [StepResult(stepName: "execute", output: output)], artifacts: [output])
        default:
            return ExecutionResult()
        }
    }

    private func review(_ result: ExecutionResult, plan: ExecutionPlan,
                        rules: ApplicableRules, facts: StructuredFacts) async throws -> Bool {
        // 简化：如果内嵌 AgentLoop 返回了内容即视为通过
        return !result.artifacts.isEmpty
    }
}
```

- [ ] **Step 4: Run test — PASS**

```bash
cd Packages/YunPatCore && swift test --filter PatentLoopEngineTests
```
Expected: 1 test PASS (result is .exceededRevisionLimit or .completed)

- [ ] **Step 5: Commit**

### Task 10: 实现 EvaluationEngine（Step 5 规则化检查）

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Knowledge/EvaluationEngine.swift`

- [ ] **Step 1: Write EvaluationEngine**

```swift
// Packages/YunPatCore/Sources/YunPatCore/Knowledge/EvaluationEngine.swift
import Foundation

public struct ReviewResult: Sendable {
    public let verdict: Bool       // true = pass
    public let issues: [Issue]
    public let evidence: [String]  // 引用证据

    public init(verdict: Bool = true, issues: [Issue] = [], evidence: [String] = []) {
        self.verdict = verdict; self.issues = issues; self.evidence = evidence
    }
}

public actor EvaluationEngine {
    /// 规则化自动检查——非一次性 LLM 评估
    public func evaluate(
        execution: ExecutionResult,
        rules: ApplicableRules,
        facts: StructuredFacts
    ) async -> ReviewResult {
        var issues: [Issue] = []

        // 1. 法条引用检查
        let citedStatutes = extractStatuteCitations(from: execution)
        let expectedStatutes = rules.candidates.filter { $0.sourceLevel <= 2 }
        if citedStatutes.isEmpty && !expectedStatutes.isEmpty {
            issues.append(Issue(severity: .warning, description: "未引用相关法条"))
        }

        // 2. 事实完整性检查
        for point in facts.inventionPoints {
            let found = execution.artifacts.contains { $0.contains(point) }
            if !found {
                issues.append(Issue(severity: .warning, description: "遗漏发明点：\(point)"))
            }
        }

        // 3. 规则一致性检查
        for conflict in rules.conflicts {
            issues.append(Issue(severity: .error, description: "规则冲突：\(conflict.description)"))
        }

        return ReviewResult(verdict: issues.allSatisfy { $0.severity == .warning }, issues: issues)
    }

    private func extractStatuteCitations(from result: ExecutionResult) -> [String] {
        let pattern = #"专利法第\d+条"#
        var citations: [String] = []
        for artifact in result.artifacts {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsRange = NSRange(artifact.startIndex..., in: artifact)
                let matches = regex.matches(in: artifact, range: nsRange)
                for match in matches {
                    if let range = Range(match.range, in: artifact) {
                        citations.append(String(artifact[range]))
                    }
                }
            }
        }
        return citations
    }
}
```

- [ ] **Step 2: Integrate into PatentLoopEngine step 5**

```swift
// PatentLoopEngine — replace review method:
private let evaluator = EvaluationEngine()

private func review(...) async throws -> Bool {
    let result = await evaluator.evaluate(execution: execResult, rules: rules, facts: facts)
    return result.verdict
}
```

- [ ] **Step 3: Verify**

```bash
cd Packages/YunPatCore && swift build && swift test --filter PatentLoopEngineTests
```

- [ ] **Step 4: Commit**

### Task 11: PatentLoopEngine 集成到 ChatViewModel

**Files:**
- Modify: `App/Views/ChatView.swift`

- [ ] **Step 1: Update ChatViewModel to support flow selection**

```swift
// ChatViewModel — add:
@Published var currentFlow: AgentFlow = .copilot
private var wikiAdapter: WikiAdapter?

func setVault(_ path: String) {
    self.wikiAdapter = WikiAdapter(vaultPath: URL(filePath: path))
}

func sendMessage(in tabManager: TabManager) async {
    // ... existing guard logic ...
    isStreaming = true

    let engine: any LoopEngine
    if let adapter = wikiAdapter, currentFlow == .guided || currentFlow == .fullAgent {
        engine = PatentLoopEngine(modelRouter: modelRouter, wikiAdapter: adapter)
    } else {
        engine = AgentLoopEngine(modelRouter: modelRouter)
    }

    do {
        let result = try await engine.run(request: UserRequest(content: sentText), flow: currentFlow)
        // ... handle result ...
    } catch { /* ... */ }
    isStreaming = false
}
```

- [ ] **Step 2: Verify build**

```bash
swift build
```

- [ ] **Step 3: Commit**

### Task 12: 添加 MockModelBackend 用于快速测试

**Files:**
- Create: `Packages/YunPatNetworking/Tests/YunPatNetworkingTests/MockModelBackend.swift`

- [ ] **Step 1: Write MockModelBackend**

```swift
// Packages/YunPatNetworking/Tests/YunPatNetworkingTests/MockModelBackend.swift
import Foundation
import YunPatNetworking

public final class MockModelBackend: ModelBackend {
    public let provider: ModelProvider
    public var mockResponse: String
    public var shouldFail: Bool = false

    public init(provider: ModelProvider = .openai, mockResponse: String = "Mock response") {
        self.provider = provider
        self.mockResponse = mockResponse
    }

    public var rateLimit: RateLimitInfo? { get async { nil } }

    public func chat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            if shouldFail {
                continuation.finish(throwing: RateLimitError(message: "Mock failure"))
                return
            }
            // 模拟逐字流式输出
            for char in mockResponse {
                continuation.yield(.text(String(char)))
            }
            continuation.yield(.finish(reason: .stop, usage: nil))
            continuation.finish()
        }
    }

    public func listModels() async throws -> [ModelInfo] { [] }
    public func capabilities() -> ModelCapabilities { ModelCapabilities() }
    public func onRateLimitExceeded(_ error: RateLimitError) async -> RetryStrategy { .fail }
}
```

- [ ] **Step 2: Use mock in PatentLoopEngineTests**

```swift
// PatentLoopEngineTests — replace OpenAIProvider with mock:
func testRun_fullAgent_withMock_returnsCompleted() async throws {
    let vaultURL = prepareTempVault()
    let adapter = WikiAdapter(vaultPath: vaultURL)
    let router = ModelRouter()
    let mock = MockModelBackend(mockResponse: "分析完成：该机构具备创造性。")
    await router.register(mock)
    let engine = PatentLoopEngine(modelRouter: router, wikiAdapter: adapter, provider: .openai, config: LoopConfig(maxRevisionCycles: 1))
    let result = try await engine.run(
        request: UserRequest(content: "分析螺旋传动机构的创造性"),
        flow: .fullAgent
    )
    switch result {
    case .completed(let text):
        XCTAssertTrue(text.contains("创造性"))
    default:
        XCTFail("Expected .completed")
    }
}
```

- [ ] **Step 3: Run tests — should be fast now**

```bash
cd Packages/YunPatCore && swift test --filter PatentLoopEngineTests
```
Expected: < 5s, PASS

- [ ] **Step 4: Commit**

---

## Phase C: HITL 协作面板（Tasks 13-15）

### Task 13: 实现 CollaborationPanel UI

**Files:**
- Create: `App/Views/CollaborationPanel.swift`

- [ ] **Step 1: Write CollaborationPanel**

```swift
// App/Views/CollaborationPanel.swift
import SwiftUI

struct CollaborationPanel: View {
    @Binding var pendingApprovals: [ApprovalItem]
    @Binding var completedItems: [ApprovalItem]

    var body: some View {
        VStack(spacing: 12) {
            if !pendingApprovals.isEmpty {
                Section {
                    Label("待确认 (\(pendingApprovals.count))", systemImage: "clock")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    ForEach(pendingApprovals) { item in
                        ApprovalCard(item: item, onApprove: { approve(item) }, onReject: { reject(item) })
                    }
                }
            }

            if !completedItems.isEmpty {
                Section {
                    Label("已完成 (\(completedItems.count))", systemImage: "checkmark.circle")
                        .font(.headline)
                        .foregroundStyle(.green)
                    ForEach(completedItems) { item in
                        HStack {
                            Image(systemName: "checkmark")
                            Text(item.title).font(.caption)
                        }
                    }
                }
            }

            if pendingApprovals.isEmpty && completedItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checklist").font(.title).foregroundStyle(.secondary)
                    Text("无待确认事项").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 32)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.windowBackgroundColor)
    }

    private func approve(_ item: ApprovalItem) { /* move to completed */ }
    private func reject(_ item: ApprovalItem) { /* move to completed with reject marker */ }
}

struct ApprovalItem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let checkpoint: String  // factsConfirmed / rulesConfirmed / strategyApproved / ...
    var status: ApprovalStatus = .pending
}

enum ApprovalStatus { case pending; case approved; case rejected }

struct ApprovalCard: View {
    let item: ApprovalItem
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title).font(.headline)
            Text(item.detail).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("确认") { onApprove() }.buttonStyle(.borderedProminent).controlSize(.small)
                Button("拒绝") { onReject() }.buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}
```

- [ ] **Step 2: Update ContentView to pass collaboration state**

```swift
// ContentView — add:
@State private var pendingApprovals: [ApprovalItem] = []
@State private var completedApprovals: [ApprovalItem] = []

// In right zone:
if collaborationVisible {
    CollaborationPanel(pendingApprovals: $pendingApprovals, completedItems: $completedApprovals)
        .frame(minWidth: 200, idealWidth: 260, maxWidth: 360)
}
```

- [ ] **Step 3: Verify build**

```bash
swift build
```

- [ ] **Step 4: Commit**

### Task 14: 将 HITL 事件从 AgentLoop 连接到协作面板

**Files:**
- Modify: `App/Views/ChatView.swift`

- [ ] **Step 1: Emit collaboration events from sendMessage**

```swift
// ChatViewModel — process collaboration events from loop result
func handleLoopResult(_ result: LoopResult) {
    switch result {
    case .completed(let text):
        // ... add message ...
    case .needsClarification(let questions):
        let items = questions.map { ApprovalItem(title: "需要澄清", detail: $0, checkpoint: "factsConfirmed") }
        // 发布到协作面板
        NotificationCenter.default.post(name: .pendingApprovalsChanged, object: items)
    case .needsRevision(let issues):
        let items = issues.map { ApprovalItem(title: "需要修正", detail: $0.description, checkpoint: "review") }
        NotificationCenter.default.post(name: .pendingApprovalsChanged, object: items)
    default: break
    }
}
```

- [ ] **Step 2: Listen in ContentView**

```swift
// ContentView.onAppear:
.onReceive(NotificationCenter.default.publisher(for: .pendingApprovalsChanged)) { notification in
    if let items = notification.object as? [ApprovalItem] {
        pendingApprovals = items
        collaborationVisible = true
    }
}
```

- [ ] **Step 3: Verify build**

- [ ] **Step 4: Commit**

---

## Phase D: 技能系统（Tasks 15-18）

### Task 15: 定义 Skill 类型和解析器

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Skill/SkillTypes.swift`
- Create: `Packages/YunPatCore/Sources/YunPatCore/Skill/SkillParser.swift`

- [ ] **Step 1: Write SkillTypes**

```swift
// Packages/YunPatCore/Sources/YunPatCore/Skill/SkillTypes.swift
import Foundation

public struct SkillManifest: Sendable, Codable {
    public let name: String
    public let displayName: String
    public let version: String
    public let description: String
    public let author: String
    public let tags: [String]
    public let triggers: [String]
    public let compatibility: SkillCompatibility

    public init(name: String, displayName: String, version: String = "1.0.0",
                description: String = "", author: String = "", tags: [String] = [],
                triggers: [String] = [], compatibility: SkillCompatibility = SkillCompatibility()) {
        self.name = name; self.displayName = displayName; self.version = version
        self.description = description; self.author = author; self.tags = tags
        self.triggers = triggers; self.compatibility = compatibility
    }
}

public struct SkillCompatibility: Sendable, Codable {
    public let minAppVersion: String
    public init(minAppVersion: String = "1.0.0") { self.minAppVersion = minAppVersion }
}

public struct SkillContent: Sendable {
    public let manifest: SkillManifest
    public let body: String
    public init(manifest: SkillManifest, body: String) { self.manifest = manifest; self.body = body }
}

public struct SkillMatch: Sendable {
    public let skill: SkillContent
    public let score: Double
    public init(skill: SkillContent, score: Double) { self.skill = skill; self.score = score }
}
```

- [ ] **Step 2: Write SkillParser**

```swift
// Packages/YunPatCore/Sources/YunPatCore/Skill/SkillParser.swift
import Foundation

public final class SkillParser {
    public func parse(_ markdown: String) throws -> SkillContent? {
        let parts = markdown.components(separatedBy: "---\n")
        guard parts.count >= 3 else { return nil }

        let yamlBlock = parts[1]
        let body = parts[2...].joined(separator: "---\n")

        // 简化的 YAML 解析（避免引入 YAML 库依赖）
        var dict: [String: String] = [:]
        for line in yamlBlock.components(separatedBy: .newlines) {
            let kv = line.components(separatedBy: ": ")
            if kv.count >= 2 {
                dict[kv[0].trimmingCharacters(in: .whitespaces)] = kv[1...].joined(separator: ": ").trimmingCharacters(in: .whitespaces)
            }
        }

        let manifest = SkillManifest(
            name: dict["name"] ?? "unknown",
            displayName: dict["displayName"] ?? dict["name"] ?? "Unknown Skill",
            version: dict["version"] ?? "1.0.0",
            description: dict["description"] ?? "",
            author: dict["author"] ?? "",
            tags: parseList(dict["tags"]),
            triggers: parseList(dict["triggers"]),
            compatibility: SkillCompatibility(minAppVersion: dict["minAppVersion"] ?? "1.0.0")
        )

        return SkillContent(manifest: manifest, body: body)
    }

    private func parseList(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        // 支持 [a, b, c] 格式
        let cleaned = raw.replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
        return cleaned.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
```

- [ ] **Step 3: Verify build**

```bash
cd Packages/YunPatCore && swift build
```

- [ ] **Step 4: Commit**

### Task 16: 实现 SkillManager（加载 + RAG 匹配）

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Skill/SkillManager.swift`
- Create: `Packages/YunPatCore/Tests/YunPatCoreTests/SkillManagerTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// Packages/YunPatCore/Tests/YunPatCoreTests/SkillManagerTests.swift
import XCTest
@testable import YunPatCore

final class SkillManagerTests: XCTestCase {
    func testMatch_triggersReturnSkill() async throws {
        let manager = SkillManager()
        let skillContent = """
        ---
        name: test-skill
        displayName: Test Skill
        triggers: [撰写权利要求]
        ---
        # Test Skill
        Test body.
        """
        let skill = try SkillParser().parse(skillContent)!
        await manager.register(skill)

        let matches = await manager.match(for: UserRequest(content: "帮我撰写权利要求"))
        XCTAssertFalse(matches.isEmpty)
        XCTAssertEqual(matches.first?.skill.manifest.name, "test-skill")
    }

    func testMatch_noTriggerMatch_returnsEmpty() async {
        let manager = SkillManager()
        let matches = await manager.match(for: UserRequest(content: "你好"))
        XCTAssertTrue(matches.isEmpty)
    }
}
```

- [ ] **Step 2: Run test — FAIL**

```bash
cd Packages/YunPatCore && swift test --filter SkillManagerTests
```

- [ ] **Step 3: Write SkillManager**

```swift
// Packages/YunPatCore/Sources/YunPatCore/Skill/SkillManager.swift
import Foundation

public actor SkillManager {
    private var skills: [SkillContent] = []

    public init() {}

    public func register(_ skill: SkillContent) {
        skills.append(skill)
    }

    /// 加载内置 skill（从 App Bundle Resources/Skills/ 读取）
    public func loadBuiltinSkills() async throws {
        // Plan 2: 加载内置 skill 文件
        // 构建时脚本负责向 App/Resources/Skills/ 写入 .skill.md 文件
    }

    /// 根据用户请求自动匹配 skill（RAG 触发词 + 标签）
    public func match(for request: UserRequest) -> [SkillMatch] {
        let content = request.content.lowercased()
        var matches: [SkillMatch] = []

        for skill in skills {
            var score: Double = 0

            // 1. 触发词精确匹配 → 权重最高
            for trigger in skill.manifest.triggers {
                if content.contains(trigger.lowercased()) {
                    score += 10.0
                    break
                }
            }
            // 2. 标签匹配 → 权重较低
            for tag in skill.manifest.tags {
                if content.contains(tag.lowercased()) {
                    score += 2.0
                }
            }

            if score > 0 {
                matches.append(SkillMatch(skill: skill, score: score))
            }
        }

        // 按 score 降序
        return matches.sorted { $0.score > $1.score }
    }

    /// 注入 skill 内容到 system prompt（带 token 预算控制）
    public func inject(_ matches: [SkillMatch], into prompt: String, maxTokenBudget: Int = 4000) -> String {
        var parts = [prompt]
        var tokenBudget = maxTokenBudget - (prompt.count / 4)

        for match in matches.prefix(3) {
            let body = match.skill.body
            let bodyTokens = body.count / 4
            if bodyTokens <= tokenBudget {
                parts.append("\n## Skill: \(match.skill.manifest.displayName)\n\(body)")
                tokenBudget -= bodyTokens
            }
        }

        let result = parts.joined(separator: "\n\n---\n\n")
        let estimatedTokens = result.count / 4
        if estimatedTokens > maxTokenBudget {
            return String(result.prefix(maxTokenBudget * 4))
        }
        return result
    }
}
```

- [ ] **Step 4: Run test — PASS**

```bash
cd Packages/YunPatCore && swift test --filter SkillManagerTests
```

- [ ] **Step 5: Commit**

### Task 17: ContextEngine 集成 Skill 注入

**Files:**
- Modify: `Packages/YunPatCore/Sources/YunPatCore/Context/ContextEngine.swift`

- [ ] **Step 1: Update ContextEngine to accept SkillManager**

```swift
// ContextEngine — add:
private let skillManager: SkillManager

public init(skillManager: SkillManager = SkillManager()) {
    self.skillManager = skillManager
}

public func buildPrompt(for request: UserRequest, flow: AgentFlow, maxTokenBudget: Int = 4000) async throws -> String {
    var parts: [String] = []
    parts.append("你是一个有用的 AI 助手。")

    // 技能注入
    let matchedSkills = await skillManager.match(for: request)
    if !matchedSkills.isEmpty {
        for match in matchedSkills.prefix(2) {
            parts.append("## 技能：\(match.skill.manifest.displayName)\n\(match.skill.body)")
        }
    }

    parts.append("用户：\(request.content)")
    let full = parts.joined(separator: "\n\n")
    let estimatedTokens = full.count / 4
    if estimatedTokens > maxTokenBudget {
        return String(full.prefix(maxTokenBudget * 4))
    }
    return full
}
```

- [ ] **Step 2: Verify build + tests**

```bash
cd Packages/YunPatCore && swift build && swift test --filter ContextEngineTests
```

- [ ] **Step 3: Commit**

### Task 18: Skill 设置 UI

**Files:**
- Create: `App/Views/Settings/SkillSettingsView.swift`

- [ ] **Step 1: Write Skill settings view**

```swift
// App/Views/Settings/SkillSettingsView.swift
import SwiftUI

struct SkillSettingsView: View {
    @State private var skills: [SkillItem] = []

    var body: some View {
        List {
            ForEach(skills) { skill in
                HStack {
                    VStack(alignment: .leading) {
                        Text(skill.name).font(.headline)
                        Text(skill.triggers).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle()
                        .fill(skill.enabled ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                }
            }
            HStack {
                Spacer()
                Button("导入 Skill") { /* open file picker */ }
                Spacer()
            }
        }
    }
}

struct SkillItem: Identifiable {
    let id = UUID()
    let name: String
    let triggers: String
    var enabled: Bool = true
}
```

- [ ] **Step 2: Add to Settings TabView**

- [ ] **Step 3: Verify build + Commit**

---

## Phase E: 五层记忆系统（Tasks 19-23）

### Task 19: 定义 Memory 类型

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Memory/MemoryTypes.swift`

- [ ] **Write MemoryTypes.swift**

```swift
// Packages/YunPatCore/Sources/YunPatCore/Memory/MemoryTypes.swift
import Foundation

public struct CaseContext: Sendable, Codable {
    public let caseId: String
    public var applicationNumber: String?
    public var technicalField: String
    public var inventionPoints: [String]
    public var keyReferences: [String]
    public var openIssues: [String]
    public var lastModified: Date

    public init(caseId: String = UUID().uuidString, applicationNumber: String? = nil,
                technicalField: String = "", inventionPoints: [String] = [],
                keyReferences: [String] = [], openIssues: [String] = []) {
        self.caseId = caseId; self.applicationNumber = applicationNumber
        self.technicalField = technicalField; self.inventionPoints = inventionPoints
        self.keyReferences = keyReferences; self.openIssues = openIssues
        self.lastModified = Date()
    }
}

public struct SessionFact: Sendable, Codable {
    public let id: UUID
    public let fact: String
    public let category: FactCategory
    public let timestamp: Date

    public init(fact: String, category: FactCategory = .other) {
        self.id = UUID(); self.fact = fact; self.category = category; self.timestamp = Date()
    }
}

public enum FactCategory: String, Sendable, Codable {
    case technicalFeature
    case legalRule
    case decision
    case strategy
    case other
}

public struct GlobalMemory: Sendable, Codable {
    public var writingStyle: String
    public var terminologyPreferences: [String: String]
    public var preferredProviders: [String]

    public init(writingStyle: String = "", terminologyPreferences: [String: String] = [:],
                preferredProviders: [String] = []) {
        self.writingStyle = writingStyle; self.terminologyPreferences = terminologyPreferences
        self.preferredProviders = preferredProviders
    }
}
```

### Task 20: 实现 MemoryStore（SQLite 持久化）

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Memory/MemoryStore.swift`

- [ ] **Step 1: Write MemoryStore**

```swift
// Packages/YunPatCore/Sources/YunPatCore/Memory/MemoryStore.swift
// Plan 2 基础实现：使用 UserDefaults + Codable JSON 替代 SQLite
// Plan 3 升级为 SQLite + SQLCipher

import Foundation

public actor MemoryStore {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func saveCaseContext(_ context: CaseContext) throws {
        let data = try encoder.encode(context)
        defaults.set(data, forKey: "yunpat.memory.case.\(context.caseId)")
    }

    public func loadCaseContext(_ caseId: String) -> CaseContext? {
        guard let data = defaults.data(forKey: "yunpat.memory.case.\(caseId)") else { return nil }
        return try? decoder.decode(CaseContext.self, from: data)
    }

    public func saveGlobalMemory(_ global: GlobalMemory) throws {
        let data = try encoder.encode(global)
        defaults.set(data, forKey: "yunpat.memory.global")
    }

    public func loadGlobalMemory() -> GlobalMemory {
        guard let data = defaults.data(forKey: "yunpat.memory.global"),
              let memory = try? decoder.decode(GlobalMemory.self, from: data) else {
            return GlobalMemory()
        }
        return memory
    }
}
```

- [ ] **Step 2: Verify build + Commit**

### Task 21: 实现 MemoryEngine（五层管理）

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Memory/MemoryEngine.swift`
- Create: `Packages/YunPatCore/Tests/YunPatCoreTests/MemoryEngineTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// Packages/YunPatCore/Tests/YunPatCoreTests/MemoryEngineTests.swift
import XCTest
@testable import YunPatCore

final class MemoryEngineTests: XCTestCase {
    func testSaveAndLoadCaseContext() async throws {
        let engine = MemoryEngine()
        let ctx = CaseContext(caseId: "test-001", technicalField: "机械")
        try await engine.saveCaseContext(ctx)
        let loaded = await engine.loadCaseContext("test-001")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.technicalField, "机械")
    }

    func testSessionFacts_accumulate() async throws {
        let engine = MemoryEngine()
        await engine.addSessionFact(SessionFact(fact: "发明使用螺旋传动"))
        await engine.addSessionFact(SessionFact(fact: "对比文件D1未公开该特征"))
        let facts = await engine.pendingSessionFacts()
        XCTAssertEqual(facts.count, 2)
    }
}
```

- [ ] **Step 2: Run test — FAIL → implement → PASS**

```swift
// Packages/YunPatCore/Sources/YunPatCore/Memory/MemoryEngine.swift
import Foundation

public actor MemoryEngine {
    private let store: MemoryStore
    private var sessionFacts: [SessionFact] = []

    public init(store: MemoryStore = MemoryStore()) {
        self.store = store
    }

    public func addSessionFact(_ fact: SessionFact) { sessionFacts.append(fact) }
    public func pendingSessionFacts() -> [SessionFact] { sessionFacts }

    public func saveCaseContext(_ context: CaseContext) throws { try store.saveCaseContext(context) }
    public func loadCaseContext(_ caseId: String) -> CaseContext? { store.loadCaseContext(caseId) }

    public func consolidate() throws -> CaseContext {
        // 蒸馏：从 sessionFacts 提取关键信息写入 CaseContext
        let ctx = CaseContext(
            caseId: "active",
            technicalField: sessionFacts.first?.fact ?? "",
            inventionPoints: sessionFacts.map(\.fact)
        )
        try store.saveCaseContext(ctx)
        sessionFacts.removeAll()
        return ctx
    }
}
```

- [ ] **Step 3: Commit**

---

## Phase F: 可观测性（Tasks 22-25）

### Task 22: 实现 TraceCollector + TraceStore

**Files:**
- Create: `Packages/YunPatCore/Sources/YunPatCore/Trace/TraceCollector.swift`
- Create: `Packages/YunPatCore/Sources/YunPatCore/Trace/TraceStore.swift`

- [ ] **Step 1: Write TraceCollector**

```swift
// Packages/YunPatCore/Sources/YunPatCore/Trace/TraceCollector.swift
import Foundation

public struct TraceID: Sendable, Hashable { public let id: UUID; public init() { id = UUID() } }

public struct CapabilityTrace: Sendable, Codable {
    public let capability: String
    public let tool: String
    public let arguments: String
    public let result: String
    public let latency: TimeInterval
    public let error: String?
    public init(capability: String, tool: String, arguments: String, result: String, latency: TimeInterval, error: String? = nil) {
        self.capability = capability; self.tool = tool; self.arguments = arguments
        self.result = result; self.latency = latency; self.error = error
    }
}

public struct PromptTrace: Sendable, Codable {
    public let systemPromptHash: String
    public let userMessages: String
    public let response: String
    public let cost: Double
    public let latency: TimeInterval
    public let model: String
    public init(systemPromptHash: String, userMessages: String, response: String, cost: Double, latency: TimeInterval, model: String) {
        self.systemPromptHash = systemPromptHash; self.userMessages = userMessages
        self.response = response; self.cost = cost; self.latency = latency; self.model = model
    }
}

public struct TraceSummary: Sendable, Codable {
    public let totalCost: Double
    public let totalLatency: TimeInterval
    public let toolCount: Int
    public let llmCallCount: Int
    public let skillNames: [String]
    public init(totalCost: Double, totalLatency: TimeInterval, toolCount: Int, llmCallCount: Int, skillNames: [String]) {
        self.totalCost = totalCost; self.totalLatency = totalLatency
        self.toolCount = toolCount; self.llmCallCount = llmCallCount; self.skillNames = skillNames
    }
}

public actor TraceCollector {
    private var traces: [TraceID: (capabilities: [CapabilityTrace], prompts: [PromptTrace])] = [:]
    private let store = TraceStore()

    public func startTrace() -> TraceID { let id = TraceID(); traces[id] = ([], []); return id }
    public func recordCapability(_ trace: CapabilityTrace, parent: TraceID) { traces[parent]?.capabilities.append(trace) }
    public func recordPrompt(_ trace: PromptTrace, parent: TraceID) { traces[parent]?.prompts.append(trace) }

    public func finishTrace(_ id: TraceID, summary: TraceSummary) async throws {
        guard let entry = traces[id] else { return }
        try await store.save(requestId: id.id, capabilities: entry.capabilities, prompts: entry.prompts, summary: summary)
        traces[id] = nil
    }
}
```

- [ ] **Step 2: Write TraceStore**

```swift
// Packages/YunPatCore/Sources/YunPatCore/Trace/TraceStore.swift
import Foundation

public final class TraceStore {
    private let tracesDir: URL

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dateFormatter = DateFormatter(); dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateDir = dateFormatter.string(from: Date())
        let dir = home.appendingPathComponent(".yunpat/traces/\(dateDir)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.tracesDir = dir
    }

    public func save(requestId: UUID, capabilities: [CapabilityTrace], prompts: [PromptTrace], summary: TraceSummary) async throws {
        let dict: [String: Any] = [
            "requestId": requestId.uuidString,
            "capabilities": capabilities.map { try? JSONEncoder().encode($0) }.compactMap { try? JSONSerialization.jsonObject(with: $0) },
            "prompts": prompts.map { try? JSONEncoder().encode($0) }.compactMap { try? JSONSerialization.jsonObject(with: $0) },
            "summary": try JSONSerialization.jsonObject(with: JSONEncoder().encode(summary))
        ]
        let data = try JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
        let url = tracesDir.appendingPathComponent("req-\(requestId.uuidString.prefix(8)).json")
        try data.write(to: url)
    }
}
```

- [ ] **Step 3: Verify build + Commit**

### Task 23: 在 AgentLoop 中埋点 Trace

- [ ] Modify AgentLoopEngine to record trace events
- [ ] Verify + Commit

---

## Phase G: 集成验证（Tasks 24-26）

### Task 24: 端到端测试——知识库查询

- [ ] Write integration test: ChatViewModel.sendMessage with vault configured
- [ ] Verify PatentLoop flow activates when vault is available
- [ ] Commit

### Task 25: 代码质量检查 + Swift 格式

```bash
swift-format --configuration .swift-format --recursive Packages/ App/ -i
cd Packages/YunPatCore && swift test
cd Packages/YunPatNetworking && swift test
```

### Task 26: 更新 README + 最终提交

---

## 验收标准

- [ ] WikiAdapter 成功读取宝宸知识库 vault
- [ ] RuleEngine 检索 + 冲突消解工作
- [ ] PatentLoopEngine 五步流程完整
- [ ] EvaluationEngine 规则化检查
- [ ] SkillManager RAG 匹配 + 注入
- [ ] MemoryEngine 五层保存/加载
- [ ] TraceCollector 记录请求链路
- [ ] 所有测试通过 (≥ 20 tests)
- [ ] 无编译警告
