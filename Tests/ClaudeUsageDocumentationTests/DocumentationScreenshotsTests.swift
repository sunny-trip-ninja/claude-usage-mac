import AppKit
import SwiftUI
import XCTest
@testable import ClaudeUsage

final class DocumentationScreenshotsTests: XCTestCase {
    @MainActor
    func testCompactModePersists() throws {
        let suiteName = "ClaudeUsageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = AppState(
            loadPersistedAccounts: false,
            startBackgroundTasks: false,
            defaults: defaults
        )
        XCTAssertFalse(state.compactMode)

        state.compactMode = true

        let restoredState = AppState(
            loadPersistedAccounts: false,
            startBackgroundTasks: false,
            defaults: defaults
        )
        XCTAssertTrue(restoredState.compactMode)
    }

    @MainActor
    func testGenerateDocumentationScreenshots() throws {
        guard let destination = ProcessInfo.processInfo.environment["DOC_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set DOC_SCREENSHOT_DIR to generate README screenshots.")
        }

        let directory = URL(fileURLWithPath: destination, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let state = AppState(loadPersistedAccounts: false, startBackgroundTasks: false)

        try render(
            UsagePopover().environmentObject(state),
            to: directory.appendingPathComponent("01-empty-state.png")
        )
        try render(
            UsagePopover(initialAddMode: .chooser).environmentObject(state),
            to: directory.appendingPathComponent("02-account-options.png")
        )
        try render(
            UsagePopover(initialAddMode: .oauth).environmentObject(state),
            to: directory.appendingPathComponent("03-browser-login.png")
        )
        try render(
            UsagePopover(initialAddMode: .enterprise).environmentObject(state),
            to: directory.appendingPathComponent("04-enterprise-analytics.png")
        )
    }

    @MainActor
    private func render<V: View>(_ view: V, to url: URL) throws {
        let content = view
            .fixedSize(horizontal: true, vertical: true)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.documentationScreenshot, true)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Could not render \(url.lastPathComponent)")
            return
        }
        try png.write(to: url, options: .atomic)
    }
}
