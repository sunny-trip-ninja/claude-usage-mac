import CryptoKit
import Foundation
import Security

public struct AnalyticsCredential: Codable, Equatable, Sendable {
    public let apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }
}

public struct OAuthUsageResult: Sendable {
    public let usage: PlanUsage
    public let credential: OAuthCredential
}

public struct OAuthAuthorization: Equatable, Sendable {
    public let authorizationURL: URL
    public let codeVerifier: String
    public let state: String

    public init(authorizationURL: URL, codeVerifier: String, state: String) {
        self.authorizationURL = authorizationURL
        self.codeVerifier = codeVerifier
        self.state = state
    }

    public static func make(useSSO: Bool = false) throws -> OAuthAuthorization {
        let verifier = try randomURLSafeString()
        let state = try randomURLSafeString()
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest).base64URLEncodedString()

        var components = URLComponents(string: "https://claude.com/cai/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: AnthropicClient.oauthClientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: AnthropicClient.manualRedirectURI),
            URLQueryItem(name: "scope", value: AnthropicClient.authorizationScopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        if useSSO {
            components.queryItems?.append(URLQueryItem(name: "login_method", value: "sso"))
        }
        guard let url = components.url else { throw UsageError.invalidResponse }
        return OAuthAuthorization(authorizationURL: url, codeVerifier: verifier, state: state)
    }

    public func authorizationCode(from pastedValue: String) throws -> String {
        let value = pastedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let pieces = value.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        guard pieces.count == 2, !pieces[0].isEmpty, !pieces[1].isEmpty else {
            throw UsageError.invalidOAuthCode("Copy and paste the complete `code#state` value from the browser.")
        }
        guard String(pieces[1]) == state else {
            throw UsageError.invalidOAuthCode("The code belongs to a different login attempt. Start the browser login again.")
        }
        return String(pieces[0])
    }

    private static func randomURLSafeString() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw UsageError.invalidResponse
        }
        return Data(bytes).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public actor AnthropicClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder = JSONEncoder()
    static let oauthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let manualRedirectURI = "https://platform.claude.com/oauth/code/callback"
    static let authorizationScopes = "org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"
    private let oauthScopes = "user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"

    public init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    public func fetchPlanUsage(using original: OAuthCredential) async throws -> OAuthUsageResult {
        var credential = original
        if let expiry = credential.expiresAt, expiry <= Date().addingTimeInterval(60) {
            credential = try await refresh(credential)
        }

        do {
            let usage = try await requestPlanUsage(credential.accessToken)
            return OAuthUsageResult(usage: usage, credential: credential)
        } catch UsageError.unauthorized where credential.refreshToken != nil {
            credential = try await refresh(credential)
            let usage = try await requestPlanUsage(credential.accessToken)
            return OAuthUsageResult(usage: usage, credential: credential)
        }
    }

    public func exchangeOAuthCode(
        _ pastedValue: String,
        authorization: OAuthAuthorization
    ) async throws -> OAuthCredential {
        let code = try authorization.authorizationCode(from: pastedValue)
        var request = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(CodeExchangeRequest(
            grantType: "authorization_code",
            code: code,
            redirectURI: Self.manualRedirectURI,
            clientID: Self.oauthClientID,
            codeVerifier: authorization.codeVerifier,
            state: authorization.state
        ))
        let data = try await send(request)
        let response = try decoder.decode(RefreshResponse.self, from: data)
        return OAuthCredential(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: Date().addingTimeInterval(response.expiresIn)
        )
    }

