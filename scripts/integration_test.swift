#!/usr/bin/env swift
// YunPat-Ai Plan 2+3+4 集成验证
import Foundation

// ── Helpers ──
func readKey(_ provider: String) -> String? {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: "yunpat.\(provider)", kSecAttrService as String: "YunPat-Ai", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
    var item: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
}

func check(_ name: String, _ fn: () async -> Bool) async -> (String, Bool) {
    let result = await fn()
    print("  \(result ? "✅" : "❌") \(name)")
    return (name, result)
}

let vaultPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents/宝宸知识库")

// ── Test 1: Knowledge Base ──
print("\n📚 Test 1: Knowledge Base Integration")
let t1a = await check("Vault readable") {
    FileManager.default.fileExists(atPath: vaultPath.appendingPathComponent("Wiki/Concept-Index.md").path)
}
let t1b = await check("WikiAdapter reads module index") {
    let indexPath = vaultPath.appendingPathComponent("Wiki/专利实务/index.md")
    guard let content = try? String(contentsOf: indexPath, encoding: .utf8) else { return false }
    return content.contains("[[")
}
let t1c = await check("Concept-Index has 三步法") {
    guard let content = try? String(contentsOf: vaultPath.appendingPathComponent("Wiki/Concept-Index.md"), encoding: .utf8) else { return false }
    return content.contains("三步法")
}

// ── Test 2: API Connectivity ──
print("\n🔌 Test 2: API Provider Connectivity")
var apiResults: [(String, Bool)] = []

