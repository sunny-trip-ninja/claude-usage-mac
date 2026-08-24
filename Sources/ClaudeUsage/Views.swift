import AppKit
import ClaudeUsageCore
import SwiftUI

private struct DocumentationScreenshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var documentationScreenshot: Bool {
        get { self[DocumentationScreenshotKey.self] }
        set { self[DocumentationScreenshotKey.self] = newValue }
    }
}

enum AddMode: Equatable {
    case chooser
    case oauth
    case cliImport
    case enterprise
}

struct UsagePopover: View {
    @EnvironmentObject private var state: AppState
    @State private var addMode: AddMode?

    init(initialAddMode: AddMode? = nil) {
        _addMode = State(initialValue: initialAddMode)
    }

    private var usesCompactLayout: Bool {
        state.compactMode && addMode == nil && state.pendingOAuth == nil && !state.accounts.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let error = state.globalError {
                errorBanner(error)
                Divider()
            }
            content
            Divider()
            footer
        }
        .frame(width: usesCompactLayout ? 260 : 410)
    }

    @ViewBuilder
    private var content: some View {
        if state.pendingOAuth != nil {
            OAuthCompletionForm {
                addMode = nil
            } onCancel: {
                state.cancelOAuthLogin()
                addMode = nil
            }
        } else if let addMode {
            inlineAddView(addMode)
        } else if state.accounts.isEmpty {
            emptyState
        } else {
            accountList
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Usage").font(.headline)
                if !usesCompactLayout {
                    Text("Personal limits and team activity").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await state.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding(.horizontal, usesCompactLayout ? 12 : 14)
        .padding(.vertical, usesCompactLayout ? 7 : 14)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button { state.clearGlobalError() } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.08))
    }

    @ViewBuilder
    private var accountList: some View {
        if usesCompactLayout {
            ScrollView {
                compactAccountRows
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .frame(height: min(CGFloat(state.accounts.count * 26 + 6), 162))
        } else {
            Group {
                if state.accounts.count == 1 {
                    accountCards
                } else {
                    ScrollView {
                        accountCards
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .frame(height: 160)
        }
    }

    private var compactAccountRows: some View {
        VStack(spacing: 0) {
            ForEach(state.accounts) { account in
                CompactAccountRow(account: account)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    private var accountCards: some View {
        VStack(spacing: 12) {
            ForEach(state.accounts) { account in
                AccountCard(account: account)
            }
        }
        .padding(14)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 30)).foregroundStyle(.secondary)
            Text("Add an account to get started").font(.headline)
            Text("Sign in through the browser for independent personal or work accounts.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add account") { addMode = .chooser }
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
    }

    @ViewBuilder
    private func inlineAddView(_ mode: AddMode) -> some View {
        switch mode {
        case .chooser:
            AddChooser { addMode = $0 } onCancel: { addMode = nil }
        case .oauth:
            OAuthStartForm(onCancel: { addMode = .chooser })
        case .cliImport:
            CLIImportForm(onComplete: { addMode = nil }, onCancel: { addMode = .chooser })
        case .enterprise:
            EnterpriseForm(onComplete: { addMode = nil }, onCancel: { addMode = .chooser })
        }
    }

    private var footer: some View {
        ZStack {
            HStack {
                if addMode == nil && state.pendingOAuth == nil && !state.accounts.isEmpty {
                    Button { addMode = .chooser } label: {
                        if usesCompactLayout {
                            Image(systemName: "plus")
                        } else {
                            Label("Add account", systemImage: "plus")
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Add account")
                    .accessibilityLabel("Add account")
                }
                Spacer()
                Button("Quit") { state.quit() }.buttonStyle(.plain).foregroundStyle(.secondary)
            }

            if addMode == nil && state.pendingOAuth == nil {
                HStack(spacing: 5) {
                    Text("Compact")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Compact mode", isOn: $state.compactMode)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        .help("Compact mode")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, usesCompactLayout ? 7 : 9)
    }
}

private struct CompactAccountRow: View {
    @EnvironmentObject private var state: AppState
    let account: Account
    @State private var confirmingRemoval = false

    var body: some View {
        HStack(spacing: 8) {
            Text(account.name)
                .font(.system(size: 13))
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if state.refreshing.contains(account.id) {
                ProgressView().controlSize(.mini)
            }

            summary
                .frame(width: 136, alignment: .trailing)

            if state.errors[account.id] != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(state.errors[account.id] ?? "Refresh failed")
            }

            Button { confirmingRemoval = true } label: {
                Image(systemName: "trash").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove account")
        }
        .frame(height: 26)
        .alert("Remove \(account.name)?", isPresented: $confirmingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { state.remove(account) }
        } message: {
            Text("This removes the account and its saved credential.")
        }
    }

    @ViewBuilder
    private var summary: some View {
        if let snapshot = state.snapshots[account.id] {
            switch snapshot {
            case .plan(let usage):
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    HStack(spacing: 4) {
                        metric("S", window: usage.fiveHour, now: context.date)
                        metric("W", window: usage.sevenDay, now: context.date)
                    }
                }
            case .team(let usage):
                Text("· \(usage.totalTokens.formatted(.number.notation(.compactName))) tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } else {
            if account.kind == .claudePlan {
                HStack(spacing: 4) {
                    metric("S", window: nil, now: .now)
                    metric("W", window: nil, now: .now)
                }
            } else {
                Text("— tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metric(_ label: String, window: LimitWindow?, now: Date) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.tertiary)
            Text(percent(window))
                .font(.caption)
                .foregroundStyle(.primary)
                .monospacedDigit()
                .frame(width: 25, alignment: .trailing)
            if let reset = window?.resetsAt {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text(compactDuration(until: reset, from: now))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text("—")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 66, alignment: .leading)
    }

    private func compactDuration(until reset: Date, from now: Date) -> String {
        let seconds = reset.timeIntervalSince(now)
        guard seconds > 0 else { return "now" }
        if seconds < 3_600 {
            return "\(max(1, Int(seconds / 60)))m"
        }
        if seconds < 86_400 {
            return "\(max(1, Int(seconds / 3_600)))h"
        }
        return "\(max(1, Int(seconds / 86_400)))d"
    }

    private func percent(_ window: LimitWindow?) -> String {
        guard let window else { return "—" }
        return "\(Int(window.utilization.rounded()))%"
    }
}

private struct AddChooser: View {
    let onSelect: (AddMode) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Add account").font(.headline)
                Spacer()
                Button("Cancel", action: onCancel).buttonStyle(.plain).foregroundStyle(.secondary)
            }
            AccountChoice(
                icon: "safari",
                title: "Sign in with browser",
                detail: "Personal, Team, Enterprise, or work SSO",
                recommended: true
            ) { onSelect(.oauth) }
            AccountChoice(
                icon: "terminal",
                title: "Import Claude CLI login",
                detail: "Copy the login currently active in Claude Code"
            ) { onSelect(.cliImport) }
            AccountChoice(
                icon: "building.2",
                title: "Enterprise analytics",
                detail: "Member leaderboard using a read-only API key"
            ) { onSelect(.enterprise) }
        }
        .padding(14)
    }
}

private struct AccountChoice: View {
    let icon: String
    let title: String
    let detail: String
    var recommended = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 22).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).fontWeight(.medium)
                        if recommended {
                            Text("Recommended").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct OAuthStartForm: View {
    @EnvironmentObject private var state: AppState
    let onCancel: () -> Void
    @State private var name = "Personal"
    @State private var useSSO = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in with Claude").font(.headline)
            Text("Claude opens in your browser. After approval, copy the complete authorization code shown there and return to this menu.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            DocumentationTextField("Account name", text: $name)
            DocumentationToggle("Use work SSO", isOn: $useSSO)
            HStack {
                Button("Back", action: onCancel)
                Spacer()
                Button("Open browser") {
                    _ = state.beginOAuthLogin(name: name, useSSO: useSSO)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
    }
}

private struct OAuthCompletionForm: View {
    @EnvironmentObject private var state: AppState
    let onComplete: () -> Void
    let onCancel: () -> Void
    @State private var code = ""
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Finish browser login", systemImage: "checkmark.shield")
                .font(.headline)
            if let pending = state.pendingOAuth {
                Text("Authorizing “\(pending.accountName)”. Paste the complete `code#state` value from Claude.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                DocumentationTextField("Paste authorization code", text: $code)
                HStack {
                    Button("Cancel", action: onCancel)
                    Button("Reopen browser") {
                        _ = NSWorkspace.shared.open(pending.authorization.authorizationURL)
                    }
                    Spacer()
                    Button("Connect") {
                        working = true
                        Task {
                            let success = await state.completeOAuthLogin(code: code)
                            working = false
                            if success { onComplete() }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(working || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(14)
    }
}

private struct CLIImportForm: View {
    @EnvironmentObject private var state: AppState
    let onComplete: () -> Void
    let onCancel: () -> Void
    @State private var name = "Personal"
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import Claude CLI login").font(.headline)
            Text("Imports whichever account is currently stored by Claude Code. Browser login is more reliable when aliases use separate config directories.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            DocumentationTextField("Account name", text: $name)
            HStack {
                Button("Back", action: onCancel)
                Spacer()
                Button("Import") {
                    working = true
                    Task {
                        let success = await state.importCurrentClaudeLogin(name: name)
                        working = false
                        if success { onComplete() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(working || name.isEmpty)
            }
        }
        .padding(14)
    }
}

private struct EnterpriseForm: View {
    @EnvironmentObject private var state: AppState
    let onComplete: () -> Void
    let onCancel: () -> Void
    @State private var name = "Work team"
    @State private var apiKey = ""
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Enterprise analytics").font(.headline)
            Text("Use a read-only `read:analytics` key from claude.ai → Organization settings → API. It stays in macOS Keychain.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            DocumentationTextField("Account name", text: $name)
            DocumentationTextField("Analytics API key", text: $apiKey, secure: true)
            HStack {
                Button("Back", action: onCancel)
                Spacer()
                Button("Add account") {
                    working = true
                    Task {
                        let success = await state.addEnterprise(name: name, apiKey: apiKey)
                        working = false
                        if success { onComplete() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(working || name.isEmpty || apiKey.isEmpty)
            }
        }
        .padding(14)
    }
}

private struct DocumentationTextField: View {
    @Environment(\.documentationScreenshot) private var isDocumentationScreenshot
    let title: String
    @Binding var text: String
    var secure: Bool

    init(_ title: String, text: Binding<String>, secure: Bool = false) {
        self.title = title
        _text = text
        self.secure = secure
    }

    var body: some View {
        if isDocumentationScreenshot {
            HStack {
                Text(text.isEmpty ? title : (secure ? String(repeating: "•", count: 12) : text))
                    .foregroundStyle(text.isEmpty ? .tertiary : .primary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(.background, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 1))
        } else if secure {
            SecureField(title, text: $text)
        } else {
            TextField(title, text: $text)
        }
    }
}

private struct DocumentationToggle: View {
    @Environment(\.documentationScreenshot) private var isDocumentationScreenshot
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        if isDocumentationScreenshot {
            HStack {
                Text(title)
                Spacer()
                Capsule()
                    .fill(isOn ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 34, height: 20)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle().fill(.white).padding(2)
                    }
            }
        } else {
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

private struct AccountCard: View {
    @EnvironmentObject private var state: AppState
    let account: Account
    @State private var confirmingRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: account.kind == .claudePlan ? "person.crop.circle" : "building.2")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.name).font(.headline)
                    Text(account.kind == .claudePlan ? "Claude plan" : "Enterprise · last 7 days")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if state.refreshing.contains(account.id) {
                    ProgressView().controlSize(.small)
                }
                Button { Task { await state.refresh(account) } } label: {
                    Image(systemName: "arrow.clockwise").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh")
                Button { confirmingRemoval.toggle() } label: {
                    Image(systemName: "trash").foregroundStyle(confirmingRemoval ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .help("Remove account")
            }

            if confirmingRemoval {
                HStack {
                    Text("Remove this account and its saved credential?").font(.caption)
                    Spacer()
                    Button("Cancel") { confirmingRemoval = false }.controlSize(.small)
                    Button("Remove", role: .destructive) { state.remove(account) }.controlSize(.small)
                }
                .padding(8)
                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            if let error = state.errors[account.id] {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let snapshot = state.snapshots[account.id] {
                switch snapshot {
                case .plan(let usage): PlanUsageView(usage: usage)
                case .team(let usage): TeamUsageView(usage: usage)
                }
            } else {
                Text("Waiting for first refresh…").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct PlanUsageView: View {
    let usage: PlanUsage

    var body: some View {
        VStack(spacing: 9) {
            if let window = usage.fiveHour {
                UsageBar(title: "Session", window: window, showsResetTime: true)
            }
            if let window = usage.sevenDay { UsageBar(title: "Weekly", window: window) }
            if let window = usage.sevenDaySonnet { UsageBar(title: "Sonnet weekly", window: window) }
            if let window = usage.sevenDayOpus { UsageBar(title: "Opus weekly", window: window) }
            if usage.fiveHour == nil && usage.sevenDay == nil {
                Text("No active limit windows were returned.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct UsageBar: View {
    let title: String
    let window: LimitWindow
    var showsResetTime = false

    var color: Color {
        if window.utilization >= 90 { return .red }
        if window.utilization >= 70 { return .orange }
        return .accentColor
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text(title).font(.caption).fontWeight(.medium)
                Spacer(minLength: 8)
                if let reset = window.resetsAt {
                    resetLabel(reset)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("\(Int(window.utilization.rounded()))% used").font(.caption).monospacedDigit()
            }
            ProgressView(value: window.utilization, total: 100).tint(color)
        }
    }

    private func resetLabel(_ reset: Date) -> Text {
        if showsResetTime {
            Text("Resets at \(reset, format: .dateTime.hour().minute()) · \(reset, format: .relative(presentation: .named))")
        } else {
            Text("Resets \(reset, format: .relative(presentation: .named))")
        }
    }
}

private struct TeamUsageView: View {
    let usage: TeamUsage

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text("\(usage.members.count) active members").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(usage.totalTokens.formatted(.number.notation(.compactName)) + " tokens")
                    .font(.caption).fontWeight(.medium)
            }
            ForEach(Array(usage.members.prefix(8).enumerated()), id: \.element.id) { index, member in
                HStack(spacing: 8) {
                    Text("\(index + 1)").font(.caption2).foregroundStyle(.secondary).frame(width: 14)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(member.name).font(.caption).lineLimit(1)
                        if let email = member.email, email != member.name {
                            Text(email).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    Text(member.totalTokens.formatted(.number.notation(.compactName)))
                        .font(.caption).monospacedDigit()
                }
            }
            if usage.members.count > 8 {
                Text("+ \(usage.members.count - 8) more members").font(.caption2).foregroundStyle(.secondary)
            }
            if let refreshedAt = usage.refreshedAt {
                HStack {
                    Spacer()
                    Text("Anthropic data refreshed \(refreshedAt, format: .relative(presentation: .named))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
