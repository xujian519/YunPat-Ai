import Foundation // swiftlint:disable:this file_name

// MARK: - Google Patents 类型

/// 专利完整信息（Google Patents 结构化提取）
public struct PatentInfo: Codable, Sendable {
    public let patentNumber: String
    public let title: String
    public let inventors: [String]
    public let assignee: String
    public let assigneeOriginal: [String]
    public let assigneeCurrent: [String]
    public let publicationDate: String
    public let abstract: String
    public let url: String
    public let filingDate: String
    public let priorityDate: String
    public let grantDate: String
    public let expirationDate: String
    public let legalStatus: String
    public let ifiStatus: String
    public let estimatedExpiration: String
    public let pdfUrl: String
    public let classifications: [String]
    public let forwardCitations: [Citation]
    public let backwardCitations: [Citation]

    public init(
        patentNumber: String,
        title: String = "",
        inventors: [String] = [],
        assignee: String = "",
        assigneeOriginal: [String] = [],
        assigneeCurrent: [String] = [],
        publicationDate: String = "",
        abstract: String = "",
        url: String = "",
        filingDate: String = "",
        priorityDate: String = "",
        grantDate: String = "",
        expirationDate: String = "",
        legalStatus: String = "",
        ifiStatus: String = "",
        estimatedExpiration: String = "",
        pdfUrl: String = "",
        classifications: [String] = [],
        forwardCitations: [Citation] = [],
        backwardCitations: [Citation] = []
    ) {
        self.patentNumber = patentNumber
        self.title = title
        self.inventors = inventors
        self.assignee = assignee
        self.assigneeOriginal = assigneeOriginal
        self.assigneeCurrent = assigneeCurrent
        self.publicationDate = publicationDate
        self.abstract = abstract
        self.url = url
        self.filingDate = filingDate
        self.priorityDate = priorityDate
        self.grantDate = grantDate
        self.expirationDate = expirationDate
        self.legalStatus = legalStatus
        self.ifiStatus = ifiStatus
        self.estimatedExpiration = estimatedExpiration
        self.pdfUrl = pdfUrl
        self.classifications = classifications
        self.forwardCitations = forwardCitations
        self.backwardCitations = backwardCitations
    }
}

public struct Citation: Codable, Sendable {
    public let patentNumber: String
    public let priorityDate: String
    public let pubDate: String

    public init(patentNumber: String, priorityDate: String = "", pubDate: String = "") {
        self.patentNumber = patentNumber
        self.priorityDate = priorityDate
        self.pubDate = pubDate
    }
}

// MARK: - PSS 类型

/// PSS 登录会话（Cookie 持久化）
public struct PssSession: Codable, Sendable {
    public let cookies: [String: String]
    public let createdAt: Date

    public var isValid: Bool {
        Date().timeIntervalSince(createdAt) < 1800  // 30 分钟
    }

    public init(cookies: [String: String], createdAt: Date = Date()) {
        self.cookies = cookies
        self.createdAt = createdAt
    }
}

/// PSS 搜索结果
public struct PssSearchResult: Codable, Sendable {
    public let keyword: String
    public let totalHits: Int
    public let patents: [PssPatentBrief]

    public init(keyword: String, totalHits: Int = 0, patents: [PssPatentBrief] = []) {
        self.keyword = keyword
        self.totalHits = totalHits
        self.patents = patents
    }
}

/// PSS 专利摘要（搜索结果中的单条）
public struct PssPatentBrief: Codable, Sendable {
    public let pubNumber: String
    public let title: String
    public let applicant: String
    public let appNumber: String
    public let appDate: String
    public let pubDate: String
    public let status: String
    public let ipc: String

    public init(
        pubNumber: String = "",
        title: String = "",
        applicant: String = "",
        appNumber: String = "",
        appDate: String = "",
        pubDate: String = "",
        status: String = "",
        ipc: String = ""
    ) {
        self.pubNumber = pubNumber
        self.title = title
        self.applicant = applicant
        self.appDate = appDate
        self.appNumber = appNumber
        self.pubDate = pubDate
        self.status = status
        self.ipc = ipc
    }
}

/// PSS 专利详情
public struct PssPatentDetail: Codable, Sendable {
    public let pubNumber: String
    public let title: String
    public let appNumber: String
    public let appDate: String
    public let pubDate: String
    public let applicant: String
    public let inventor: String
    public let ipc: String
    public let cpc: String
    public let priority: String
    public let abstract: String
    public let claims: String
    public let description: String
    public let status: String
    public let agency: String
    public let agent: String
    public let address: String
    public let imageURL: String?

    public init(
        pubNumber: String = "",
        title: String = "",
        appNumber: String = "",
        appDate: String = "",
        pubDate: String = "",
        applicant: String = "",
        inventor: String = "",
        ipc: String = "",
        cpc: String = "",
        priority: String = "",
        abstract: String = "",
        claims: String = "",
        description: String = "",
        status: String = "",
        agency: String = "",
        agent: String = "",
        address: String = "",
        imageURL: String? = nil
    ) {
        self.pubNumber = pubNumber
        self.title = title
        self.appNumber = appNumber
        self.appDate = appDate
        self.pubDate = pubDate
        self.applicant = applicant
        self.inventor = inventor
        self.ipc = ipc
        self.cpc = cpc
        self.priority = priority
        self.abstract = abstract
        self.claims = claims
        self.description = description
        self.status = status
        self.agency = agency
        self.agent = agent
        self.address = address
        self.imageURL = imageURL
    }
}

// MARK: - 错误类型

public enum PatentClientError: Error, Sendable, LocalizedError {
    case networkError(String)
    case parseError(String)
    case notFound(String)
    case unauthorized(String)
    case invalidPatentNumber(String)

    public var errorDescription: String? {
        switch self {
        case .networkError(let msg): return "网络错误: \(msg)"
        case .parseError(let msg): return "解析错误: \(msg)"
        case .notFound(let msg): return "未找到: \(msg)"
        case .unauthorized(let msg): return "未授权: \(msg)"
        case .invalidPatentNumber(let msg): return "无效专利号: \(msg)"
        }
    }
}
