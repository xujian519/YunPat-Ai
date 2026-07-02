import Foundation
import Testing

@testable import YunPatCore

struct SkillManagerTests {

    // MARK: - Helpers

    private func makeSkill(
        name: String = "test-skill", displayName: String = "测试技能",
        triggers: [String] = [], tags: [String] = []
    ) -> SkillContent {
        SkillContent(
            manifest: SkillManifest(
                name: name,
                displayName: displayName,
                description: "测试用技能",
                tags: tags,
                triggers: triggers
            ),
            body: "技能正文内容"
        )
    }

    // MARK: - register

    @Test func register_increasesCount() async {
        let manager: SkillManager = SkillManager()
        let skill: SkillContent = makeSkill()

        #expect(await manager.count() == 0)

        await manager.register(skill)
        #expect(await manager.count() == 1)
    }

    @Test func register_multipleSkills_increasesCount() async {
        let manager: SkillManager = SkillManager()
        await manager.register(makeSkill(name: "s1"))
        await manager.register(makeSkill(name: "s2"))
        await manager.register(makeSkill(name: "s3"))

        #expect(await manager.count() == 3)
        #expect(await manager.allSkills().count == 3)
    }

    @Test func allSkills_returnsRegisteredSkills() async {
        let manager: SkillManager = SkillManager()
        let skill: SkillContent = makeSkill(name: "my-skill")
        await manager.register(skill)

        let skills: [SkillMatch] = await manager.allSkills()
        #expect(skills.count == 1)
        #expect(skills.first?.manifest.name == "my-skill")
    }

    // MARK: - match (trigger exact match, weight 10)

    @Test func match_triggerExactMatch_scores10() async {
        let manager: SkillManager = SkillManager()
        let skill: SkillContent = makeSkill(triggers: ["专利分析", "侵权分析"])
        await manager.register(skill)

        let request: UserRequest = UserRequest(content: "请进行专利分析")
        let matches: [SkillMatch] = await manager.match(for: request)

        #expect(!matches.isEmpty)
        #expect(matches.first?.score == 10)
    }

    @Test func match_multipleTriggers_firstMatchScores10() async {
        let manager: SkillManager = SkillManager()
        let skill: SkillContent = makeSkill(triggers: ["深度推理", "专利分析", "侵权比对"])
        await manager.register(skill)

        let request: UserRequest = UserRequest(content: "我需要深度推理支持")
        let matches: [SkillMatch] = await manager.match(for: request)

        #expect(!matches.isEmpty)
        #expect(matches.first?.score == 10)
    }

    @Test func match_noMatch_returnsEmpty() async {
        let manager: SkillManager = SkillManager()
        let skill: SkillContent = makeSkill(triggers: ["特定触发词"])
        await manager.register(skill)

        let request: UserRequest = UserRequest(content: "完全不相关的内容")
        let matches: [SkillMatch] = await manager.match(for: request)

        #expect(matches.isEmpty)
    }

    // MARK: - matchByKeywords (tag match, weight 2)

    @Test func matchByKeywords_tagMatch_scores2() async {
        let manager: SkillManager = SkillManager()
        let skill: SkillContent = makeSkill(tags: ["专利分析", "侵权评估"])
        await manager.register(skill)

        let request: UserRequest = UserRequest(content: "请进行专利分析")
        let matches: [SkillMatch] = await manager.matchByKeywords(for: request)

        #expect(!matches.isEmpty)
        #expect(matches.first?.score == 2)
    }

    @Test func matchByKeywords_multipleTags_accumulatesScore() async {
        let manager: SkillManager = SkillManager()
        let skill: SkillContent = makeSkill(tags: ["专利", "分析", "侵权"])
        await manager.register(skill)

        let request: UserRequest = UserRequest(content: "专利侵权分析报告")
        let matches: [SkillMatch] = await manager.matchByKeywords(for: request)

        #expect(!matches.isEmpty)
        // All 3 tags match, each gives 2 -> total 6
        #expect(matches.first?.score == 6)
    }

