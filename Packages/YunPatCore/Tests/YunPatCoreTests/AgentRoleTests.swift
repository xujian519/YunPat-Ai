import XCTest

@testable import YunPatCore

final class AgentRoleTests: XCTestCase {

    // MARK: - 预设角色

    func test_searcher_preset() {
        let role: AgentRole = AgentRole.searcher
        XCTAssertEqual(role.name, "searcher")
        XCTAssertFalse(role.systemPrompt.isEmpty)
        XCTAssertNotNil(role.toolGroupIDs)
        XCTAssertEqual(role.toolGroupIDs?.contains("patent_search"), true)
        XCTAssertEqual(role.toolGroupIDs?.contains("knowledge_search"), true)
        XCTAssertEqual(role.maxIterations, 5)
    }

    func test_analyst_preset() {
        let role: AgentRole = AgentRole.analyst
        XCTAssertEqual(role.name, "analyst")
        XCTAssertEqual(role.toolGroupIDs?.contains("read_file"), true)
        XCTAssertEqual(role.maxIterations, 8)
    }

    func test_drafter_preset() {
        let role: AgentRole = AgentRole.drafter
        XCTAssertEqual(role.name, "drafter")
        XCTAssertEqual(role.toolGroupIDs?.contains("write_file"), true)
        XCTAssertEqual(role.toolGroupIDs?.contains("edit"), true)
        XCTAssertEqual(role.maxIterations, 15)
    }

    func test_reviewer_preset() {
        let role: AgentRole = AgentRole.reviewer
        XCTAssertEqual(role.name, "reviewer")
        XCTAssertEqual(role.toolGroupIDs?.contains("patent_search"), true)
        XCTAssertEqual(role.maxIterations, 8)
    }

    // MARK: - allPresets

    func test_allPresets_count() {
        XCTAssertEqual(AgentRole.allPresets.count, 4)
        let names = Set(AgentRole.allPresets.map(\.name))
        XCTAssertEqual(names, ["searcher", "analyst", "drafter", "reviewer"])
    }

    // MARK: - makePrompt

    func test_makePrompt_combinesSystemAndTask() {
        let role = AgentRole(
            name: "test",
            systemPrompt: "你是测试员。",
            toolGroupIDs: nil
        )
        let prompt = role.makePrompt(task: "执行测试")
        XCTAssertTrue(prompt.contains("你是测试员"))
        XCTAssertTrue(prompt.contains("执行测试"))
        XCTAssertTrue(prompt.contains("---"))
    }

    // MARK: - 自定义角色

    func test_customRole() {
        let role = AgentRole(
            name: "translator",
            systemPrompt: "你是翻译专家",
            toolGroupIDs: ["read_file", "write_file"],
            maxIterations: 3,
            description: "专利翻译"
        )
        XCTAssertEqual(role.name, "translator")
        XCTAssertEqual(role.toolGroupIDs?.count, 2)
        XCTAssertEqual(role.maxIterations, 3)
        XCTAssertEqual(role.description, "专利翻译")
    }

    func test_customRole_defaultValues() {
        let role = AgentRole(name: "minimal", systemPrompt: "hi")
        XCTAssertEqual(role.name, "minimal")
        XCTAssertNil(role.toolGroupIDs)
        XCTAssertEqual(role.maxIterations, 10)
        XCTAssertTrue(role.description.isEmpty)
    }

    // MARK: - 角色不重复

    func test_presetNames_unique() {
        let names = AgentRole.allPresets.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "预设角色名不应重复")
    }

    // MARK: - 角色系统提示不为空

    func test_allPresets_haveNonEmptyPrompts() {
        for role in AgentRole.allPresets {
            XCTAssertFalse(role.systemPrompt.isEmpty, "\(role.name) 系统提示不应为空")
            XCTAssertFalse(role.description.isEmpty, "\(role.name) 描述不应为空")
        }
    }
}
