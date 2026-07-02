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

// MARK: - 1. Extract tools from ToolDispatch.swift
let dispatchPath = repoRoot
    .appendingPathComponent("Packages/YunPatCore/Sources/YunPatCore/Loop/ToolDispatch.swift")

guard FileManager.default.fileExists(atPath: dispatchPath.path) else {
    print("ERROR: ToolDispatch.swift not found at \(dispatchPath.path)")
    exit(2)
}

let source = try String(contentsOf: dispatchPath, encoding: .utf8)
let handlerRegex = try! NSRegularExpression(
    pattern: #"handlers\["([^"]+)"\]\s*="# , options: []
)
let codeToolNames = Set(handlerRegex.matches(
    in: source, range: NSRange(source.startIndex..., in: source)
).compactMap { match -> String? in
    guard let range = Range(match.range(at: 1), in: source) else { return nil }
    let name = String(source[range])
    return (name == "task_complete" || name == "ask_user") ? nil : name
})

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

// MARK: - 4. Generate new registry.json
let toolEntries = codeToolNames.sorted().map { name -> [String: Any] in
    ["name": name, "source": "builtin", "version": "1.0.0"]
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