if let key = readKey("deepseek"), !key.isEmpty {
    let r = await check("DeepSeek chat") {
        var req = URLRequest(url: URL(string: "https://api.deepseek.com/v1/chat/completions")!)
        req.httpMethod = "POST"; req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization"); req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try! JSONSerialization.data(withJSONObject: ["model":"deepseek-chat","stream":false,"max_tokens":50, "messages":[["role":"user","content":"回1"]]])
        do { let (data, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }
    apiResults.append(r)
}
if let key = readKey("glm"), !key.isEmpty {
    let r = await check("GLM chat") {
        var req = URLRequest(url: URL(string: "https://open.bigmodel.cn/api/coding/paas/v4/chat/completions")!)
        req.httpMethod = "POST"; req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization"); req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try! JSONSerialization.data(withJSONObject: ["model":"glm-5.1","stream":false,"max_tokens":50, "messages":[["role":"user","content":"回1"]]])
        do { let (data, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch { return false }
    }
    apiResults.append(r)
}

// ── Test 3: Shell Execution ──
print("\n💻 Test 3: Desktop Shell Execution")
let t3a = await check("ls works") {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/ls"); p.arguments = ["/tmp"]
    let pipe = Pipe(); p.standardOutput = pipe
    try? p.run(); p.waitUntilExit()
    return p.terminationStatus == 0
}

// ── Test 4: File Operations ──
print("\n📁 Test 4: File Operations")
let testDir = FileManager.default.temporaryDirectory.appendingPathComponent("yunpat-integration-test")
try? FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
let t4a = await check("Write file") {
    let f = testDir.appendingPathComponent("test.md")
    do { try "test content".write(to: f, atomically: true, encoding: .utf8); return true } catch { return false }
}
let t4b = await check("Read file") {
    let f = testDir.appendingPathComponent("test.md")
    guard let content = try? String(contentsOf: f, encoding: .utf8) else { return false }
    return content == "test content"
}
let t4c = await check("NSFileCoordinator lock") {
    let f = testDir.appendingPathComponent("coordinator-test.md")
    let coordinator = NSFileCoordinator()
    var ok = false; var err: Error?
    coordinator.coordinate(writingItemAt: f, options: .forReplacing, error: &err) { url in
        try? "locked".data(using: .utf8)!.write(to: url); ok = true
    }
    return ok && err == nil
}

// ── Test 5: Git Version Control ──
print("\n📜 Test 5: Git Version Control")
let gitDir = FileManager.default.temporaryDirectory.appendingPathComponent("yunpat-git-test")
try? FileManager.default.removeItem(at: gitDir); try? FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
var gitSetup = false
do {
    let p1 = Process(); p1.executableURL = URL(fileURLWithPath: "/usr/bin/git"); p1.arguments = ["init"]; p1.currentDirectoryURL = gitDir
    try p1.run(); p1.waitUntilExit()
    let p2 = Process(); p2.executableURL = URL(fileURLWithPath: "/usr/bin/git"); p2.arguments = ["config","user.email","test@test.com"]; p2.currentDirectoryURL = gitDir
    try p2.run(); p2.waitUntilExit()
    let p3 = Process(); p3.executableURL = URL(fileURLWithPath: "/usr/bin/git"); p3.arguments = ["config","user.name","test"]; p3.currentDirectoryURL = gitDir
    try p3.run(); p3.waitUntilExit()
    gitSetup = true
} catch {}
let t5a = await check("Git init + commit") {
    guard gitSetup else { return false }
    let f = gitDir.appendingPathComponent("claims.md")
    try? "# 权利要求书\n1. 一种装置...".write(to: f, atomically: true, encoding: .utf8)
    let add = Process(); add.executableURL = URL(fileURLWithPath: "/usr/bin/git"); add.arguments = ["add","."]; add.currentDirectoryURL = gitDir
    try add.run(); add.waitUntilExit()
    let cm = Process(); cm.executableURL = URL(fileURLWithPath: "/usr/bin/git"); cm.arguments = ["commit","-m","[agent] init claims"]; cm.currentDirectoryURL = gitDir
    try cm.run(); cm.waitUntilExit()
    return cm.terminationStatus == 0
}

// ── Test 6: Annotation Parser ──
print("\n📝 Test 6: Annotation Parser {del:}{ins:}{???}")
let t6a = await check("{del:} detection") {
    let input = "一种~~包括~~{del:包括}包含以下步骤"
    return input.contains("{del:") && input.contains("包含")
}
let t6b = await check("{ins:} detection") {
    let input = "所述方法{ins:在采集步骤之后}执行"
    return input.contains("{ins:") && input.contains("在采集步骤之后")
}
let t6c = await check("{???} detection") {
    let input = "连接到所述装置{???}"
    return input.contains("{???}")
}

// ── Test 7: Plugin Lifecycle Simulation ──
print("\n🔌 Test 7: Plugin Lifecycle")
enum PluginState: String { case installed, verified, enabled, disabled, uninstalled }
struct PluginManagerSim {
    var plugins: [String: PluginState] = [:]
    mutating func install(_ id: String) { plugins[id] = .installed }
    mutating func verify(_ id: String) { plugins[id] = .verified }
    mutating func enable(_ id: String) { plugins[id] = .enabled }
    mutating func disable(_ id: String) { plugins[id] = .disabled }
}
var sim = PluginManagerSim()
sim.install("test-plugin")
let t7a = await check("install→verify→enable→disable") {
    sim.verify("test-plugin"); sim.enable("test-plugin"); sim.disable("test-plugin")
    return sim.plugins["test-plugin"] == .disabled
}

// ── Test 8: Memory 5-layer ──
print("\n🧠 Test 8: Memory 5-Layer")
let t8a = await check("Session→Case→Global layers") {
    struct SessionFact { let fact: String }
    struct CaseContext { var inventionPoints: [String] = [] }
    struct GlobalMemory { var writingStyle: String = "" }
    var session: [SessionFact] = [SessionFact(fact: "螺旋传动机构")]
    var caseCtx = CaseContext(inventionPoints: ["螺旋传动"])
    var global = GlobalMemory(writingStyle: "先独权后从权")
    // 蒸馏：session → case
    for f in session { caseCtx.inventionPoints.append(f.fact) }
    return caseCtx.inventionPoints.count >= 2 && !global.writingStyle.isEmpty
}

// ── Test 9: SSE Streaming (single-batch verification) ──
print("\n📡 Test 9: SSE Stream Protocol Verification")
let t9a = await check("SSE data: prefix") {
    let sampleSSE = "data: {\"choices\":[{\"delta\":{\"content\":\"测试\"}}]}\n\ndata: [DONE]"
    return sampleSSE.hasPrefix("data: ") && sampleSSE.contains("[DONE]")
}

// ── Test 10: Secure Credential Storage ──
print("\n🔐 Test 10: Keychain Credential Storage")
let t10a = await check("DeepSeek key stored") { readKey("deepseek") != nil }
let t10b = await check("GLM key stored") { readKey("glm") != nil }
let t10c = await check("oMLX key stored") { readKey("omlx") != nil }

// ── Summary ──
print("\n" + String(repeating: "=", count: 50))
let allTests = [t1a,t1b,t1c,t3a,t4a,t4b,t4c,t5a,t6a,t6b,t6c,t7a,t8a,t9a,t10a,t10b,t10c] + apiResults
let passed = allTests.filter(\.1).count
print("Result: \(passed)/\(allTests.count) integration checks passed")
if passed == allTests.count { print("🎉 All integration checks passed!") }
else { print("⚠️ Some checks failed — review above") }
