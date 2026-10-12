import AppKit
import SwiftUI
import Testing
@testable import SeeThis

struct HostContextDiagnosticsTests {

    @Test @MainActor func accessibilityPermissionRefreshReadsTheLatestSystemState() {
        var isTrusted = false
        let diagnostics = HostContextDiagnostics(
            lensStore: LensStore(),
            translateSettings: TranslateSettingsStore(),
            accessibilityTrustProvider: { isTrusted }
        )

        #expect(!diagnostics.isAccessibilityTrusted)

        isTrusted = true
        diagnostics.refreshAccessibilityPermission()

        #expect(diagnostics.isAccessibilityTrusted)
    }

    @Test @MainActor func settingsRefreshAccessibilityPermissionWhenApplicationBecomesActive() async {
        let suiteName = "HostContextDiagnosticsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var isTrusted = false
        let translateSettings = TranslateSettingsStore(defaults: defaults)
        let diagnostics = HostContextDiagnostics(
            lensStore: LensStore(defaults: defaults),
            translateSettings: translateSettings,
            accessibilityTrustProvider: { isTrusted }
        )
        let contentView = ContentView(
            diagnostics: diagnostics,
            shortcutStore: ShortcutStore(defaults: defaults),
            firstRunGuide: FirstRunGuideState(defaults: defaults),
            translateSettings: translateSettings
        )
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 720, height: 460)
        hostingView.layoutSubtreeIfNeeded()
        await Task.yield()

        isTrusted = true
        NotificationCenter.default.post(
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        await Task.yield()

        #expect(diagnostics.isAccessibilityTrusted)
    }
}
