import Foundation
import SwiftUI

#if DEBUG
enum MarkdownShowcase {
    static let answer = """
    # Markdown showcase

    ## Inline formatting

    Plain text with **bold**, *italic*, ***both***, `inline code`, ~~strikethrough~~, and [safe link](https://example.invalid).

    This is a deliberately long body paragraph that wraps across the overlay width.
    Second line of the same paragraph keeps ordinary prose readable after wrapping.

    > Quoted context stays visually separate.

    ## Lists

    - First item
      - Nested item
    - Second item

    1. First ordered item
    2. Second ordered item

    ## Python

    ```python
    def explain(value: str) -> str:
        return f"Explanation: {value}"
    ```

    ## Safety probes

    | Format | Probe |
    | --- | --- |
    | Task | - [x] complete |

    <strong>HTML must not execute</strong>

    <u>HTML underline must stay literal</u>

    ![Remote image](https://example.invalid/image.png)
    """
}
#endif

#if DEBUG
private enum SimulatedOllamaStatus: String, CaseIterable, Identifiable {
    case notChecked, checking, notInstalled, notRunningApp, notRunningCLI, starting, noModels, available
    var id: String { rawValue }

    var label: String {
        switch self {
        case .notChecked: "notChecked"
        case .checking: "checking"
        case .notInstalled: "notInstalled"
        case .notRunningApp: "notRunning · App"
        case .notRunningCLI: "notRunning · CLI"
        case .starting: "starting"
        case .noModels: "noModels"
        case .available: "available (gemma3:4b, llama3.2:3b)"
        }
    }

    var status: OllamaConnectionStatus {
        switch self {
        case .notChecked: .notChecked
        case .checking: .checking
        case .notInstalled: .notInstalled
        case .notRunningApp: .notRunning(.app(URL(fileURLWithPath: "/Applications/Ollama.app")))
        case .notRunningCLI: .notRunning(.cli(URL(fileURLWithPath: "/opt/homebrew/bin/ollama")))
        case .starting: .starting
        case .noModels: .noModels
        case .available: .available([
            OllamaInstalledModel(id: "gemma3:4b", sizeBytes: 3_500_000_000),
            OllamaInstalledModel(id: "llama3.2:3b", sizeBytes: 2_000_000_000)
        ])
        }
    }
}

struct DeveloperDiagnosticsView: View {
    @ObservedObject var diagnostics: HostContextDiagnostics
    @State private var simulatedOllamaStatus: SimulatedOllamaStatus = .notChecked

    var body: some View {
        SettingsPage {
            Text("Simulate Ollama status")
                .font(.headline)
            Text("Force the Models panel into any state. Buttons still perform real work (Start actually spawns, Download actually opens the browser).")
                .foregroundStyle(.secondary)
            Picker("Force status", selection: $simulatedOllamaStatus) {
                ForEach(SimulatedOllamaStatus.allCases) { simulated in
                    Text(simulated.label).tag(simulated)
                }
            }
            .onChange(of: simulatedOllamaStatus) { _, new in
                diagnostics.debugSetOllamaStatus(new.status)
            }
            Button("Reset to real detection") {
                if diagnostics.lensStore.selectedOllamaModel.hasPrefix("debug:") {
                    diagnostics.lensStore.setSelectedOllamaModel(OllamaProvider.defaultModelName)
                }
                diagnostics.checkOllamaConnection()
            }
            .hoverHighlight()

            Divider()
            Text("Last result")
                .font(.headline)
            Text(diagnostics.lastResult)
                .textSelection(.enabled)
            Divider()
            Text("Host capability probe")
                .font(.headline)
            Text("With a supported host frontmost, press \(CapabilityProbeHotKeyMonitor.shortcutDisplay) to sample document-reference capabilities.")
            Text("Zotero")
                .font(.subheadline)
            Text(diagnostics.capabilityProbeSummary.summary)
                .foregroundStyle(.secondary)
            Text(diagnostics.capabilityProbeSummary.documentReferenceCandidateAvailability.summary)
                .foregroundStyle(.secondary)
            Text(diagnostics.capabilityProbeStatus.summary)
                .foregroundStyle(.secondary)
            Button("Reset Zotero probe results") {
                diagnostics.resetCapabilityProbe()
            }
            Text("Typora")
                .font(.subheadline)
            Text(diagnostics.typoraDocumentReferenceProbeSummary.summary)
                .foregroundStyle(.secondary)
            Text(diagnostics.typoraDocumentReferenceProbeStatus.summary)
                .foregroundStyle(.secondary)
            Button("Reset Typora document-reference probe results") {
                diagnostics.resetTyporaDocumentReferenceProbe()
            }
            Divider()
            Text("Typora selection feasibility")
                .font(.headline)
            Text("Recorded on each ⌘D capture while Typora is frontmost.")
                .foregroundStyle(.secondary)
            Text(diagnostics.typoraCapabilityProbeSummary.summary)
                .foregroundStyle(.secondary)
            Text(diagnostics.typoraCapabilityProbeStatus.summary)
                .foregroundStyle(.secondary)
            Button("Reset Typora feasibility results") {
                diagnostics.resetTyporaCapabilityProbe()
            }
            Divider()
            Text("Reading session")
                .font(.headline)
            Text(diagnostics.readingSession.statusDescription)
                .foregroundStyle(.secondary)
            Text(diagnostics.readingContextDiagnostic)
                .foregroundStyle(.secondary)
            HStack {
                Button("Choose document…") {
                    diagnostics.chooseReadingSource()
                }
                Button("Stop session") {
                    diagnostics.clearReadingSession()
                }
                .disabled(diagnostics.readingSession.displayName == nil)
                Button("Clear session") {
                    diagnostics.clearReadingSession()
                }
                .disabled(diagnostics.readingSession.displayName == nil)
            }
            Divider()
            Text("Markdown showcase")
                .font(.headline)
            Text("Opens a fixed Markdown sample without calling Ollama.")
                .foregroundStyle(.secondary)
            Button("Show Markdown showcase") {
                diagnostics.showMarkdownShowcase()
            }
        }
    }
}
#endif
