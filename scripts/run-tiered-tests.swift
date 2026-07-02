#!/usr/bin/env swift
import Foundation

// MARK: - T0/T1/T2 测试分档运行器
//
// 用法:
//   swift scripts/run-tiered-tests.swift t0      # 仅 T0（纯本地，秒级）
//   swift scripts/run-tiered-tests.swift t0t1    # T0 + T1（探测本地依赖）
//   swift scripts/run-tiered-tests.swift all     # 全量（含网络 API）
//   swift scripts/run-tiered-tests.swift list    # 列出各档工具

enum Tier: String {
    case t0, t1, t2
}

struct ToolInfo {
    let name: String
    let tier: Tier
    let testFilter: String
}

/// 工具清单 — T0 纯本地 / T1 软依赖 / T2 硬依赖
let tools: [ToolInfo] = [
    // T0 — 纯本地，零外部依赖
    ToolInfo(name: "read_file", tier: .t0, testFilter: "ToolDispatchTests"),
    ToolInfo(name: "write_file", tier: .t0, testFilter: "ToolDispatchTests"),
    ToolInfo(name: "edit", tier: .t0, testFilter: "ToolDispatchTests"),
    ToolInfo(name: "execute_shell", tier: .t0, testFilter: "ToolDispatchTests"),
    ToolInfo(name: "search_files", tier: .t0, testFilter: "ToolDispatchTests"),
    ToolInfo(name: "list_files", tier: .t0, testFilter: "ToolDispatchTests"),
    ToolInfo(name: "list_tools", tier: .t0, testFilter: "ToolDispatchTests"),
    ToolInfo(name: "file_undo", tier: .t0, testFilter: "ToolDispatchTests"),
    ToolInfo(name: "file_operation_history", tier: .t0, testFilter: "ToolDispatchTests"),

    // T1 — 软依赖（本地 DB / 索引 / 环境）
    ToolInfo(name: "knowledge_search", tier: .t1, testFilter: "KnowledgeTests"),
    ToolInfo(name: "legal_status_query", tier: .t1, testFilter: "PatentTests"),
    ToolInfo(name: "capabilities_load", tier: .t1, testFilter: "CapabilityRegistryTests"),
    ToolInfo(name: "capabilities_discover", tier: .t1, testFilter: "CapabilityRegistryTests"),

    // T2 — 硬依赖（网络 API / LLM / 外部服务）
    ToolInfo(name: "patent_search", tier: .t2, testFilter: "PatentClientTests"),
]

func runCommand(_ args: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = args
    process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    try? process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

func runTests(for tiers: Set<Tier>) {
    let tierTools = tools.filter { tiers.contains($0.tier) }
    let filters = Array(Set(tierTools.map(\.testFilter)))

    print("[TieredTest] 运行 \(tiers.map(\.rawValue).sorted().joined(separator: "+")) 档测试 (\(tierTools.count) 个工具)")

    for filter in filters.sorted() {
        print("[TieredTest]   → \(filter)")
    }

    // 构建
    let buildStatus = runCommand(["swift", "build"])
    guard buildStatus == 0 else {
        print("[TieredTest] ❌ 构建失败")
        exit(1)
    }

    // 逐包运行测试
    var allPassed = true
    let packages: [(name: String, path: String)] = [
        ("YunPatCore", "Packages/YunPatCore"),
        ("YunPatPlugins", "Packages/YunPatPlugins"),
        ("PatentClient", "Packages/PatentClient"),
    ]

    for (name, path) in packages {
        let packageURL = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: packageURL.path) else { continue }

        print("[TieredTest] 测试 \(name)...")
        let status = runCommand(["swift", "test", "--package-path", path])
        if status != 0 {
            print("[TieredTest] ❌ \(name) 测试失败")
            allPassed = false
        } else {
            print("[TieredTest] ✅ \(name) 通过")
        }
    }

    if allPassed {
        print("[TieredTest] ✅ 全部通过 (\(tiers.map(\.rawValue).sorted().joined(separator: "+")))")
    } else {
        print("[TieredTest] ❌ 有失败")
        exit(1)
    }
}

func listTools() {
    for tier in [Tier.t0, Tier.t1, Tier.t2] {
        let tierTools = tools.filter { $0.tier == tier }
        print("\n[T\(tier.rawValue.uppercased())] \(tierTools.count) 个工具:")
        for t in tierTools {
            print("  - \(t.name)")
        }
    }
}

// MARK: - Main

let args = CommandLine.arguments.dropFirst()
let mode = args.first ?? "list"

switch mode {
case "t0":
    runTests(for: [.t0])
case "t0t1":
    runTests(for: [.t0, .t1])
case "all":
    runTests(for: [.t0, .t1, .t2])
case "list":
    listTools()
default:
    print("用法: run-tiered-tests.swift [t0|t0t1|all|list]")
    exit(1)
}
