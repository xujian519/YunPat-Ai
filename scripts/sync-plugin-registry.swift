#!/usr/bin/env swift
import Foundation

// MARK: - Plugin Registry Auto-Sync Script
// 自动同步工具代码定义到注册表 JSON
//
// 用法:
//   swift scripts/sync-plugin-registry.swift              # 同步
//   swift scripts/sync-plugin-registry.swift --check       # CI 模式：仅检测漂移

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()

let checkOnly = CommandLine.arguments.contains("--check")

// MARK: - 1. Extract tools from all ToolDispatch*.swift files
let loopDir = repoRoot
    .appendingPathComponent("Packages/YunPatCore/Sources/YunPatCore/Loop")

guard FileManager.default.fileExists(atPath: loopDir.path) else {
    print("ERROR: Loop/ directory not found at \(loopDir.path)")
    exit(2)
}

let dispatchFiles = try FileManager.default.contentsOfDirectory(at: loopDir, includingPropertiesForKeys: nil)
    .filter { $0.lastPathComponent.hasPrefix("ToolDispatch") && $0.pathExtension == "swift" }

let handlerRegex = try! NSRegularExpression(
    pattern: #"handlers\["([^"]+)"\]\s*="# , options: []
)

var codeToolNames = Set<String>()
for fileURL in dispatchFiles {
    let source = try String(contentsOf: fileURL, encoding: .utf8)
    let matches = handlerRegex.matches(
        in: source, range: NSRange(source.startIndex..., in: source)
    )
    for match in matches {
        guard let range = Range(match.range(at: 1), in: source) else { continue }
        let name = String(source[range])
        if name != "task_complete" && name != "ask_user" {
            codeToolNames.insert(name)
        }
    }
}

print("Code tools: \(codeToolNames.count)")

// MARK: - 2. Read registry.json
let registryPath = repoRoot.appendingPathComponent("plugins/registry.json")
var registryTools = Set<String>()

if FileManager.default.fileExists(atPath: registryPath.path) {
    let regData = try Data(contentsOf: registryPath)
    if let json = try JSONSerialization.jsonObject(with: regData) as? [String: Any],
       let tools = json["tools"] as? [[String: Any]] {
        registryTools = Set(tools.compactMap { $0["name"] as? String })
    }
}

print("Registry tools: \(registryTools.count)")

// MARK: - 3. Detect drift
let added = codeToolNames.subtracting(registryTools).sorted()
let removed = registryTools.subtracting(codeToolNames).sorted()

if added.isEmpty && removed.isEmpty {
    print("✅ Registry in sync — \(codeToolNames.count) tools.")
    exit(0)
}

if !added.isEmpty {
    print("➕ \(added.count) tool(s) in code but NOT in registry:")
    for name in added { print("    - \(name)") }
}

if !removed.isEmpty {
    print("➖ \(removed.count) tool(s) in registry but NOT in code:")
    for name in removed { print("    - \(name)") }
}

if checkOnly {
    print("\n❌ Registry drift detected.")
    print("   Run 'swift scripts/sync-plugin-registry.swift' to sync.")
    exit(1)
}

// MARK: - 4. Read tool docs for workflow metadata
let docsDir = repoRoot
    .appendingPathComponent("Packages/YunPatCore/Sources/YunPatCore/Tools/Docs")

func extractFrontmatter(from content: String) -> [String: String] {
    let lines = content.components(separatedBy: .newlines)
    guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
          let endIdx = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
    else { return [:] }
    var frontmatter: [String: String] = [:]
    for line in lines[1..<endIdx] {
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { continue }
        let key = parts[0].trimmingCharacters(in: .whitespaces)
        let value = parts[1].trimmingCharacters(in: .whitespaces)
        frontmatter[key] = value
    }
    return frontmatter
}

func extractBullets(after heading: String, from content: String) -> [String] {
    let lines = content.components(separatedBy: .newlines)
    guard let headingIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == heading }) else {
        return []
    }
    var bullets: [String] = []
    for line in lines[(headingIdx + 1)...] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { continue }
        guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("1. ") else { break }
        let bullet = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
        if !bullet.isEmpty { bullets.append(bullet) }
    }
    return bullets
}

func extractWorkflow(from content: String) -> [String] {
    extractBullets(after: "## Typical Workflow", from: content).map { step in
        // Strip leading "1. ", "2. ", etc.
        step.replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression)
    }
}

func extractTriggers(from content: String) -> [String] {
    extractBullets(after: "## When to Use", from: content)
}

let toolEntries = codeToolNames.sorted().map { name -> [String: Any] in
    let docPath = docsDir.appendingPathComponent("\(name).md")
    var entry: [String: Any] = [
        "name": name,
        "source": "builtin",
        "version": "1.0.0",
    ]
    if FileManager.default.fileExists(atPath: docPath.path),
       let docContent = try? String(contentsOf: docPath, encoding: .utf8) {
        let frontmatter = extractFrontmatter(from: docContent)
        if let desc = frontmatter["description"], !desc.isEmpty, !desc.hasPrefix("TODO") {
            entry["description"] = desc
        }
        let triggers = extractTriggers(from: docContent)
        if !triggers.isEmpty { entry["triggers"] = triggers }
        let workflow = extractWorkflow(from: docContent)
        if !workflow.isEmpty { entry["workflow"] = workflow }
    }
    return entry
}

let registry: [String: Any] = [
    "generated": ISO8601DateFormatter().string(from: Date()),
    "toolCount": toolEntries.count,
    "tools": toolEntries,
]
let jsonData = try JSONSerialization.data(
    withJSONObject: registry,
    options: [.prettyPrinted, .sortedKeys]
)
let registryDir = registryPath.deletingLastPathComponent()
try FileManager.default.createDirectory(at: registryDir, withIntermediateDirectories: true)
try jsonData.write(to: registryPath)

print("✅ Registry written — \(codeToolNames.count) tools → \(registryPath.path)")
exit(0)
