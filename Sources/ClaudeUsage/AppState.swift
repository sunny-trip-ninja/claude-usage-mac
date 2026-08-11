import AppKit
import ClaudeUsageCore
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    struct PendingOAuth: Equatable {
        let accountName: String
        let authorization: OAuthAuthorization
    }

    @Published private(set) var accounts: [Account] = []
    @Published private(set) var snapshots: [UUID: AccountSnapshot] = [:]
    @Published private(set) var errors: [UUID: String] = [:]
    @Published private(set) var refreshing: Set<UUID> = []
    @Published var globalError: String?
    @Published private(set) var pendingOAuth: PendingOAuth?

    private let defaultsKey = "accounts.v1"
    private let client = AnthropicClient()

    init(loadPersistedAccounts: Bool = true, startBackgroundTasks: Bool = true) {
        if startBackgroundTasks {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
        if loadPersistedAccounts { loadAccounts() }
        if startBackgroundTasks {
            Task { await refreshAll() }
            Task { await refreshLoop() }
        }
    }

    var menuPercent: Int? {
        let values = snapshots.values.compactMap { snapshot -> Double? in
            guard case .plan(let usage) = snapshot else { return nil }
            return usage.highestUtilization
        }
        guard let maximum = values.max() else { return nil }
        return Int(maximum.rounded())
    }

    func importCurrentClaudeLogin(name: String) async -> Bool {
        do {
            let credential = try ClaudeCredentialImporter.current()
            let account = Account(name: name.trimmingCharacters(in: .whitespacesAndNewlines), kind: .claudePlan)
            try SecretStore.save(credential, for: account.id)
            accounts.append(account)
            persistAccounts()
            await refresh(account)
            return true
        } catch {
            globalError = error.localizedDescription
            return false
        }
    }

    func beginOAuthLogin(name: String, useSSO: Bool) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            globalError = "Enter a name for this account."
            return false
        }
        do {
            let authorization = try OAuthAuthorization.make(useSSO: useSSO)
            pendingOAuth = PendingOAuth(accountName: cleanName, authorization: authorization)
            guard NSWorkspace.shared.open(authorization.authorizationURL) else {
                pendingOAuth = nil
                globalError = "The browser could not be opened."
                return false
            }
            return true
        } catch {
            globalError = error.localizedDescription
            return false
        }
    }

    func completeOAuthLogin(code: String) async -> Bool {
        guard let pendingOAuth else {
            globalError = "This login attempt expired. Start browser login again."
            return false
        }
        do {
            let credential = try await client.exchangeOAuthCode(
                code,
                authorization: pendingOAuth.authorization
            )
            let account = Account(name: pendingOAuth.accountName, kind: .claudePlan)
            try SecretStore.save(credential, for: account.id)
            accounts.append(account)
            persistAccounts()
            self.pendingOAuth = nil
            await refresh(account)
            return true
        } catch {
            globalError = error.localizedDescription
            return false
        }
    }

    func cancelOAuthLogin() { pendingOAuth = nil }

    func clearGlobalError() { globalError = nil }

    func addEnterprise(name: String, apiKey: String) async -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanKey.isEmpty else {
            globalError = "Enter an account name and Analytics API key."
            return false
        }
        let account = Account(name: cleanName, kind: .enterpriseAnalytics)
        do {
            try SecretStore.save(AnalyticsCredential(apiKey: cleanKey), for: account.id)
            accounts.append(account)
            persistAccounts()
            await refresh(account)
            return true
        } catch {
            globalError = error.localizedDescription
            return false
        }
    }

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for account in accounts {
                group.addTask { await self.refresh(account) }
            }
        }
    }

    func refresh(_ account: Account) async {
        guard !refreshing.contains(account.id) else { return }
        refreshing.insert(account.id)
        defer { refreshing.remove(account.id) }
        do {
            switch account.kind {
            case .claudePlan:
                let credential = try SecretStore.read(OAuthCredential.self, for: account.id)
                let result = try await client.fetchPlanUsage(using: credential)
                if result.credential != credential {
                    try SecretStore.save(result.credential, for: account.id)
                }
                snapshots[account.id] = .plan(result.usage)
            case .enterpriseAnalytics:
                let credential = try SecretStore.read(AnalyticsCredential.self, for: account.id)
                snapshots[account.id] = .team(try await client.fetchTeamUsage(apiKey: credential.apiKey))
            }
            errors[account.id] = nil
        } catch {
            errors[account.id] = error.localizedDescription
        }
    }

    func remove(_ account: Account) {
        try? SecretStore.delete(for: account.id)
        accounts.removeAll { $0.id == account.id }
        snapshots[account.id] = nil
        errors[account.id] = nil
        persistAccounts()
    }

    func quit() { NSApp.terminate(nil) }

    private func refreshLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(300))
            await refreshAll()
        }
    }

    private func loadAccounts() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([Account].self, from: data) else { return }
        accounts = decoded
    }

    private func persistAccounts() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
