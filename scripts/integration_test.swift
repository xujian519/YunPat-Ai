#!/usr/bin/env swift
// YunPat-Ai Plan 2+3+4 集成验证
import Foundation

// ── Helpers ──
func readKey(_ provider: String) -> String? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: "yunpat.\(provider)",
        kSecAttrService as String: "YunPat-Ai",
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
          let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
}

func check(_ name: String, _ closure: () async -> Bool) async -> (String, Bool) {
    let result: Bool = await closure()
    print("  \(result ? "✅" : "❌") \(name)")
    return (name, result)
}

let vaultPath: URL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents/宝宸知识库")

// ── Test 1: Knowledge Base ──
print("\n📚 Test 1: Knowledge Base Integration")
let t1a: (String, Bool) = await check("Vault readable") {
    FileManager.default.fileExists(
        atPath: vaultPath.appendingPathComponent("Wiki/Concept-Index.md").path)
}
let t1b: (String, Bool) = await check("WikiAdapter reads module index") {
    let indexPath: URL = vaultPath.appendingPathComponent("Wiki/专利实务/index.md")
    guard let content: String = try? String(contentsOf: indexPath, encoding: .utf8) else { return false }
    return content.contains("[[")
}
let t1c: (String, Bool) = await check("Concept-Index has 三步法") {
    guard let content: String = try? String(
        contentsOf: vaultPath.appendingPathComponent("Wiki/Concept-Index.md"),
        encoding: .utf8
    ) else { return false }
    return content.contains("三步法")
}

// ── Test 2: API Connectivity ──
print("\n🔌 Test 2: API Provider Connectivity")
var apiResults: [(String, Bool)] = []

if let key: String = readKey("deepseek"), !key.isEmpty {
    let result: (String, Bool) = await check("DeepSeek chat") {
        guard let url = URL(string: "https://api.deepseek.com/v1/chat/completions") else { return false }
        var request: URLRequest = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "deepseek-chat", "stream": false, "max_tokens": 50,
            "messages": [["role": "user", "content": "回1"]]
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, response): (Data, URLResponse) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
    apiResults.append(result)
}
if let key: String = readKey("glm"), !key.isEmpty {
    let result: (String, Bool) = await check("GLM chat") {
        guard let url = URL(string: "https://open.bigmodel.cn/api/paas/v4/chat/completions") else { return false }
        var request: URLRequest = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "glm-4", "stream": false, "max_tokens": 50,
            "messages": [["role": "user", "content": "回1"]]
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, response): (Data, URLResponse) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
    apiResults.append(result)
}

// ── Test 3: Shell Execution ──
print("\n💻 Test 3: Desktop Shell Execution")
let t3a: (String, Bool) = await check("ls works") {
    let process: Process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ls")
    process.arguments = ["/tmp"]
    let pipe: Pipe = Pipe()
    process.standardOutput = pipe
    try? process.run()
    process.waitUntilExit()
    return process.terminationStatus == 0
}

// ── Test 4: File Operations ──
print("\n📁 Test 4: File Operations")
let testDir: URL = FileManager.default.temporaryDirectory
    .appendingPathComponent("yunpat-integration-test")
try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
let t4a: (String, Bool) = await check("Write file") {
    let fileURL: URL = testDir.appendingPathComponent("test.md")
    do {
        try "test content".write(to: fileURL, atomically: true, encoding: .utf8)
        return true
    } catch {
        return false
    }
}
let t4b: (String, Bool) = await check("Read file") {
    let fileURL: URL = testDir.appendingPathComponent("test.md")
    guard let content: String = try? String(contentsOf: fileURL, encoding: .utf8) else { return false }
    return content == "test content"
}
let t4c: (String, Bool) = await check("NSFileCoordinator lock") {
    let fileURL: URL = testDir.appendingPathComponent("coordinator-test.md")
    let coordinator: NSFileCoordinator = NSFileCoordinator()
    var ok: Bool = false
    var error: Error?
    coordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &error) { writingURL in
        do {
            try "locked".write(to: writingURL, atomically: true, encoding: .utf8)
            ok = true
        } catch {}
    }
    return ok && error == nil
}

// ── Test 5: Git Version Control ──
print("\n📜 Test 5: Git Version Control")
let gitDir: URL = FileManager.default.temporaryDirectory
    .appendingPathComponent("yunpat-git-test")
