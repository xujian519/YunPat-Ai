import XCTest
@testable import YunPatCore

final class TwoPassDraftTests: XCTestCase {

    // MARK: - DiagnosisResult.verdict

    func testVerdictPass_whenNoTaboosAndFactsPreserved() {
        let factResult = FactVerificationResult(
            passed: true, preservedCount: 3,
            lostFacts: [], addedFacts: [])
        let diag = DiagnosisResult(taboos: [], factVerification: factResult)
        if case .pass = diag.verdict {
            // pass
        } else {
            XCTFail("Expected .pass, got \(diag.verdict)")
        }
    }

    func testVerdictFail_whenErrorTabooPresent() {
        let errorRule = TabooRule(
            pattern: "大约", reason: "数值应精确",
            severity: .error, suggestion: "使用精确值")
        let match = TabooMatch(rule: errorRule, line: 1, matchedText: "大约 5mm")
        let factResult = FactVerificationResult(
            passed: true, preservedCount: 3,
            lostFacts: [], addedFacts: [])
        let diag = DiagnosisResult(taboos: [match], factVerification: factResult)
        if case .fail(let belowMin, let score) = diag.verdict {
            XCTAssertEqual(score, 0)
            XCTAssertTrue(belowMin.contains("禁用词"))
        } else {
            XCTFail("Expected .fail, got \(diag.verdict)")
        }
    }

    func testVerdictFail_whenFactsLost() {
        let lostFact = FactMarker(fact: "螺旋机构", source: "input")
        let factResult = FactVerificationResult(
            passed: false, preservedCount: 2,
            lostFacts: [lostFact], addedFacts: [])
        let diag = DiagnosisResult(taboos: [], factVerification: factResult)
        if case .fail(let belowMin, let score) = diag.verdict {
            XCTAssertEqual(score, 0)
            XCTAssertTrue(belowMin.contains("事实丢失"))
        } else {
            XCTFail("Expected .fail, got \(diag.verdict)")
        }
    }

    func testVerdictPass_whenWarningTabooOnly() {
        let warnRule = TabooRule(
            pattern: "最好", reason: "模糊用语",
            severity: .warning, suggestion: "删除")
        let match = TabooMatch(rule: warnRule, line: 1, matchedText: "最好")
        let factResult = FactVerificationResult(
            passed: true, preservedCount: 1,
            lostFacts: [], addedFacts: [])
        let diag = DiagnosisResult(taboos: [match], factVerification: factResult)
        if case .pass = diag.verdict {
            // warning taboos don't fail
        } else {
            XCTFail("Expected .pass for warning-only taboos, got \(diag.verdict)")
        }
    }

    // MARK: - DraftEvaluation.summary

    func testDraftEvaluationSummary_containsTabooCount() {
        let factResult = FactVerificationResult(
            passed: true, preservedCount: 5,
            lostFacts: [], addedFacts: [])
        let diag = DiagnosisResult(taboos: [], factVerification: factResult)
        let eval = DraftEvaluation(diagnosis: diag, verdict: .pass)
        XCTAssertTrue(eval.summary.contains("0 处"))
    }

    // MARK: - TwoPassDraft

    func testExtractFacts_fromMarkedText() async {
        let engine = TwoPassDraft()
        let facts = await engine.extractFacts(
            from: "[FACT: 螺旋机构]一种螺旋传动装置[/FACT]")
        XCTAssertEqual(facts.count, 1)
        XCTAssertEqual(facts.first?.fact, "螺旋机构")
    }

    func testDiagnose_cleanDraft_passes() async {
        let engine = TwoPassDraft()
        let fact = FactMarker(fact: "螺旋机构", source: "input")
        let draft = "1. 一种螺旋传动装置，包括螺旋机构和驱动单元。[FACT: 螺旋机构]"
        let result = await engine.diagnose(draft: draft, inputFacts: [fact])
        XCTAssertEqual(result.taboos.count, 0)
        if case .pass = result.verdict {
            // clean draft passes
        } else {
            XCTFail("Expected .pass for clean draft, got \(result.verdict)")
        }
    }

    func testDiagnose_errorTaboo_fails() async {
        let engine = TwoPassDraft()
        let fact = FactMarker(fact: "螺旋机构", source: "input")
        // "大约" is error-level taboo in the built-in rules
        let draft = "1. 一种传动装置，大约 5mm。[FACT: 螺旋机构]"
        let result = await engine.diagnose(draft: draft, inputFacts: [fact])
        XCTAssertFalse(result.taboos.isEmpty)
        if case .fail = result.verdict {
            // error taboo triggers fail
        } else {
            XCTFail("Expected .fail for error taboo, got \(result.verdict)")
        }
    }

    func testDiagnose_factLost_fails() async {
        let engine = TwoPassDraft()
        let fact = FactMarker(fact: "螺旋机构", source: "input")
        // Fact not mentioned in draft — lost
        let draft = "1. 一种传动装置，包括驱动单元。"
        let result = await engine.diagnose(draft: draft, inputFacts: [fact])
        if case .fail(let belowMin, _) = result.verdict {
            XCTAssertTrue(belowMin.contains("事实丢失"))
        } else {
            XCTFail("Expected .fail for lost fact, got \(result.verdict)")
        }
    }

    func testEvaluate_cleanDraft_passes() async {
        let engine = TwoPassDraft()
        let fact = FactMarker(fact: "螺旋机构", source: "input")
        let draft = "1. 一种螺旋传动装置。[FACT: 螺旋机构]"
        let eval = await engine.evaluate(draft: draft, inputFacts: [fact])
        if case .pass = eval.verdict {
            XCTAssertTrue(eval.summary.contains("0 处"))
        } else {
            XCTFail("Expected .pass, got \(eval.verdict)")
        }
    }

    func testEvaluate_errorTaboo_fails() async {
        let engine = TwoPassDraft()
        let fact = FactMarker(fact: "螺旋机构", source: "input")
        let draft = "1. 一种传动装置，大约 5mm。[FACT: 螺旋机构]"
        let eval = await engine.evaluate(draft: draft, inputFacts: [fact])
        if case .fail = eval.verdict {
            // fail as expected
        } else {
            XCTFail("Expected .fail, got \(eval.verdict)")
        }
    }
}
