import Foundation

// MARK: - Knowledge Graph Node

struct KGNode: Sendable {
    let id: String
    let type: String
    let name: String
    let relations: [(targetId: String, relation: String)]
    let excerpt: String
}

// MARK: - Chinese Patent Law Knowledge Graph

/// 中国专利法知识图谱 — 涵盖专利法第22条（新颖性/创造性/实用性）、
/// 第26条第4款（权利要求清楚/支持）、第33条（修改超范围）及对应审查指南章节
enum PatentLawKG {

    static let nodes: [KGNode] = [
        // 专利法第22条第2款 — 新颖性
        KGNode(
            id: "art-22-2",
            type: "legal_requirement",
            name: "专利法第22条第2款 新颖性",
            relations: [
                ("art-22-2-def", "defined_by"),
                ("art-22-3", "contrasts_with"),
                ("gl-novelty", "guideline_ref")
            ],
            excerpt: "新颖性，是指该发明或者实用新型不属于现有技术；也没有任何单位或者个人就同样的发明或者实用新型在申请日以前向专利局提出过申请。"  // swiftlint:disable:this line_length
        ),
        KGNode(
            id: "art-22-2-def",
            type: "legal_standard",
            name: "现有技术判断标准",
            relations: [
                ("art-22-2-priority", "requires"),
                ("gl-novelty", "guides")
            ],
            excerpt: "现有技术是指申请日以前在国内外为公众所知的技术。包括出版物公开、使用公开和其他方式公开。"
        ),
        KGNode(
            id: "art-22-2-priority",
            type: "fact_pattern",
            name: "优先权与申请日",
            relations: [("art-22-2-def", "evaluated_against")],
            excerpt: "判断新颖性时以申请日（或优先权日）为时间基准，对比现有技术的公开日期。"
        ),

        // 专利法第22条第3款 — 创造性
        KGNode(
            id: "art-22-3",
            type: "legal_requirement",
            name: "专利法第22条第3款 创造性",
            relations: [
                ("three-step", "defined_by"),
                ("art-22-2", "contrasts_with"),
                ("gl-inventive", "guideline_ref")
            ],
            excerpt: "创造性，是指与现有技术相比，该发明具有突出的实质性特点和显著的进步。"
        ),
        KGNode(
            id: "three-step",
            type: "legal_standard",
            name: "三步法判断法",
            relations: [
                ("closest-prior-art", "step_1"),
                ("distinguishing-features", "step_2"),
                ("obviousness-test", "step_3")
            ],
            excerpt: "1. 确定最接近的现有技术；2. 确定区别特征和实际解决的技术问题；3. 判断是否显而易见。"
        ),
        KGNode(
            id: "closest-prior-art",
            type: "fact_pattern",
            name: "最接近的现有技术",
            relations: [("distinguishing-features", "leads_to")],
            excerpt: "选择技术领域相同或相近、所要解决的技术问题和技术效果最接近的现有技术。"
        ),
        KGNode(
            id: "distinguishing-features",
            type: "fact_pattern",
            name: "区别技术特征",
            relations: [("actual-problem", "determines")],
            excerpt: "对比要求保护的发明与最接近现有技术，确定区别技术特征。"
        ),
        KGNode(
            id: "actual-problem",
            type: "fact_pattern",
            name: "实际解决的技术问题",
            relations: [("obviousness-test", "evaluated_in")],
            excerpt: "基于区别特征所能达到的技术效果来确定发明实际解决的技术问题。"
        ),
        KGNode(
            id: "obviousness-test",
            type: "legal_standard",
            name: "显而易见性判断",
            relations: [],
            excerpt: "判断现有技术中是否给出将上述区别特征应用到最接近现有技术的技术启示。"
        ),

        // 专利法第26条第4款 — 权利要求清楚/支持
        KGNode(
            id: "art-26-4",
            type: "legal_requirement",
            name: "专利法第26条第4款 权利要求清楚与支持",
            relations: [
                ("clarity-test", "clarity_requirement"),
                ("support-test", "support_requirement"),
                ("gl-claims", "guideline_ref")
            ],
            excerpt: "权利要求书应当以说明书为依据，清楚、简要地限定要求专利保护的范围。"
        ),
        KGNode(
            id: "clarity-test",
            type: "legal_standard",
            name: "权利要求清楚性",
            relations: [],
            excerpt: "权利要求的用语应当清楚，保护范围边界明确，不得使用含糊不清的表述。"
        ),
        KGNode(
            id: "support-test",
            type: "legal_standard",
            name: "说明书支持",
            relations: [],
            excerpt: "权利要求的技术方案应当得到说明书充分公开内容的支持，不应超出说明书记载的范围。"
        ),

        // 专利法第33条 — 修改超范围
        KGNode(
            id: "art-33",
            type: "legal_requirement",
            name: "专利法第33条 修改不超范围",
            relations: [("gl-amendment", "guideline_ref")],
            excerpt: "申请人可以对其专利申请文件进行修改，但修改不得超出原说明书和权利要求书记载的范围。"
        ),

        // 审查指南引用
        KGNode(
            id: "gl-novelty",
            type: "guideline",
            name: "审查指南第二部分第三章 新颖性",
            relations: [],
            excerpt: "审查指南对新颖性审查的标准、对比方式、同样的发明等进行了详细规定。"
        ),
        KGNode(
            id: "gl-inventive",
            type: "guideline",
            name: "审查指南第二部分第四章 创造性",
            relations: [],
            excerpt: "审查指南对创造性判断的三步法、组合发明、选择性发明等情形进行了规定。"
        ),
        KGNode(
            id: "gl-claims",
            type: "guideline",
            name: "审查指南第二部分第二章 权利要求书",
            relations: [],
            excerpt: "审查指南对权利要求的撰写要求、清楚性、简要性、支持性进行了规定。"
        ),
        KGNode(
            id: "gl-amendment",
            type: "guideline",
            name: "审查指南第一部分第二章 申请文件的修改",
            relations: [],
            excerpt: "审查指南对修改的内容与范围、主动修改的时机等进行了规定。"
        )
    ]

