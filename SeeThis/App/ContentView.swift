import AppKit
import SwiftUI

enum SettingsSection: String, Hashable {
    case general
    case models
    case lenses
    #if DEBUG
    case developer
    #endif

    static let productSections: [SettingsSection] = [.general, .models, .lenses]

    var title: String {
        switch self {
        case .general: "General"
        case .models: "Models"
        case .lenses: "Lenses"
        #if DEBUG
        case .developer: "Developer"
        #endif
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .models: "cpu"
        case .lenses: "text.magnifyingglass"
        #if DEBUG
        case .developer: "wrench.and.screwdriver"
        #endif
        }
    }

    var shortcutDescription: String {
        self == .general
            ? "Press \(KeyboardShortcut.commandD.display) in any app. Selected text is captured automatically."
            : ""
    }

    var accessibilityDescription: String {
        self == .general
            ? "Allow \(AppIdentity.displayName) to read selected text from the frontmost app."
            : ""
    }
}

struct ContentView: View {
    @ObservedObject var diagnostics: HostContextDiagnostics
    @ObservedObject var shortcutStore: ShortcutStore
    @ObservedObject var firstRunGuide: FirstRunGuideState
    @ObservedObject var translateSettings: TranslateSettingsStore
    @State private var selectedSection: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                ForEach(SettingsSection.productSections, id: \.self) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
                #if DEBUG
                Divider()
                Label(SettingsSection.developer.title, systemImage: SettingsSection.developer.systemImage)
                    .tag(SettingsSection.developer)
                #endif
            }
            .navigationTitle("Settings")
        } detail: {
            detail
        }
        .frame(minWidth: 720, minHeight: 460)
        .onAppear {
            diagnostics.refreshAccessibilityPermission()
            applyPendingSettingsSection()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            diagnostics.refreshAccessibilityPermission()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .seeThisSettingsSectionRequested
            )
        ) { notification in
            guard let section = notification.object as? SettingsSection else { return }
            selectedSection = section
        }
    }

    private func applyPendingSettingsSection() {
        if let requestedSection = SettingsNavigation.consumeRequestedSection() {
            selectedSection = requestedSection
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selectedSection {
        case .general:
            GeneralSettingsView(
                diagnostics: diagnostics,
                shortcutStore: shortcutStore,
                firstRunGuide: firstRunGuide,
                onOpenModels: { selectedSection = .models }
            )
        case .models:
            OllamaSettingsView(diagnostics: diagnostics, store: diagnostics.lensStore)
        case .lenses:
            LensManagementView(
                store: diagnostics.lensStore,
                translateSettings: translateSettings,
                onLensesSaved: diagnostics.refreshVisibleLenses
            )
        #if DEBUG
        case .developer:
            DeveloperDiagnosticsView(diagnostics: diagnostics)
        #endif
        }
    }
}

#Preview {
    ContentView(
        diagnostics: HostContextDiagnostics(),
        shortcutStore: ShortcutStore(),
        firstRunGuide: FirstRunGuideState(),
        translateSettings: TranslateSettingsStore()
    )
}