    public func fetchTeamUsage(apiKey: String, now: Date = Date()) async throws -> TeamUsage {
        let calendar = Calendar(identifier: .iso8601)
        let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now.addingTimeInterval(-604_800)
        var components = URLComponents(string: "https://api.anthropic.com/v1/organizations/analytics/user_usage_report")!
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: Self.rfc3339(start)),
            URLQueryItem(name: "ending_at", value: Self.rfc3339(now)),
            URLQueryItem(name: "limit", value: "1000"),
            URLQueryItem(name: "order_by", value: "total_tokens"),
            URLQueryItem(name: "order", value: "desc"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("ClaudeUsage/0.1", forHTTPHeaderField: "User-Agent")
        let data = try await send(request)
        let response = try decoder.decode(TeamUsageResponse.self, from: data)
        let members = response.data.map {
            TeamMemberUsage(
                id: $0.actor.userID,
                name: $0.actor.name ?? $0.actor.email ?? "Unknown member",
                email: $0.actor.email,
                totalTokens: $0.totalTokens,
                requests: $0.requests
            )
        }
        return TeamUsage(members: members, refreshedAt: Self.parseDate(response.dataRefreshedAt))
    }

    private func requestPlanUsage(_ token: String) async throws -> PlanUsage {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ClaudeUsage/0.1", forHTTPHeaderField: "User-Agent")
        let data = try await send(request)
        let response = try decoder.decode(PlanUsageResponse.self, from: data)
        return response.model
    }

    private func refresh(_ credential: OAuthCredential) async throws -> OAuthCredential {
        guard let refreshToken = credential.refreshToken else {
            throw UsageError.unauthorized("Sign in with Claude Code again, then re-import this account.")
        }
        var request = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(RefreshRequest(
            grantType: "refresh_token",
            refreshToken: refreshToken,
            clientID: Self.oauthClientID,
            scope: oauthScopes
        ))
        let data = try await send(request)
        let response = try decoder.decode(RefreshResponse.self, from: data)
        return OAuthCredential(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? refreshToken,
            expiresAt: Date().addingTimeInterval(response.expiresIn)
        )
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            let message = Self.errorMessage(data)
            if http.statusCode == 401 || http.statusCode == 403 {
                throw UsageError.unauthorized(message)
            }
            throw UsageError.server(http.statusCode, message)
        }
        return data
    }

    private static func errorMessage(_ data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return String(data: data, encoding: .utf8).flatMap { String($0.prefix(240)) } ?? ""
    }

    private static func rfc3339(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }
}

private struct CodeExchangeRequest: Encodable {
    let grantType: String
    let code: String
    let redirectURI: String
    let clientID: String
    let codeVerifier: String
    let state: String

    enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
        case code
        case redirectURI = "redirect_uri"
        case clientID = "client_id"
        case codeVerifier = "code_verifier"
        case state
    }
}

private struct PlanUsageResponse: Decodable {
    let fiveHour: Window?
    let sevenDay: Window?
    let sevenDaySonnet: Window?
    let sevenDayOpus: Window?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOpus = "seven_day_opus"
    }

    var model: PlanUsage {
        PlanUsage(
            fiveHour: fiveHour?.model,
            sevenDay: sevenDay?.model,
            sevenDaySonnet: sevenDaySonnet?.model,
            sevenDayOpus: sevenDayOpus?.model
        )
    }

    struct Window: Decodable {
        let utilization: Double
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }

        var model: LimitWindow {
            LimitWindow(utilization: utilization, resetsAt: AnthropicClient.parseDate(resetsAt))
        }
    }
}

private struct RefreshRequest: Encodable {
    let grantType: String
    let refreshToken: String
    let clientID: String
    let scope: String

    enum CodingKeys: String, CodingKey {
        case grantType = "grant_type"
        case refreshToken = "refresh_token"
        case clientID = "client_id"
        case scope
    }
}

private struct RefreshResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Double

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct TeamUsageResponse: Decodable {
    let data: [Row]
    let dataRefreshedAt: String?

    enum CodingKeys: String, CodingKey {
        case data
        case dataRefreshedAt = "data_refreshed_at"
    }

    struct Row: Decodable {
        let actor: Actor
        let totalTokens: Int64
        let requests: Int

        enum CodingKeys: String, CodingKey {
            case actor
            case totalTokens = "total_tokens"
            case requests
        }
    }

    struct Actor: Decodable {
        let userID: String
        let email: String?
        let name: String?

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case email, name
        }
    }
}
