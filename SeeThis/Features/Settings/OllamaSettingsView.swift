import AppKit
import SwiftUI

struct OllamaSettingsView: View {
    @ObservedObject var diagnostics: HostContextDiagnostics
    @ObservedObject var store: LensStore
    @State private var isInstallMoreExpanded = false
    @State private var showsSelectedInstallConfirmation = false
    @State private var showsStopConfirmation = false

    private static let installMoreBottomAnchor = "installMoreBottomAnchor"

    var body: some View {
        ScrollViewReader { proxy in
            SettingsPage {
                Text("Language model")
                    .font(.headline)
                Text("Explanations run through Ollama. Selected text stays on this Mac unless you choose an Ollama cloud model.")
                    .foregroundStyle(.secondary)
                statusView
                Text("Endpoint: \(OllamaProvider.serviceEndpoint.absoluteString)")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                installMoreSection
            }
            .contentShape(Rectangle())
            .onTapGesture {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
            .onAppear {
                if case .notChecked = diagnostics.ollamaConnectionStatus {
                    diagnostics.checkOllamaConnection()
                }
            }
            .onChange(of: isInstallMoreExpanded) { _, expanded in
                guard expanded else { return }
                // Yield one runloop so the disclosure content (and its anchor)
                // is inserted into the hierarchy before we ask ScrollView to
                // move to it; the disclosure's own expansion animation then
                // plays in parallel with the scroll.
                DispatchQueue.main.async {
                    withAnimation {
                        proxy.scrollTo(Self.installMoreBottomAnchor, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var installMoreSection: some View {
        if case let .available(models) = diagnostics.ollamaConnectionStatus {
            DisclosureGroup(isExpanded: $isInstallMoreExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    quickInstallHeader
                    recommendedModelList(installedModelIDs: Set(models.map(\.id)))
                    Text("Or")
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    Text("Install by name")
                        .font(.headline)
                    ManualInstallControls(diagnostics: diagnostics)
                    Color.clear.frame(height: 1).id(Self.installMoreBottomAnchor)
                }
                .padding(.top, 8)
            } label: {
                HStack {
                    Text("Install more models")
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isInstallMoreExpanded.toggle()
                }
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch diagnostics.ollamaConnectionStatus {
        case .notChecked, .checking:
            ProgressView("Checking local Ollama…")
        case .notInstalled:
            Text("Ollama isn't installed on this Mac. It powers the local model. Install it once, then come back.")
                .foregroundStyle(.secondary)
            Button("Download Ollama…") {
                diagnostics.openOllamaDownloadPage()
            }
            .hoverHighlight()
            Button("I installed it, check again") {
                diagnostics.checkOllamaConnection()
            }
            .hoverHighlight()
        case .notRunning(let installation):
            OllamaStatusHeader(isActive: false)
            Text(notRunningMessage(for: installation))
                .foregroundStyle(.secondary)
            Button(startButtonTitle(for: installation)) {
                diagnostics.startOllama()
            }
            .hoverHighlight()
        case .starting:
            ProgressView("Starting Ollama…")
        case .noModels:
            OllamaStatusHeader(isActive: true)
            Text("No models are installed yet. Pick one to install below.")
                .foregroundStyle(.secondary)
            quickInstallHeader
            recommendedModelList(installedModelIDs: [])
            Text("Or")
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            Text("Install by name")
                .font(.headline)
            ManualInstallControls(diagnostics: diagnostics)
        case .available(let models):
            HStack(spacing: 6) {
                OllamaStatusHeader(isActive: true)
                Spacer()
                Button("Stop Ollama") {
                    showsStopConfirmation = true
                }
                .hoverHighlight()
                .confirmationDialog(
                    "Stop Ollama?",
                    isPresented: $showsStopConfirmation
                ) {
                    Button("Stop", role: .destructive) { diagnostics.stopOllama() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Other apps that use Ollama will lose access until it's started again.")
                }
            }
            if !models.contains(where: { $0.id == store.selectedOllamaModel }) {
                Text("Selected model \(store.selectedOllamaModel) isn't installed. Install it now, or pick one below.")
                    .foregroundStyle(.secondary)
                Button("Install \(store.selectedOllamaModel)") {
                    showsSelectedInstallConfirmation = true
                }
                .disabled(diagnostics.modelInstallStates[store.selectedOllamaModel] != nil)
                .hoverHighlight()
                .confirmationDialog(
                    "Install \(store.selectedOllamaModel)?",
                    isPresented: $showsSelectedInstallConfirmation
                ) {
                    Button("Install") {
                        diagnostics.installModel(id: store.selectedOllamaModel)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Downloads may take several minutes. Size depends on the model.")
                }
            }
            InstalledModelsList(diagnostics: diagnostics, store: store, models: models)
        }
    }

    @ViewBuilder
    private var quickInstallHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Quick install")
                .font(.headline)
            Text("Examples you can install with one click.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func recommendedModelList(installedModelIDs: Set<String>) -> some View {
        let notInstalled = RecommendedOllamaModel.curated.filter { !installedModelIDs.contains($0.id) }
        return VStack(alignment: .leading, spacing: 8) {
            if notInstalled.isEmpty {
                Text("All recommended models are installed.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(notInstalled) { model in
                    RecommendedModelRow(
                        model: model,
                        installState: diagnostics.modelInstallStates[model.id],
                        showsCancelledHint: diagnostics.recentlyCancelledInstalls.contains(model.id),
                        onInstall: { diagnostics.installModel(id: model.id) },
                        onCancel: { diagnostics.cancelInstall(id: model.id) },
                        onPause: { diagnostics.pauseInstall(id: model.id) },
                        onDismissCancelledHint: { diagnostics.dismissCancelHint(id: model.id) }
                    )
                }
            }
        }
    }

    private func notRunningMessage(for installation: OllamaInstallation) -> String {
        switch installation {
        case .app:
            return "Start Ollama to enable local explanations."
        case .cli:
            return "Start the Ollama background service. It stays up once started."
        }
    }

    private func startButtonTitle(for installation: OllamaInstallation) -> String {
        switch installation {
        case .app: "Launch Ollama"
        case .cli: "Start Ollama service"
        }
    }
}

private struct OllamaStatusHeader: View {
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isActive ? Color.green : Color.secondary.opacity(0.6))
                .frame(width: 8, height: 8)
            Text("Ollama")
                .font(.body.weight(.medium))
            Text(isActive ? "Active" : "Inactive")
                .font(.caption)
                .foregroundStyle(isActive ? Color.green : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill((isActive ? Color.green : Color.secondary).opacity(0.15))
                )
        }
        .fixedSize()
    }
}

private struct InstalledModelsList: View {
    @ObservedObject var diagnostics: HostContextDiagnostics
    @ObservedObject var store: LensStore
    let models: [OllamaInstalledModel]
    @State private var filter = ""
    @State private var isEmbeddingSectionExpanded = false

    private var filtered: [OllamaInstalledModel] {
        let trimmed = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return models }
        return models.filter { $0.id.lowercased().contains(trimmed) }
    }

    private var chatCapable: [OllamaInstalledModel] {
        filtered.filter { $0.isEmbeddingOnly != true }
    }

    private var embeddingOnly: [OllamaInstalledModel] {
        filtered.filter { $0.isEmbeddingOnly == true }
    }

    // Force the section open when the user is filtering (they're searching for something,
    // don't hide it) or when no chat model exists at all (otherwise the main list is empty).
    private var embeddingSectionExpandedBinding: Binding<Bool> {
        Binding(
            get: {
                isEmbeddingSectionExpanded
                    || !filter.trimmingCharacters(in: .whitespaces).isEmpty
                    || chatCapable.isEmpty
            },
            set: { isEmbeddingSectionExpanded = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Installed")
                .font(.headline)
                .padding(.top, 4)
            if let notice = diagnostics.lastDeletionNotice {
                DeletionNoticeBanner(
                    notice: notice,
                    onDismiss: { diagnostics.dismissDeletionNotice() }
                )
                .transition(.opacity)
            }
            TextField("Filter installed models…", text: $filter)
                .textFieldStyle(.roundedBorder)
            if filtered.isEmpty {
                Text("No installed model matches “\(filter)”.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                HStack {
                    Text("Available for chat (\(chatCapable.count))")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.top, 4)
                ForEach(chatCapable) { model in
                    row(for: model)
                }
                if !embeddingOnly.isEmpty {
                    DisclosureGroup(isExpanded: embeddingSectionExpandedBinding) {
                        VStack(spacing: 8) {
                            ForEach(embeddingOnly) { model in
                                row(for: model)
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        HStack {
                            Text("Not usable for chat (\(embeddingOnly.count))")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isEmbeddingSectionExpanded.toggle()
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: diagnostics.lastDeletionNotice)
    }

    private func row(for model: OllamaInstalledModel) -> some View {
        InstalledModelRow(
            model: model,
            isSelected: model.id == store.selectedOllamaModel,
            isDeleting: diagnostics.deletingModels.contains(model.id),
            isRecentlyInstalled: diagnostics.recentlyInstalledName == model.id,
            hasOtherInstalledModel: models.contains { $0.id != model.id },
            onSelect: { store.setSelectedOllamaModel(model.id) },
            onDelete: { diagnostics.deleteInstalledModel(id: model.id) }
        )
    }
}

private struct DeletionNoticeBanner: View {
    let notice: DeletionNotice
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Uninstalled \(notice.modelID)")
                    .font(.body)
                if let freedSizeText = notice.freedSizeText {
                    Text("Frees up to \(freedSizeText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 10, height: 10)
                    .padding(4)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Dismiss")
            .hoverHighlight()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct InstalledModelRow: View {
    let model: OllamaInstalledModel
    let isSelected: Bool
    let isDeleting: Bool
    let isRecentlyInstalled: Bool
    let hasOtherInstalledModel: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var showsDeleteConfirmation = false
    @State private var isHovering = false
    @State private var flashIntensity: Double = 0

    private var rowTooltip: String {
        if model.isEmbeddingOnly == true {
            return "Embedding-only model. Can't be used for chat."
        }
        return isSelected ? "In use" : "Use this model"
    }

    private var uninstallConfirmationMessage: String {
        var lines = ["This removes \(model.id) from Ollama and frees the disk space it uses, aside from any layers shared with other installed models."]
        if isSelected {
            if hasOtherInstalledModel {
                lines.append("Note: This is the model you're using. Another installed model will be selected automatically.")
            } else {
                lines.append("Note: This is the model you're using and the only installed one.")
            }
        }
        return lines.joined(separator: "\n\n")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onSelect) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(model.id)
                                .font(.body.weight(.medium))
                            if let sizeText = model.displaySize {
                                Text(sizeText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let contextText = model.contextLengthDisplay {
                            Text("Supports up to \(contextText) tokens")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        // Prefer capability-based verdict; fall back to name heuristic only when
                        // capabilities weren't fetched (soft hint stays advisory in that case).
                        if model.isEmbeddingOnly == nil, model.isEmbeddingLike {
                            Text("Embedding model. Likely not suitable for chat here.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.isEmbeddingOnly == true)
            .opacity(model.isEmbeddingOnly == true ? 0.45 : 1)
            .help(rowTooltip)
            Button {
                showsDeleteConfirmation = true
            } label: {
                if isDeleting {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text("Uninstalling")
                    }
                } else {
                    Text("Uninstall")
                }
            }
            .font(.callout)
            .fixedSize()
            .help("Uninstall this model from Ollama")
            .hoverHighlight()
            .disabled(isDeleting)
            .confirmationDialog(
                "Uninstall \(model.id)?",
                isPresented: $showsDeleteConfirmation
            ) {
                Button("Uninstall", role: .destructive) { onDelete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(uninstallConfirmationMessage)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            ZStack {
                Color.secondary.opacity((isHovering && model.isEmbeddingOnly != true) ? 0.12 : 0.06)
                Color.green.opacity(0.32 * flashIntensity)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isHovering = $0 }
        .onChange(of: isRecentlyInstalled) { _, new in
            guard new else { return }
            triggerFlash()
        }
        .onAppear {
            if isRecentlyInstalled { triggerFlash() }
        }
    }

    private func triggerFlash() {
        withAnimation(.easeIn(duration: 0.15)) {
            flashIntensity = 1.0
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.easeOut(duration: 0.9)) {
                flashIntensity = 0
            }
        }
    }
}

private struct ManualInstallControls: View {
    @ObservedObject var diagnostics: HostContextDiagnostics
    @State private var manualModelName = ""
    @State private var showsInstallConfirmation = false
    @State private var pendingInstallName: String?

    private static let bottomAnchorID = "manualInstallControlsBottom"

    private var trimmedName: String {
        manualModelName.trimmingCharacters(in: .whitespaces)
    }

    private var installState: ModelInstallState? {
        guard !trimmedName.isEmpty else { return nil }
        return diagnostics.modelInstallStates[trimmedName]
    }

    private var isBusyPulling: Bool {
        switch installState {
        case .queued, .pulling, .paused: return true
        default: return false
        }
    }

    private var showsCancelHint: Bool {
        !trimmedName.isEmpty && diagnostics.recentlyCancelledInstalls.contains(trimmedName)
    }

    // If the user typed a curated model name, the recommended row above already shows
    // progress/hint for it - don't render a duplicate here.
    private var isCoveredByRecommendedRow: Bool {
        RecommendedOllamaModel.curated.contains { $0.id == trimmedName }
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Model name (e.g. llama3.2)", text: $manualModelName)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isBusyPulling)
                    Button("Install") {
                        showsInstallConfirmation = true
                    }
                    .disabled(trimmedName.isEmpty || isBusyPulling)
                    .hoverHighlight()
                }
                HStack(spacing: LensEditorSaveNote.iconToMessageSpacing) {
                    Image(systemName: LensEditorSaveNote.iconName)
                    Text("Browse [ollama.com/library](https://ollama.com/library) to find a model name.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                if let installState, !isCoveredByRecommendedRow {
                    progressRow(state: installState)
                }
                if showsCancelHint, !isCoveredByRecommendedRow {
                    cancelHintRow
                }
                Color.clear.frame(height: 1).id(Self.bottomAnchorID)
            }
            .onChange(of: pendingInstallName) { _, new in
                guard new != nil else { return }
                withAnimation {
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
            }
        }
        .confirmationDialog(
            "Install \(trimmedName)?",
            isPresented: $showsInstallConfirmation
        ) {
            Button("Install") {
                pendingInstallName = trimmedName
                diagnostics.installModel(id: trimmedName)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Downloads may take several minutes. Size depends on the model.")
        }
        .onChange(of: diagnostics.ollamaConnectionStatus) { _, new in
            guard let name = pendingInstallName else { return }
            if case .available(let models) = new, models.contains(where: { $0.id == name }) {
                manualModelName = ""
                pendingInstallName = nil
            }
        }
    }

    @ViewBuilder
    private func progressRow(state: ModelInstallState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(trimmedName)
                    .font(.body.weight(.medium))
                Spacer()
                switch state {
                case .failed:
                    Button("Retry") { showsInstallConfirmation = true }
                        .hoverHighlight()
                    Button("Cancel") { diagnostics.cancelInstall(id: trimmedName) }
                        .hoverHighlight()
                case .paused:
                    Button("Resume") { diagnostics.installModel(id: trimmedName) }
                        .hoverHighlight()
                    Button("Cancel") { diagnostics.cancelInstall(id: trimmedName) }
                        .hoverHighlight()
                case .queued, .pulling:
                    Button("Pause") { diagnostics.pauseInstall(id: trimmedName) }
                        .hoverHighlight()
                    Button("Cancel") { diagnostics.cancelInstall(id: trimmedName) }
                        .hoverHighlight()
                }
            }
            progressContent(state: state)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func progressContent(state: ModelInstallState) -> some View {
        switch state {
        case .queued:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Preparing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .pulling(let progress):
            VStack(alignment: .leading, spacing: 3) {
                ProgressView(value: progress.fraction ?? 0.0)
                    .progressViewStyle(.linear)
                    .animation(nil, value: progress.fraction)
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text(progressLabel(for: progress))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .paused(let progress):
            VStack(alignment: .leading, spacing: 3) {
                ProgressView(value: progress.fraction ?? 0.0)
                    .progressViewStyle(.linear)
                Text(pausedLabel(for: progress))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var cancelHintRow: some View {
        HStack(spacing: 6) {
            Text("Cancelled. Any partial download is kept on disk for a quick resume.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                diagnostics.dismissCancelHint(id: trimmedName)
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 10, height: 10)
                    .padding(4)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Dismiss")
            .hoverHighlight()
        }
    }

    private func progressLabel(for progress: OllamaPullProgress) -> String {
        if let fraction = progress.fraction {
            let percent = Int((fraction * 100).rounded())
            return "\(progress.userFacingStatus) · \(percent)%"
        }
        return progress.userFacingStatus
    }

    private func pausedLabel(for progress: OllamaPullProgress) -> String {
        if let fraction = progress.fraction {
            let percent = Int((fraction * 100).rounded())
            return "Paused · \(percent)%"
        }
        return "Paused"
    }
}

private struct RecommendedModelRow: View {
    let model: RecommendedOllamaModel
    let installState: ModelInstallState?
    let showsCancelledHint: Bool
    let onInstall: () -> Void
    let onCancel: () -> Void
    let onPause: () -> Void
    let onDismissCancelledHint: () -> Void
    @State private var showsInstallConfirmation = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.id)
                        .font(.body.weight(.medium))
                    Text(model.downloadSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                progressBlock
                cancelHintBlock
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            actionButton
                .frame(minWidth: 88, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var progressBlock: some View {
        switch installState {
        case .queued:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Preparing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        case .pulling(let progress):
            VStack(alignment: .leading, spacing: 3) {
                ProgressView(value: progress.fraction ?? 0.0)
                    .progressViewStyle(.linear)
                    .animation(nil, value: progress.fraction)
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text(progressLabel(for: progress))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        case .paused(let progress):
            VStack(alignment: .leading, spacing: 3) {
                if let fraction = progress.fraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                } else {
                    ProgressView(value: 0.0).progressViewStyle(.linear)
                }
                Text(pausedLabel(for: progress))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.top, 4)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch installState {
        case .queued, .pulling:
            HStack(spacing: 6) {
                Button("Pause", action: onPause)
                    .hoverHighlight()
                Button("Cancel", action: onCancel)
                    .hoverHighlight()
            }
        case .paused:
            HStack(spacing: 6) {
                Button("Resume", action: onInstall)
                    .hoverHighlight()
                Button("Cancel", action: onCancel)
                    .hoverHighlight()
            }
        case .failed:
            HStack(spacing: 6) {
                Button("Retry", action: onInstall)
                    .hoverHighlight()
                Button("Cancel", action: onCancel)
                    .hoverHighlight()
            }
        case .none:
            Button("Install") {
                showsInstallConfirmation = true
            }
            .hoverHighlight()
            .confirmationDialog(
                "Install \(model.id)?",
                isPresented: $showsInstallConfirmation
            ) {
                Button("Install") { onInstall() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Downloads about \(model.downloadSize). This may take several minutes.")
            }
        }
    }

    @ViewBuilder
    private var cancelHintBlock: some View {
        if showsCancelledHint {
            HStack(spacing: 6) {
                Text("Cancelled. Any partial download is kept on disk for a quick resume.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    onDismissCancelledHint()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 10, height: 10)
                        .padding(4)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Dismiss")
                .hoverHighlight()
            }
            .padding(.top, 4)
        }
    }

    private func progressLabel(for progress: OllamaPullProgress) -> String {
        if let fraction = progress.fraction {
            let percent = Int((fraction * 100).rounded())
            return "\(progress.userFacingStatus) · \(percent)%"
        }
        return progress.userFacingStatus
    }

    private func pausedLabel(for progress: OllamaPullProgress) -> String {
        if let fraction = progress.fraction {
            let percent = Int((fraction * 100).rounded())
            return "Paused · \(percent)%"
        }
        return "Paused"
    }
}

enum OllamaConnectionStatus: Equatable {
    case notChecked
    case checking
    case notInstalled
    case notRunning(OllamaInstallation)
    case starting
    case noModels
    case available([OllamaInstalledModel])
}

struct DeletionNotice: Equatable {
    let modelID: String
    let freedBytes: Int64?

    var freedSizeText: String? {
        guard let freedBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: freedBytes, countStyle: .file)
    }
}

enum ModelInstallState: Equatable {
    case queued
    case pulling(OllamaPullProgress)
    case paused(OllamaPullProgress)
    case failed(String)
}