    @Test func matchByKeywords_triggerAndTag_accumulatesScore() async {
        let manager: SkillManager = SkillManager()
        let skill: SkillContent = makeSkill(triggers: ["分析"], tags: ["专利", "侵权"])
        await manager.register(skill)

        let request: UserRequest = UserRequest(content: "专利侵权分析")
        let matches: [SkillMatch] = await manager.matchByKeywords(for: request)

        #expect(!matches.isEmpty)
        // Trigger match: 10, 2 tag matches: 4 -> total 14
        #expect(matches.first?.score == 14)
    }

    @Test func matchByKeywords_noMatch_returnsEmpty() async {
        let manager: SkillManager = SkillManager()
        let skill: SkillContent = makeSkill(tags: ["无关标签"])
        await manager.register(skill)

        let request: UserRequest = UserRequest(content: "完全无关的内容")
        let matches: [SkillMatch] = await manager.matchByKeywords(for: request)

        #expect(matches.isEmpty)
    }

    // MARK: - remove

    @Test func remove_removesSkillByName() async {
        let manager: SkillManager = SkillManager()
        await manager.register(makeSkill(name: "to-remove"))
        #expect(await manager.count() == 1)

        await manager.remove(name: "to-remove")
        #expect(await manager.count() == 0)
    }

    @Test func remove_onlyRemovesMatchingName() async {
        let manager: SkillManager = SkillManager()
        await manager.register(makeSkill(name: "keep"))
        await manager.register(makeSkill(name: "to-remove"))
        #expect(await manager.count() == 2)

        await manager.remove(name: "to-remove")
        #expect(await manager.count() == 1)

        let remaining: [SkillMatch] = await manager.allSkills()
        #expect(remaining.first?.manifest.name == "keep")
    }

    @Test func remove_nonexistent_doesNotThrow() async {
        let manager: SkillManager = SkillManager()
        await manager.register(makeSkill(name: "existing"))

        await manager.remove(name: "nonexistent")
        #expect(await manager.count() == 1)
    }

    @Test func removeAll_clearsAllSkills() async {
        let manager: SkillManager = SkillManager()
        await manager.register(makeSkill(name: "s1"))
        await manager.register(makeSkill(name: "s2"))

        await manager.removeAll()
        #expect(await manager.count() == 0)
        #expect(await manager.allSkills().isEmpty)
    }

    // MARK: - loadBuiltinSkills

    @Test func loadBuiltinSkills_noBundleResource_returnsEmpty() async throws {
        let manager: SkillManager = SkillManager()
        // In test environment, Bundle.main has no "Skills" resource directory
        let manifests: [SkillManifest] = try await manager.loadBuiltinSkills()
        #expect(manifests.isEmpty)
    }

    // MARK: - score > 0 verification

    @Test func match_onlyReturnsSkillsWithPositiveScore() async {
        let manager: SkillManager = SkillManager()
        await manager.register(makeSkill(triggers: ["unrelated"], tags: ["other"]))

        let request: UserRequest = UserRequest(content: "完全无关的请求内容")
        let matches: [SkillMatch] = await manager.match(for: request)

        #expect(matches.isEmpty)
    }

    @Test func matchByKeywords_onlyReturnsSkillsWithPositiveScore() async {
        let manager: SkillManager = SkillManager()
        await manager.register(makeSkill(tags: ["甲亢"]))

        let request: UserRequest = UserRequest(content: "今天天气很好")
        let matches: [SkillMatch] = await manager.matchByKeywords(for: request)

        #expect(matches.isEmpty)
    }

    // MARK: - sorting

    @Test func match_returnsSortedByScoreDescending() async {
        let manager: SkillManager = SkillManager()
        await manager.register(makeSkill(name: "tag-skill", tags: ["专利"]))
        await manager.register(makeSkill(name: "trigger-skill", triggers: ["专利分析"]))

        let request: UserRequest = UserRequest(content: "专利分析请求")
        let matches: [SkillMatch] = await manager.match(for: request)

        #expect(matches.count >= 2)
        // trigger-skill (score 10) should be first
        #expect(matches.first?.skill.manifest.name == "trigger-skill")
    }
}
