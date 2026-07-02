import Testing

@testable import YunPatCore

struct ToolUsageGuideTests {
    let registry: CapabilityRegistry = CapabilityRegistry()

    @Test func usageGuideExistsForPatentSearch() async {
        let guide: String? = await registry.usageGuide(for: "patent_search")
        #expect(guide != nil, "patent_search should have a TOOL.md guide")
    }

    @Test func usageGuideExistsForWriteFile() async {
        let guide: String? = await registry.usageGuide(for: "write_file")
        #expect(guide != nil, "write_file should have a TOOL.md guide")
    }

    @Test func usageGuideMissingTool() async {
        let guide: String? = await registry.usageGuide(for: "nonexistent_tool")
        #expect(guide == nil, "non-existent tool should return nil")
    }

    @Test func usageGuideNotEmpty() async {
        guard let guide = await registry.usageGuide(for: "patent_search") else {
            #expect(Bool(false), "patent_search guide should exist")
            return
        }
        #expect(guide.count > 100, "Guide should have meaningful content")
    }
}
