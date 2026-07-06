#!/usr/bin/env swift
import Foundation

// MARK: - Tool Registry Validation Script
// 校验 ToolDispatch 中注册的所有工具：
//   1. 无重复注册
//   2. 每个工具有对应的 TOOL.md
//   3. readOnlyTools 与 dispatch table 一致
//
// 用法:
//   swift scripts/validate-tools.swift              # 运行校验
//   swift scripts/validate-tools.swift --fix         # 自动修复可修复的问题
//
// Exit codes:
//   0 — all validations pass
//   1 — errors found (duplicates, broken references)
//   2 — warnings only (missing TOOL.md, misconfigured)

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()

let fixMode = CommandLine.arguments.contains("--fix")

// MARK: - 1. Extract tool names from ToolDispatch.swift
let dispatchPath = repoRoot
    .appendingPathComponent("Packages/YunPatCore/Sources/YunPatCore/Loop/ToolDispatch.swift")

guard FileManager.default.fileExists(atPath: dispatchPath.path) else {
    print("ERROR: ToolDispatch.swift not found at \(dispatchPath.path)")
    exit(2)
}

let source = try String(contentsOf: dispatchPath, encoding: .utf8)

// Extract unique tool names from handler registrations
let handlerRegex = try! NSRegularExpression(
    pattern: #"handlers\["([^"]+)"\]\s*="# , options: []
)
let matches = handlerRegex.matches(in: source, range: NSRange(source.startIndex..., in: source))
let allToolNames = matches.compactMap { match -> String? in
    guard let range = Range(match.range(at: 1), in: source) else { return nil }
    let name = String(source[range])
    // Skip aliases
    if name == "task_complete" || name == "ask_user" { return nil }
    return name
}
let toolNames = Set(allToolNames)

if toolNames.isEmpty {
    print("❌ ERROR: No tools registered in buildDispatchTable()")
    exit(1)
}

print("Found \(toolNames.count) unique tools:")
for name in toolNames.sorted() { print("  - \(name)") }

// MARK: - 2. Check for duplicate registrations
let dupGroups = Dictionary(grouping: allToolNames, by: { $0 }).filter { $0.value.count > 1 }
var errorCount = 0
if !dupGroups.isEmpty {
    for (name, _) in dupGroups {
        print("❌ ERROR: Duplicate registration: \(name)")
        errorCount += 1
    }
} else {
    print("✅ No duplicate registrations")
}

// MARK: - 3. Check TOOL.md for each tool
let docsDir = repoRoot
    .appendingPathComponent("Packages/YunPatCore/Sources/YunPatCore/Tools/Docs")
var warningCount = 0
var missingDocs: [String] = []

for name in toolNames.sorted() {
    let docPath = docsDir.appendingPathComponent("\(name).md")
    if !FileManager.default.fileExists(atPath: docPath.path) {
        if fixMode {
            // Create a placeholder TOOL.md
            let templatePath = repoRoot
                .appendingPathComponent("Packages/YunPatCore/Sources/YunPatCore/Tools/Docs/TOOL_TEMPLATE.md")
            if FileManager.default.fileExists(atPath: templatePath.path),
               let template = try? String(contentsOf: templatePath, encoding: .utf8) {
                let filled = template
                    .replacingOccurrences(of: "<tool_name>", with: name)
                    .replacingOccurrences(of: "<one-line summary of what this tool does and when to use it>", with: "Auto-generated placeholder for \(name)")
                try? filled.write(to: docPath, atomically: true, encoding: .utf8)
                print("📝 Created from template: \(name).md")
            } else {
                let placeholder = """
                ---
                name: \(name)
                description: Auto-generated placeholder for \(name)
                version: "1.0"
                author: YunPat Team
                ---

                # \(name)

                Refer to TOOL_TEMPLATE.md for documentation structure.
                """
                try? placeholder.write(to: docPath, atomically: true, encoding: .utf8)
                print("📝 Created placeholder: \(name).md")
            }
        } else {
            missingDocs.append(name)
            warningCount += 1
        }
    }
}

if missingDocs.isEmpty {
    print("✅ All \(toolNames.count) tools have TOOL.md")
} else {
    for name in missingDocs {
        print("⚠️  WARNING: Missing TOOL.md for '\(name)' — "
              + "create at Tools/Docs/\(name).md")
    }
}

// MARK: - 4. Check readOnlyTools consistency
let readOnlyRegex = try! NSRegularExpression(
    pattern: #"readOnlyTools: Set<String> = \[([^\]]+)\]"# ,
    options: [.dotMatchesLineSeparators]
)
if let roMatch = readOnlyRegex.firstMatch(
    in: source,
    range: NSRange(source.startIndex..., in: source)
), let roRange = Range(roMatch.range(at: 1), in: source) {
    let readOnlyBody = String(source[roRange])
    let readOnlyNames = readOnlyBody
        .components(separatedBy: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "") }
        .filter { !$0.isEmpty && !$0.hasPrefix("//") }

    for roName in readOnlyNames {
        if !toolNames.contains(roName)
            && roName != "read_dir"
            && !roName.hasPrefix("git_")
            && !roName.hasPrefix("ax_") {
            print("⚠️  WARNING: readOnly tool '\(roName)' not in dispatch table")
            warningCount += 1
        }
    }
}

// MARK: - Summary
print("")
if errorCount > 0 {
    print("❌ \(errorCount) error(s), \(warningCount) warning(s)")
    exit(1)
} else if warningCount > 0 {
    print("⚠️  \(warningCount) warning(s) — run with --fix to auto-create missing TOOL.md files")
    exit(2)
} else {
    print("✅ All tool validations passed.")
    exit(0)
}
