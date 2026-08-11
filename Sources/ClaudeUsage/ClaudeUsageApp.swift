import SwiftUI

@main
struct ClaudeUsageApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            UsagePopover()
                .environmentObject(state)
        } label: {
            if let percent = state.menuPercent {
                Label("Claude \(percent)%", systemImage: "chart.bar.fill")
            } else {
                Image(systemName: "chart.bar.fill")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
