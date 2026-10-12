import SwiftUI

private func shortcutFailureMessage(_ failure: ShortcutStore.UpdateFailure) -> String {
    switch failure {
    case .invalidCombination:
        return "Include at least one of ⌘, ⌃, or ⌥."
    case .systemConflict:
        return "That shortcut is already taken by macOS or another app."
    case .sequoiaOptionShiftBug:
        return "Option+Shift shortcuts don't work on macOS 15.0 or 15.1. Add ⌘ or ⌃, or update macOS."
    }
}

private func shortcutWarningMessage(_ warning: ShortcutStore.ConflictWarning) -> String {
    switch warning.source {
    case .system:
        return "\(warning.owner) also uses this shortcut."
    case .mainMenu:
        return "The menu command \(warning.owner) uses this shortcut."
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var diagnostics: HostContextDiagnostics
    @ObservedObject var shortcutStore: ShortcutStore
    @ObservedObject var firstRunGuide: FirstRunGuideState
    let onOpenModels: () -> Void

    var body: some View {
        SettingsPage {
            if firstRunGuide.isPresented {
                FirstRunGuideView(
                    diagnostics: diagnostics,
                    shortcutStore: shortcutStore,
                    firstRunGuide: firstRunGuide,
                    onOpenModels: onOpenModels
                )
            } else {
                Text("Accessibility permission")
                    .font(.headline)
                HStack(spacing: 6) {
                    Image(systemName: diagnostics.isAccessibilityTrusted
                          ? "checkmark.circle.fill"
                          : "exclamationmark.triangle.fill")
                        .foregroundStyle(diagnostics.isAccessibilityTrusted ? .green : .orange)
                    Text(diagnostics.isAccessibilityTrusted ? "Granted" : "Not granted")
                }
                Text("Used to read the text you select. The app never captures your screen.")
                    .foregroundStyle(.secondary)
                if !diagnostics.isAccessibilityTrusted {
                    Button("Grant Accessibility permission…") {
                        diagnostics.requestAccessibilityPermission()
                    }
                    .hoverHighlight()
                }

                Divider()

                Text("Trigger Shortcut")
                    .font(.headline)
                Text("Trigger the overlay while text is selected in the app you're reading.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ShortcutRecorderField(
                        current: shortcutStore.currentShortcut,
                        onCommit: { shortcutStore.attemptUpdate(to: $0) },
                        onInvalid: { shortcutStore.reportInvalidAttempt() }
                    )
                    Button("Reset to default") {
                        shortcutStore.resetToDefault()
                    }
                    .hoverHighlight()
                    .disabled(shortcutStore.currentShortcut == .commandD)
                }
                if let failure = shortcutStore.lastFailure {
                    Text(shortcutFailureMessage(failure))
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if !shortcutStore.lastWarning.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(shortcutStore.lastWarning.indices, id: \.self) { index in
                            let warning = shortcutStore.lastWarning[index]
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(shortcutWarningMessage(warning))
                            }
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Press")
                    Keycap("esc")
                    Text("to dismiss the overlay.")
                }
                .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 8) {
                    Text("Context file")
                        .font(.headline)
                    BetaBadge()
                }
                if diagnostics.readingSession.displayName == nil {
                    Text("Give SeeThis more to read from.")
                        .foregroundStyle(.secondary)
                    Text("1. Select text in an app and press your shortcut.\n2. Drag a PDF, TXT, or Markdown file onto the overlay.")
                        .foregroundStyle(.secondary)
                    Text(diagnostics.readingSession.statusDescription)
                        .foregroundStyle(.secondary)
                } else {
                    Text(diagnostics.readingSession.statusDescription)
                        .foregroundStyle(.secondary)
                    Text("Used only in the app you dropped it in. Detach it before switching to a different document. Cleared when you quit.")
                        .foregroundStyle(.secondary)
                    Button("Detach") {
                        diagnostics.clearReadingSession()
                    }
                    .hoverHighlight()
                }
                Text("The file text is sent only to your Ollama model. It leaves this Mac only if that is a cloud model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SettingsDisclosure("Advanced") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Text sent per request")
                        Text("Range: 5,000 to 100,000 characters.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Stepper(
                            value: Binding(
                                get: { diagnostics.contextCharacterLimit },
                                set: { diagnostics.contextCharacterLimit = $0 }
                            ),
                            in: ReadingSession.minimumFullContextCharacterLimit...ReadingSession.maximumFullContextCharacterLimit,
                            step: 5_000
                        ) {
                            Text("\(diagnostics.contextCharacterLimit) characters")
                        }
                        .frame(maxWidth: 360, alignment: .leading)
                    }
                }

                Divider()

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tutorial")
                            .font(.headline)
                        Text("Review setup and try the shortcut with demo text.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Replay Tutorial…") {
                        firstRunGuide.present(.tutorial)
                    }
                    .hoverHighlight()
                }
            }
        }
    }
}