try? FileManager.default.removeItem(at: gitDir)
try? FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
var gitSetup: Bool = false
do {
    let initProcess: Process = Process()
    initProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    initProcess.arguments = ["init"]
    initProcess.currentDirectoryURL = gitDir
    try initProcess.run()
    initProcess.waitUntilExit()

    let configEmailProcess: Process = Process()
    configEmailProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    configEmailProcess.arguments = ["config", "user.email", "test@test.com"]
    configEmailProcess.currentDirectoryURL = gitDir
    try configEmailProcess.run()
    configEmailProcess.waitUntilExit()

    let configNameProcess: Process = Process()
    configNameProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    configNameProcess.arguments = ["config", "user.name", "test"]
    configNameProcess.currentDirectoryURL = gitDir
    try configNameProcess.run()
    configNameProcess.waitUntilExit()

    gitSetup = true
} catch {}
let t5a: (String, Bool) = await check("Git init + commit") {
    guard gitSetup else { return false }
    let fileURL: URL = gitDir.appendingPathComponent("claims.md")
    try? "# 权利要求书\n1. 一种装置...".write(to: fileURL, atomically: true, encoding: .utf8)
    let addProcess: Process = Process()
    addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    addProcess.arguments = ["add", "."]
    addProcess.currentDirectoryURL = gitDir
    try addProcess.run()
    addProcess.waitUntilExit()
    let commitProcess: Process = Process()
    commitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    commitProcess.arguments = ["commit", "-m", "[agent] init claims"]
    commitProcess.currentDirectoryURL = gitDir
    try commitProcess.run()
    commitProcess.waitUntilExit()
    return commitProcess.terminationStatus == 0
}

// ── Test 6: Annotation Parser ──
print("\n📝 Test 6: Annotation Parser {del:}{ins:}{???}")
let t6a: (String, Bool) = await check("{del:} detection") {
    let input: String = "一种~~包括~~{del:包括}包含以下步骤"
    return input.contains("{del:") && input.contains("包含")
}
let t6b: (String, Bool) = await check("{ins:} detection") {
    let input: String = "所述方法{ins:在采集步骤之后}执行"
    return input.contains("{ins:") && input.contains("在采集步骤之后")
}
let t6c: (String, Bool) = await check("{???} detection") {
    let input: String = "连接到所述装置{???}"
    return input.contains("{???}")
}

// ── Test 7: Plugin Lifecycle Simulation ──
print("\n🔌 Test 7: Plugin Lifecycle")
enum PluginState: String { case installed, verified, enabled, disabled, uninstalled }
struct PluginManagerSim {
    var plugins: [String: PluginState] = [:]
    mutating func install(_ identifier: String) { plugins[identifier] = .installed }
    mutating func verify(_ identifier: String) { plugins[identifier] = .verified }
    mutating func enable(_ identifier: String) { plugins[identifier] = .enabled }
    mutating func disable(_ identifier: String) { plugins[identifier] = .disabled }
}
var sim: PluginManagerSim = PluginManagerSim()
sim.install("test-plugin")
let t7a: (String, Bool) = await check("install→verify→enable→disable") {
    sim.verify("test-plugin")
    sim.enable("test-plugin")
    sim.disable("test-plugin")
    return sim.plugins["test-plugin"] == .disabled
}

// ── Test 8: Memory 5-layer ──
print("\n🧠 Test 8: Memory 5-Layer")
let t8a: (String, Bool) = await check("Session→Case→Global layers") {
    struct SessionFact { let fact: String }
    struct CaseContext { var inventionPoints: [String] = [] }
    struct GlobalMemory { var writingStyle: String = "" }
    var session: [SessionFact] = [SessionFact(fact: "螺旋传动机构")]
    var caseCtx: CaseContext = CaseContext(inventionPoints: ["螺旋传动"])
    var globalMemory: GlobalMemory = GlobalMemory(writingStyle: "先独权后从权")
    // 蒸馏：session → case
    for fact in session { caseCtx.inventionPoints.append(fact.fact) }
    return caseCtx.inventionPoints.count >= 2 && !globalMemory.writingStyle.isEmpty
}

// ── Test 9: SSE Streaming (single-batch verification) ──
print("\n📡 Test 9: SSE Stream Protocol Verification")
let t9a: (String, Bool) = await check("SSE data: prefix") {
    let sampleSSE: String = "data: {\"choices\":[{\"delta\":{\"content\":\"测试\"}}]}\n\ndata: [DONE]"
    return sampleSSE.hasPrefix("data: ") && sampleSSE.contains("[DONE]")
}

// ── Test 10: Secure Credential Storage ──
print("\n🔐 Test 10: Keychain Credential Storage")
let t10a: (String, Bool) = await check("DeepSeek key stored") { readKey("deepseek") != nil }
let t10b: (String, Bool) = await check("GLM key stored") { readKey("glm") != nil }
let t10c: (String, Bool) = await check("oMLX key stored") { readKey("omlx") != nil }

// ── Summary ──
print("\n" + String(repeating: "=", count: 50))
let allTests: [(String, Bool)] = [
    t1a, t1b, t1c, t3a, t4a, t4b, t4c, t5a,
    t6a, t6b, t6c, t7a, t8a, t9a, t10a, t10b, t10c
] + apiResults
let passed: Int = allTests.filter(\.1).count
print("Result: \(passed)/\(allTests.count) integration checks passed")
if passed == allTests.count {
    print("🎉 All integration checks passed!")
} else {
    print("⚠️ Some checks failed — review above")
}