    static let nodeMap: [String: KGNode] = {
        var map: [String: KGNode] = [:]
        for node in nodes { map[node.id] = node }
        return map
    }()

    /// 关键词到 KG 节点的索引
    static let keywordIndex: [String: [String]] = {
        var index: [String: [String]] = [:]
        for node in nodes {
            let keywords: [String] = extractKeywords(from: node.name)
            for keyword in keywords {
                index[keyword, default: []].append(node.id)
            }
        }
        return index
    }()

    private static func extractKeywords(from text: String) -> [String] {
        let lowered: String = text.lowercased()
        var keywords: [String] = []

        if lowered.contains("新颖") || lowered.contains("novelty") { keywords.append("新颖性") }
        if lowered.contains("创造") || lowered.contains("inventive") { keywords.append("创造性") }
        if lowered.contains("三步") || lowered.contains("three") { keywords.append("三步法") }
        if lowered.contains("区别") || lowered.contains("distinguish") { keywords.append("区别特征") }
        if lowered.contains("显而易见") || lowered.contains("obvious") { keywords.append("显而易见") }
        if lowered.contains("现有技术") || lowered.contains("prior art") { keywords.append("现有技术") }
        if lowered.contains("权利要求") || lowered.contains("claim") { keywords.append("权利要求") }
        if lowered.contains("清楚") || lowered.contains("clarity") { keywords.append("清楚性") }
        if lowered.contains("支持") || lowered.contains("support") { keywords.append("支持") }
        if lowered.contains("修改") || lowered.contains("amend") { keywords.append("修改") }
        if lowered.contains("22.2") || lowered.contains("22条第2款") { keywords.append("22.2") }
        if lowered.contains("22.3") || lowered.contains("22条第3款") { keywords.append("22.3") }
        if lowered.contains("26.4") || lowered.contains("26条第4款") { keywords.append("26.4") }
        if lowered.contains("33条") { keywords.append("33") }
        if lowered.contains("技术问题") { keywords.append("技术问题") }
        if lowered.contains("技术特征") { keywords.append("技术特征") }

        return keywords.isEmpty ? ["general"] : keywords
    }
}
