#!/usr/bin/env swift
import Foundation

// MARK: - L0-L3 影响面自动检测
//
// 对齐 XiaoNuo .nuo/review-plan.md 的判定规则，适配 SwiftPM 项目。
//
// 用法:
//   swift scripts/impact-detect.swift [--base origin/main]
//   输出: L0|L1|L2|L3 或 JSON 详情

// ── 配置 ──
let baseBranch = CommandLine.arguments.dropFirst().first ?? "origin/main"

// ── 判定规则 ──
enum ImpactLevel: String, CaseIterable {
    case l0 = "L0"  // 微型：单文件、typo、注释、配置微调
    case l1 = "L1"  // 局部：单包内变更，public API 未变
    case l2 = "L2"  // 跨包：2+包变更 或 单包但 public API 变更
    case l3 = "L3"  // 架构级：新增/删除包、依赖方向变更、破坏性 API
}

struct ImpactReport: Encodable {
    let level: String
    let changedFiles: [String]
    let changedPackages: [String]
    let publicAPIChanged: Bool
    let dependencyChanged: Bool
    let newPackage: Bool
    let removedPackage: Bool
    let reasoning: String
}

// ── Shell 辅助 ──
func shell(_ args: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = args
    let pipe = Pipe()
    process.standardOutput = pipe
    process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    try? process.run()
    process.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

func changedFiles(base: String) -> [String] {
    let output = shell(["git", "diff", "--name-only", base])
    return output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
}

func changedPackages(from files: [String]) -> Set<String> {
    var pkgs = Set<String>()
    for f in files {
        if f.hasPrefix("Packages/") {
            let parts = f.split(separator: "/")
            if parts.count >= 2 { pkgs.insert("Packages/\(parts[1])") }
        } else if f.hasPrefix("App/") {
            pkgs.insert("App")
        }
    }
    return pkgs
}

func isDocOrConfig(_ file: String) -> Bool {
    let docExts = [".md", ".txt"]
    let configPatterns = ["Package.resolved", ".gitignore", ".editorconfig", ".swiftlint.yml", ".swift-format"]
    for ext in docExts where file.hasSuffix(ext) { return true }
    for pattern in configPatterns where file.contains(pattern) { return true }
    return file.hasPrefix("docs/") || file.hasPrefix("设计意见/") || file.hasPrefix("scripts/")
}

func hasPublicAPIChange(files: [String]) -> Bool {
    // 检测 public 声明变更
    for file in files where file.hasSuffix(".swift") {
        let diff = shell(["git", "diff", baseBranch, "--", file])
        if diff.contains("public ") { return true }
    }
    return false
}

func hasDependencyChange(files: [String]) -> Bool {
    for file in files where file.contains("Package.swift") || file.contains("Package.resolved") {
        return true
    }
    return false
}

func hasNewPackage(files: [String]) -> Bool {
    // 检测新增的 Package 目录
    for file in files where file.hasPrefix("Packages/") {
        let parts = file.split(separator: "/")
        if parts.count >= 2 {
            let pkgDir = "Packages/\(parts[1])"
            let output = shell(["git", "diff", "--name-status", baseBranch, "--", pkgDir])
            if output.hasPrefix("A") { return true }
        }
    }
    return false
}

// ── 判定逻辑 ──
func detectImpact(files: [String]) -> ImpactReport {
    let sourceFiles = files.filter { !isDocOrConfig($0) }
    let pkgs = changedPackages(from: sourceFiles)

    // L0: 仅文档/配置/脚本
    if sourceFiles.isEmpty || sourceFiles.allSatisfy({ isDocOrConfig($0) || $0.hasPrefix("scripts/") }) {
        return ImpactReport(level: "L0", changedFiles: files, changedPackages: [],
                            publicAPIChanged: false, dependencyChanged: false,
                            newPackage: false, removedPackage: false,
                            reasoning: "仅文档/配置/脚本变更 — 自动门禁")
    }

    let newPkg = hasNewPackage(files)
    let depChanged = hasDependencyChange(files)
    let apiChanged = hasPublicAPIChange(files: files)

    // L3: 新增包 / 删除包 / Package.swift 结构变更
    if newPkg || depChanged {
        return ImpactReport(level: "L3", changedFiles: files, changedPackages: Array(pkgs),
                            publicAPIChanged: apiChanged, dependencyChanged: depChanged,
                            newPackage: newPkg, removedPackage: false,
                            reasoning: "依赖结构变更 — 架构级审阅 (2 reviewers)")
    }

    // L2: 跨包变更 或 public API 变更
    if pkgs.count >= 2 || apiChanged {
        return ImpactReport(level: "L2", changedFiles: files, changedPackages: Array(pkgs),
                            publicAPIChanged: apiChanged, dependencyChanged: false,
                            newPackage: false, removedPackage: false,
                            reasoning: "\(pkgs.count) 包变更 \(apiChanged ? "+ public API" : "") — 跨包审阅 (1 reviewer + 架构知悉)")
    }

    // L1: 单包内变更，export 未变
    if pkgs.count == 1 {
        return ImpactReport(level: "L1", changedFiles: files, changedPackages: Array(pkgs),
                            publicAPIChanged: false, dependencyChanged: false,
                            newPackage: false, removedPackage: false,
                            reasoning: "单包内变更 (\(pkgs.first!)) — 局部审阅 (1 reviewer)")
    }

    // L0: 单文件变更
    return ImpactReport(level: "L0", changedFiles: files, changedPackages: [],
                        publicAPIChanged: false, dependencyChanged: false,
                        newPackage: false, removedPackage: false,
                        reasoning: "微型变更 — 自动合并")
}

// ── Main ──
let files = changedFiles(base: baseBranch)
let report = detectImpact(files: files)

let encoder = JSONEncoder()
encoder.outputFormatting = .prettyPrinted
let json = try! encoder.encode(report)
print(String(data: json, encoding: .utf8)!)

// 退出码 = 影响面数字（CI 可读取）
let exitCodes: [String: Int32] = ["L0": 0, "L1": 10, "L2": 20, "L3": 30]
exit(exitCodes[report.level] ?? 0)
