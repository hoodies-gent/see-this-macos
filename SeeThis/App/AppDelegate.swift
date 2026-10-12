import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let shortcutStore = ShortcutStore()
    let translateSettings: TranslateSettingsStore
    let diagnostics: HostContextDiagnostics
    private let hotKeyMonitor = GlobalHotKeyMonitor()
    #if DEBUG
    private let capabilityProbeHotKeyMonitor = CapabilityProbeHotKeyMonitor()
    #endif
    private var windowCloseObserver: NSObjectProtocol?

    override init() {
        let lensStore = LensStore()
        let settings = TranslateSettingsStore(lensStore: lensStore)
        translateSettings = settings
        diagnostics = HostContextDiagnostics(
            lensStore: lensStore,
            translateSettings: settings
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !RuntimeEnvironment.isRunningUnitTests else { return }
        let diagnostics = diagnostics
        let hotKeyMonitor = hotKeyMonitor
        var didStart = false
        shortcutStore.bind { shortcut in
            if didStart {
                return hotKeyMonitor.update(shortcut: shortcut)
            }
            didStart = hotKeyMonitor.start(shortcut: shortcut) {
                diagnostics.capture()
            }
            return didStart
        }
        #if DEBUG
        capabilityProbeHotKeyMonitor.start {
            diagnostics.probeFrontmostHostCapabilities()
        }
        #endif
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let closingWindow = notification.object as? NSWindow else { return }
            Task { @MainActor in
                self?.reevaluateActivationPolicy(closingWindow: closingWindow)
            }
        }
    }

    private func reevaluateActivationPolicy(closingWindow: NSWindow) {
        let hasContentWindow = NSApp.windows.contains { window in
            window !== closingWindow && window.isVisible && window.canBecomeMain
        }
        if !hasContentWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
