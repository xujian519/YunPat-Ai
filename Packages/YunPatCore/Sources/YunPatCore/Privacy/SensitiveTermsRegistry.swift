import Foundation

/// 客户级敏感词表 — 三层：案件(workspace) > 客户(client) > 事务所(firm) > 默认
public actor SensitiveTermsRegistry {

    public static let shared: SensitiveTermsRegistry = SensitiveTermsRegistry()
    /// 敏感词条目
    public struct Term: Sendable, Codable, Equatable {
        public let value: String
        public let kind: EntityKind
        public let scope: Scope
        public init(value: String, kind: EntityKind = .custom, scope: Scope = .firmLevel) {
            self.value = value
            self.kind = kind
            self.scope = scope
        }
    }

    public enum Scope: String, Sendable, Codable, Comparable {
        /// workspace/.yunpat/sensitive/\{caseId\}.txt
        case caseLevel
        /// ~/.yunpat/templates/sensitive/\{client\}.txt
        case clientLevel
        /// ~/.yunpat/templates/sensitive/firm.txt
        case firmLevel

        public static func < (l: Scope, r: Scope) -> Bool {
            let order: [Scope] = [.caseLevel, .clientLevel, .firmLevel]
            return order.firstIndex(of: l)! < order.firstIndex(of: r)!
        }
    }

    private var terms: [Term] = []

    private init() {}

    /// 注册一系列敏感词
    public func register(_ terms: [Term]) {
        self.terms.append(contentsOf: terms)
    }

    /// 注册一个敏感词
    public func register(value: String, kind: EntityKind = .custom, scope: Scope = .firmLevel) {
        terms.append(Term(value: value, kind: kind, scope: scope))
    }

    /// 获取某案件的敏感词（按优先级排序：case > client > firm > default）
    public func terms(forCase caseId: String?) -> [Term] {
        terms.filter { term in
            switch term.scope {
            case .caseLevel: true
            case .clientLevel, .firmLevel: true
            }
        }
    }

    /// 从文件加载（预计格式：每行一个敏感词）
    public func loadFrom(url: URL, scope: Scope) throws {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        for line in lines {
            if line.contains("::") {
                let parts = line.components(separatedBy: "::")

                let kindStr = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts.dropFirst().joined(separator: "::").trimmingCharacters(in: .whitespaces)
                let resolvedKind: EntityKind = EntityKind(rawValue: kindStr) ?? .custom
                terms.append(Term(value: value, kind: resolvedKind, scope: scope))
            } else {
                terms.append(Term(value: line, kind: .custom, scope: scope))
            }
        }
    }

    /// 清空
    public func reset() {
        terms.removeAll()
    }

    /// 获取某案件的所有敏感词原文列表
    public func rawTerms(forCase caseId: String? = nil) -> [String] {
        terms.map(\.value)
    }
}
