import Foundation

public enum AccountKind: String, Codable, Sendable {
    case claudePlan
    case enterpriseAnalytics
}

public struct Account: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public let kind: AccountKind

    public init(id: UUID = UUID(), name: String, kind: AccountKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

public struct LimitWindow: Codable, Equatable, Sendable {
    public let utilization: Double
    public let resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
        self.utilization = min(max(utilization, 0), 100)
        self.resetsAt = resetsAt
    }
}

public struct PlanUsage: Equatable, Sendable {
    public let fiveHour: LimitWindow?
    public let sevenDay: LimitWindow?
    public let sevenDaySonnet: LimitWindow?
    public let sevenDayOpus: LimitWindow?

    public init(
        fiveHour: LimitWindow?,
        sevenDay: LimitWindow?,
        sevenDaySonnet: LimitWindow? = nil,
        sevenDayOpus: LimitWindow? = nil
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDaySonnet = sevenDaySonnet
        self.sevenDayOpus = sevenDayOpus
    }

    public var highestUtilization: Double {
        [fiveHour, sevenDay, sevenDaySonnet, sevenDayOpus]
            .compactMap(\.self)
            .map(\.utilization)
            .max() ?? 0
    }
}

public struct TeamMemberUsage: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let email: String?
    public let totalTokens: Int64
    public let requests: Int

    public init(id: String, name: String, email: String?, totalTokens: Int64, requests: Int) {
        self.id = id
        self.name = name
        self.email = email
        self.totalTokens = totalTokens
        self.requests = requests
    }
}

public struct TeamUsage: Equatable, Sendable {
    public let members: [TeamMemberUsage]
    public let refreshedAt: Date?

    public init(members: [TeamMemberUsage], refreshedAt: Date?) {
        self.members = members
        self.refreshedAt = refreshedAt
    }

    public var totalTokens: Int64 { members.reduce(0) { $0 + $1.totalTokens } }
}

public enum AccountSnapshot: Equatable, Sendable {
    case plan(PlanUsage)
    case team(TeamUsage)
}

public enum UsageError: LocalizedError, Sendable {
    case noClaudeLogin
    case malformedCredentials
    case missingSecret
    case invalidResponse
    case invalidOAuthCode(String)
    case unauthorized(String)
    case server(Int, String)

    public var errorDescription: String? {
        switch self {
        case .noClaudeLogin:
            "No Claude Code login found. Run `claude /login` in Terminal, then import again."
        case .malformedCredentials:
            "Claude Code credentials were found but could not be read."
        case .missingSecret:
            "The account secret is missing from Keychain. Import or add the account again."
        case .invalidResponse:
            "Anthropic returned a response this version does not understand."
        case .invalidOAuthCode(let detail):
            "The authorization code is invalid. \(detail)"
        case .unauthorized(let detail):
            "Authentication failed. \(detail)"
        case .server(let status, let detail):
            "Anthropic returned HTTP \(status). \(detail)"
        }
    }
}
