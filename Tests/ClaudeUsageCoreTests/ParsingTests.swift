import Foundation
import Testing
@testable import ClaudeUsageCore

@Test func parsesCurrentClaudeCredentialShape() throws {
    let data = Data(#"{"claudeAiOauth":{"accessToken":"access","refreshToken":"refresh","expiresAt":2000000000000}}"#.utf8)
    let credential = try ClaudeCredentialImporter.parse(data)
    #expect(credential.accessToken == "access")
    #expect(credential.refreshToken == "refresh")
    #expect(credential.expiresAt == Date(timeIntervalSince1970: 2_000_000_000))
}

@Test func parsesSnakeCaseCredentialShape() throws {
    let data = Data(#"{"access_token":"access","refresh_token":"refresh","expires_at":2000000000}"#.utf8)
    let credential = try ClaudeCredentialImporter.parse(data)
    #expect(credential.accessToken == "access")
    #expect(credential.refreshToken == "refresh")
    #expect(credential.expiresAt == Date(timeIntervalSince1970: 2_000_000_000))
}

@Test func clampsLimitUtilization() {
    #expect(LimitWindow(utilization: 120, resetsAt: nil).utilization == 100)
    #expect(LimitWindow(utilization: -4, resetsAt: nil).utilization == 0)
}

@Test func teamUsageTotalsMembers() {
    let usage = TeamUsage(members: [
        TeamMemberUsage(id: "1", name: "A", email: nil, totalTokens: 1_250, requests: 2),
        TeamMemberUsage(id: "2", name: "B", email: nil, totalTokens: 3_750, requests: 4),
    ], refreshedAt: nil)
    #expect(usage.totalTokens == 5_000)
}

@Test func oauthAuthorizationUsesPKCEAndManualCallback() throws {
    let authorization = try OAuthAuthorization.make(useSSO: true)
    let components = try #require(URLComponents(url: authorization.authorizationURL, resolvingAgainstBaseURL: false))
    let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

    #expect(components.host == "claude.com")
    #expect(values["response_type"] == "code")
    #expect(values["code_challenge_method"] == "S256")
    #expect(values["redirect_uri"] == "https://platform.claude.com/oauth/code/callback")
    #expect(values["login_method"] == "sso")
    #expect(values["state"] == authorization.state)
    #expect(authorization.codeVerifier.count >= 43)
}

@Test func oauthPasteRequiresMatchingState() throws {
    let authorization = try OAuthAuthorization.make()
    #expect(try authorization.authorizationCode(from: "the-code#\(authorization.state)") == "the-code")
    #expect(throws: UsageError.self) {
        try authorization.authorizationCode(from: "the-code#wrong-state")
    }
    #expect(throws: UsageError.self) {
        try authorization.authorizationCode(from: "only-the-code")
    }
}
