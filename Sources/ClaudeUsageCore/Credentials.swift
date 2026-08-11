import Foundation
import Security

public struct OAuthCredential: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date?

    public init(accessToken: String, refreshToken: String?, expiresAt: Date?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

public enum ClaudeCredentialImporter {
    public static func current() throws -> OAuthCredential {
        if let data = try? Keychain.read(service: "Claude Code-credentials"),
           let credential = try? parse(data) {
            return credential
        }

        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        guard let data = try? Data(contentsOf: url) else {
            throw UsageError.noClaudeLogin
        }
        return try parse(data)
    }

    public static func parse(_ data: Data) throws -> OAuthCredential {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.malformedCredentials
        }

        let container = (root["claudeAiOauth"] as? [String: Any])
            ?? (root["oauthAccount"] as? [String: Any])
            ?? root
        guard let accessToken = string(container, "accessToken", "access_token"), !accessToken.isEmpty else {
            throw UsageError.malformedCredentials
        }

        let expiresAt: Date?
        if let raw = number(container, "expiresAt", "expires_at") {
            let seconds = raw > 10_000_000_000 ? raw / 1000 : raw
            expiresAt = Date(timeIntervalSince1970: seconds)
        } else {
            expiresAt = nil
        }

        return OAuthCredential(
            accessToken: accessToken,
            refreshToken: string(container, "refreshToken", "refresh_token"),
            expiresAt: expiresAt
        )
    }

    private static func string(_ object: [String: Any], _ keys: String...) -> String? {
        keys.lazy.compactMap { object[$0] as? String }.first
    }

    private static func number(_ object: [String: Any], _ keys: String...) -> Double? {
        for key in keys {
            if let value = object[key] as? NSNumber { return value.doubleValue }
            if let value = object[key] as? String, let number = Double(value) { return number }
        }
        return nil
    }
}

public enum SecretStore {
    private static let prefix = "com.local.ClaudeUsage.account."

    public static func save<T: Encodable>(_ secret: T, for id: UUID) throws {
        let data = try JSONEncoder().encode(secret)
        try Keychain.write(data, service: prefix + id.uuidString)
    }

    public static func read<T: Decodable>(_ type: T.Type, for id: UUID) throws -> T {
        guard let data = try Keychain.read(service: prefix + id.uuidString) else {
            throw UsageError.missingSecret
        }
        return try JSONDecoder().decode(type, from: data)
    }

    public static func delete(for id: UUID) throws {
        try Keychain.delete(service: prefix + id.uuidString)
    }
}

enum Keychain {
    static func read(service: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return result as? Data
    }

    static func write(_ data: Data, service: String) throws {
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainError(status: updateStatus) }

        var insert = lookup
        insert[kSecValueData as String] = data
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    static func delete(service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
    }
}
