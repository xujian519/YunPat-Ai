import Foundation
import Testing
@testable import YunPatDesktop

struct SecurityGateTests {

    @Test func alwaysLevelAlwaysPasses() async {
        let gate = SecurityGate()
        let result = await gate.check("shell.execute", level: .always)
        #expect(result)
    }

    @Test func neverLevelAlwaysFails() async {
        let gate = SecurityGate()
        let result = await gate.check("dangerous.stuff", level: .never)
        #expect(!result)
    }

    @Test func perSessionRequiresGrant() async {
        let gate = SecurityGate()
        let before = await gate.check("file.write", level: .perSession)
        #expect(!before)

        await gate.grant("file.write", level: .perSession)
        let after = await gate.check("file.write", level: .perSession)
        #expect(after)
    }

    @Test func perCallTokenIsConsumedOnce() async {
        let gate = SecurityGate()
        await gate.grant("one.time", level: .perCall)

        let first = await gate.check("one.time", level: .perCall)
        #expect(first)

        let second = await gate.check("one.time", level: .perCall)
        #expect(!second)
    }

    @Test func perCallTokensAreIndependent() async {
        let gate = SecurityGate()
        await gate.grant("token.a", level: .perCall)
        await gate.grant("token.b", level: .perCall)

        let a1 = await gate.check("token.a", level: .perCall)
        #expect(a1)
        let b1 = await gate.check("token.b", level: .perCall)
        #expect(b1)
    }

    @Test func auditLogRecords() async {
        let gate = SecurityGate()
        let log = OperationLog(capability: "shell.execute", tool: "echo", result: "ok")
        await gate.record(log)

        let logs = await gate.auditLog
        #expect(logs.count == 1)
        #expect(logs[0].capability == "shell.execute")
        #expect(logs[0].tool == "echo")
        #expect(logs[0].result == "ok")
    }

    @Test func auditLogAppendsMultiple() async {
        let gate = SecurityGate()
        await gate.record(OperationLog(capability: "a", tool: "t1", result: "ok"))
        await gate.record(OperationLog(capability: "b", tool: "t2", result: "fail"))

        let logs = await gate.auditLog
        #expect(logs.count == 2)
    }

    @Test func grantDefaultLevelDoesNothing() async {
        let gate = SecurityGate()
        await gate.grant("anything", level: .always)
        let result = await gate.check("anything", level: .perSession)
        #expect(!result)  // .always grant should not affect .perSession check
    }

    @Test func operationLogTimestamps() {
        let before = Date().timeIntervalSince1970
        let log = OperationLog(capability: "x", tool: "y", result: "z")
        let after = Date().timeIntervalSince1970
        #expect(log.timestamp.timeIntervalSince1970 >= before)
        #expect(log.timestamp.timeIntervalSince1970 <= after)
    }
}
