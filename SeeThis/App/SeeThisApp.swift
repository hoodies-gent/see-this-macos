import SwiftUI

@main
struct SeeThisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var firstRunGuide = FirstRunGuideState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                diagnostics: appDelegate.diagnostics,
                lensStore: appDelegate.diagnostics.lensStore
            )
        } label: {
            FirstRunLaunchLabel(firstRunGuide: firstRunGuide)
        }
        Window("Settings", id: Self.settingsWindowID) {
            ContentView(
                diagnostics: appDelegate.diagnostics,
                shortcutStore: appDelegate.shortcutStore,
                firstRunGuide: firstRunGuide,
                translateSettings: appDelegate.translateSettings
            )
        }
        .defaultLaunchBehavior(.suppressed)
    }

    static let settingsWindowID = "settings"
}

private struct FirstRunLaunchLabel: View {
    @ObservedObject var firstRunGuide: FirstRunGuideState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image("MenuBarIcon")
            .renderingMode(.template)
            .accessibilityLabel(AppIdentity.displayName)
            .onReceive(
                NotificationCenter.default.publisher(for: .seeThisSettingsWindowRequested)
            ) { _ in
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: SeeThisApp.settingsWindowID)
            }
            .task {
                guard !RuntimeEnvironment.isRunningUnitTests else { return }
                guard !firstRunGuide.hasCompleted, !firstRunGuide.isPresented else { return }
                firstRunGuide.present(.gettingStarted)
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                await Task.yield()
                openWindow(id: SeeThisApp.settingsWindowID)
            }
    }
}

private struct MenuBarContent: View {
    @ObservedObject var diagnostics: HostContextDiagnostics
    @ObservedObject var lensStore: LensStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let status = ollamaStatus {
                Label {
                    Text(status.text)
                } icon: {
                    Image(systemName: "circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(status.color)
                }
                if case .available(let models) = diagnostics.ollamaConnectionStatus {
                    Picker(
                        "Model: \(lensStore.selectedOllamaModel)",
                        selection: Binding(
                            get: { lensStore.selectedOllamaModel },
                            set: { lensStore.setSelectedOllamaModel($0) }
                        )
                    ) {
                        ForEach(models.filter { $0.isEmbeddingOnly != true }) { model in
                            Text(model.id).tag(model.id)
                        }
                    }
                }
                if let action = ollamaAction {
                    Button(action.title, action: action.perform)
                }
                Divider()
            }
            Button("Settings…") {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: SeeThisApp.settingsWindowID)
            }
            .keyboardShortcut(",", modifiers: .command)
            Divider()
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .onAppear {
            diagnostics.checkOllamaConnection()
        }
    }

    private struct OllamaStatus {
        let text: String
        let color: Color
    }

    private struct OllamaAction {
        let title: String
        let perform: () -> Void
    }

    private var ollamaAction: OllamaAction? {
        switch diagnostics.ollamaConnectionStatus {
        case .notRunning:
            return OllamaAction(title: "Start Ollama") { diagnostics.startOllama() }
        case .noModels, .available:
            return OllamaAction(title: "Stop Ollama") { diagnostics.stopOllama() }
        case .notInstalled, .notChecked, .checking, .starting:
            return nil
        }
    }

    private var ollamaStatus: OllamaStatus? {
        switch diagnostics.ollamaConnectionStatus {
        case .notInstalled:
            return nil
        case .notChecked, .checking:
            return OllamaStatus(text: "Ollama: Checking…", color: .gray)
        case .starting:
            return OllamaStatus(text: "Ollama: Starting…", color: .gray)
        case .notRunning:
            return OllamaStatus(text: "Ollama: Inactive", color: .gray)
        case .noModels, .available:
            return OllamaStatus(text: "Ollama: Active", color: .green)
        }
    }
}
