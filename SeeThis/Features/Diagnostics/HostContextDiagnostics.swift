import ApplicationServices
import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class HostContextDiagnostics: ObservableObject {
    @Published private(set) var isAccessibilityTrusted: Bool
    @Published private(set) var lastResult = "No capture has been run."
    @Published private(set) var captureRevision = 0
    private(set) var lastCaptureHostBundleIdentifier: String?
    private(set) var lastCaptureHasSelection = false
    @Published private(set) var lensSelectionRevision = 0
    @Published private(set) var paperContextSession: PaperContextSession = .disabled
    @Published private(set) var readingSession: ReadingSession = .disabled
    @Published private(set) var readingContextDiagnostic = "No document context match has been evaluated."
    #if DEBUG
    @Published private(set) var capabilityProbeSummary = ZoteroCapabilityProbeSummary()
    @Published private(set) var capabilityProbeStatus: ZoteroCapabilityProbeStatus = .noSamples
    @Published private(set) var typoraCapabilityProbeSummary = TyporaCapabilityProbeSummary()
    @Published private(set) var typoraCapabilityProbeStatus: TyporaCapabilityProbeStatus = .noSamples
    @Published private(set) var typoraDocumentReferenceProbeSummary = TyporaDocumentReferenceProbeSummary()
    @Published private(set) var typoraDocumentReferenceProbeStatus: TyporaCapabilityProbeStatus = .noSamples
    #endif
    @Published private(set) var ollamaConnectionStatus: OllamaConnectionStatus = .notChecked
    @Published private(set) var modelInstallStates: [String: ModelInstallState] = [:]
    @Published private(set) var recentlyCancelledInstalls: Set<String> = []
    // Cancelling a pull must never delete a model that was already on disk.
    private var installsOfPresentModels: Set<String> = []
    @Published private(set) var deletingModels: Set<String> = []
    @Published private(set) var recentlyInstalledName: String?
    @Published private(set) var lastDeletionNotice: DeletionNotice?
    private var modelInstallTasks: [String: Task<Void, Never>] = [:]
    private var cancelHintClearTasks: [String: Task<Void, Never>] = [:]
    private var recentlyInstalledClearTask: Task<Void, Never>?
    private var deletionNoticeClearTask: Task<Void, Never>?
    private static let cancelHintDisplayNanoseconds: UInt64 = 6_000_000_000
    private static let deletionNoticeDisplayNanoseconds: UInt64 = 4_000_000_000
    @Published var contextCharacterLimit: Int = ReadingSession.fullContextCharacterLimit {
        didSet {
            ReadingSession.fullContextCharacterLimit = contextCharacterLimit
            UserDefaults.standard.set(contextCharacterLimit, forKey: Self.contextCharacterLimitDefaultsKey)
        }
    }

    static let contextCharacterLimitDefaultsKey = "contextCharacterLimit"
    private let overlayController = OverlayController()
    private var isTutorialDemoActive = false
    private static let tutorialLenses = [ExplanationLens.tutorialDemo]
    private static let modelRequestTimeoutNanoseconds: UInt64 = 30_000_000_000
    let lensStore: LensStore
    let translateSettings: TranslateSettingsStore
    private let actionModelClient: any ActionModelClient
    private let accessibilityTrustProvider: () -> Bool
    private var activeRequestID: UUID?
    private var activeRequestTask: Task<Void, Never>?
    private var streamingAnswer = ""
    private var hasIssuedModelRequest = false
    private var activeSnapshot: SelectionSnapshot?
    private var activeSelectedLens: ExplanationLens?

    convenience init() {
        let lensStore = LensStore()
        self.init(
            lensStore: lensStore,
            translateSettings: TranslateSettingsStore(lensStore: lensStore)
        )
    }

    init(
        translateSettings: TranslateSettingsStore,
        accessibilityTrustProvider: @escaping () -> Bool = { AXIsProcessTrusted() }
    ) {
        self.accessibilityTrustProvider = accessibilityTrustProvider
        isAccessibilityTrusted = accessibilityTrustProvider()
        lensStore = translateSettings.lensStore
        self.translateSettings = translateSettings
        actionModelClient = DeadlineActionModelClient(
            base: OllamaProvider(),
            timeoutNanoseconds: Self.modelRequestTimeoutNanoseconds
        )
        loadContextCharacterLimit()
        configureOverlayCallbacks()
    }

    convenience init(lensStore: LensStore) {
        self.init(
            lensStore: lensStore,
            translateSettings: TranslateSettingsStore(lensStore: lensStore)
        )
    }

    init(
        lensStore: LensStore,
        translateSettings: TranslateSettingsStore,
        accessibilityTrustProvider: @escaping () -> Bool = { AXIsProcessTrusted() }
    ) {
        self.accessibilityTrustProvider = accessibilityTrustProvider
        isAccessibilityTrusted = accessibilityTrustProvider()
        self.lensStore = lensStore
        self.translateSettings = translateSettings
        actionModelClient = DeadlineActionModelClient(
            base: OllamaProvider(),
            timeoutNanoseconds: Self.modelRequestTimeoutNanoseconds
        )
        loadContextCharacterLimit()
        configureOverlayCallbacks()
    }

    private func loadContextCharacterLimit() {
        let saved = UserDefaults.standard.integer(forKey: Self.contextCharacterLimitDefaultsKey)
        guard saved >= ReadingSession.minimumFullContextCharacterLimit,
              saved <= ReadingSession.maximumFullContextCharacterLimit else {
            return
        }
        contextCharacterLimit = saved
        ReadingSession.fullContextCharacterLimit = saved
    }

    private func configureOverlayCallbacks() {
        overlayController.setOnDismiss { [weak self] in
            self?.cancelActiveRequest()
            self?.clearActivePresentation()
        }
        overlayController.setOnFileDropped { [weak self] url in
            self?.handleFileDroppedOnOverlay(url: url)
        }
    }

    private func handleFileDroppedOnOverlay(url: URL) {
        let hostBundleIdentifier = overlayController.activeHostBundleIdentifier
        do {
            let session = try ReadingSession.load(url: url, hostBundleIdentifier: hostBundleIdentifier)
            readingSession = session
            paperContextSession = .enabled
            lastResult = "Attached \(session.displayName ?? url.lastPathComponent) as context."
            recomputeCurrentPresentation()
        } catch {
            lastResult = "Could not load dropped file: \(url.lastPathComponent)"
        }
    }

    private func recomputeCurrentPresentation() {
        guard let snapshot = activeSnapshot else { return }
        let host = overlayController.activeHostBundleIdentifier
        let session = readingSession.matchesHost(host) ? readingSession : .disabled

        if let lens = activeSelectedLens {
            present(
                snapshot,
                using: session,
                hostBundleIdentifier: host,
                selectedLens: lens,
                repositionsOverlay: false,
                lensesOverride: isTutorialDemoActive ? Self.tutorialLenses : nil
            )
        } else {
            let name: String? = paperContextSession.isEnabled ? session.displayName : nil
            overlayController.updateLocalSourceName(name)
        }
    }

    func loadReadingSource(from url: URL, hostBundleIdentifier: String? = nil) {
        do {
            let session = try ReadingSession.load(url: url, hostBundleIdentifier: hostBundleIdentifier)
            readingSession = session
            paperContextSession = .enabled
            lastResult = "Attached \(session.displayName ?? url.lastPathComponent) as context."
        } catch {
            lastResult = "Could not load dropped file: \(url.lastPathComponent)"
        }
    }

    #if DEBUG
    func showMarkdownShowcase() {
        cancelActiveRequest()
        overlayController.presentPreview(
            answer: MarkdownShowcase.answer,
            model: "Markdown showcase",
            selectionPreviewText: "Static Markdown rendering test"
        )
        lastResult = "Showing static Markdown showcase."
    }
    #endif

    func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshAccessibilityPermission()
    }

    func refreshAccessibilityPermission() {
        isAccessibilityTrusted = accessibilityTrustProvider()
    }

    func refreshVisibleLenses() {
        overlayController.refreshVisibleActions(actionOptionsForOverlay())
    }

    private func actionsForOverlay() -> [ReaderAction] {
        let promptActions = lensStore.orderedLensIDs.compactMap { id -> ReaderAction? in
            if id == ExplanationLens.localTranslateID {
                return .lens(
                    .translation(targetLanguage: translateSettings.targetLanguageDisplayName)
                )
            }
            guard let lens = lensStore.lens(id: id),
                  lens.id != ExplanationLens.localTranslateID else {
                return nil
            }
            return .lens(lens)
        }
        let packageLoader = ActionPackageLoader(
            validator: ActionManifestValidator(
                runtimeVersion: SemanticVersion(1, 0, 0),
                knownCapabilityIDs: [DeepLTranslationCapability.capabilityID]
            ),
            availableCapabilityIDs: [DeepLTranslationCapability.capabilityID]
        )
        let packages = packageLoader
            .load(from: ActionPackageDirectories.production())
            .packages
        let packageActions = packages.compactMap { package -> ReaderAction? in
            guard case let .resolved(action) = PackageActionResolver.resolve(package) else {
                return nil
            }
            return .package(action)
        }
        return promptActions + packageActions
    }

    func actionOptionsForOverlay() -> [ReaderActionOption] {
        let enabledPackageIDs: Set<String> = translateSettings.isConfigured
            ? [TranslateSettingsStore.actionID]
            : []
        if !enabledPackageIDs.contains(TranslateSettingsStore.actionID),
           lensStore.inlineLensIDs.contains(TranslateSettingsStore.actionID) {
            lensStore.invalidateLens(id: TranslateSettingsStore.actionID)
        }
        return ReaderActionCatalog.options(
            actions: actionsForOverlay(),
            orderedIDs: lensStore.orderedLensIDs,
            visibleIDs: lensStore.inlineLensIDs,
            enabledPackageIDs: enabledPackageIDs
        )
    }

    func defaultActionForOverlay() -> ReaderAction? {
        guard let defaultLensID = lensStore.defaultLensID else { return nil }
        let action = actionOptionsForOverlay()
            .first(where: { $0.id == defaultLensID })?
            .action
        if action == nil {
            lensStore.setDefaultLens(id: nil)
        }
        return action
    }

    func setTutorialLensHint(_ isEnabled: Bool) {
        overlayController.setTutorialLensHint(isEnabled)
    }

    func setTutorialDemoActive(_ isEnabled: Bool) {
        isTutorialDemoActive = isEnabled
        if !isEnabled {
            overlayController.setTutorialLensHint(false)
        }
    }

    #if DEBUG
    func chooseReadingSource(hostBundleIdentifier: String? = nil) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .pdf,
            .plainText,
            UTType(filenameExtension: "md")!,
            UTType(filenameExtension: "markdown")!
        ]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadReadingSource(from: url, hostBundleIdentifier: hostBundleIdentifier)
    }
    #endif

    func clearReadingSession() {
        readingSession = .disabled
        paperContextSession = .disabled
    }

    #if DEBUG
    func probeFrontmostHostCapabilities() {
        probeCapabilities(for: HostProviderRouter.frontmostHost())
    }

    func probeCapabilities(for host: FrontmostHost) {
        switch host {
        case .zotero:
            probeZoteroCapabilities()
        case .typora:
            probeTyporaDocumentReference()
        case .unsupported:
            lastResult = "Capability probe: no supported host is frontmost."
        }
    }

    func probeZoteroCapabilities() {
        let provider = ZoteroHostContextProvider()
        switch provider.probeCapabilities() {
        case .success(let observations):
            capabilityProbeSummary.record(observations)
            capabilityProbeStatus = .recorded
        case .failure(let failure):
            capabilityProbeStatus = .failed(failure)
        }
    }

    func resetCapabilityProbe() {
        capabilityProbeSummary = ZoteroCapabilityProbeSummary()
        capabilityProbeStatus = .noSamples
    }

    func probeTyporaDocumentReference() {
        switch TyporaHostContextProvider().probeDocumentReference() {
        case .success(let availability):
            typoraDocumentReferenceProbeSummary.record(availability)
            typoraDocumentReferenceProbeStatus = .recorded
        case .failure(let outcome):
            typoraDocumentReferenceProbeStatus = .failed(outcome)
        }
    }

    func resetTyporaDocumentReferenceProbe() {
        typoraDocumentReferenceProbeSummary = TyporaDocumentReferenceProbeSummary()
        typoraDocumentReferenceProbeStatus = .noSamples
    }

    func resetTyporaCapabilityProbe() {
        typoraCapabilityProbeSummary = TyporaCapabilityProbeSummary()
        typoraCapabilityProbeStatus = .noSamples
    }
    #endif

    func checkOllamaConnection() {
        ollamaConnectionStatus = .checking
        Task { [weak self] in
            let result = await OllamaProvider().listModels()
            guard let self else { return }
            switch result {
            case .success(let descriptors) where descriptors.isEmpty:
                ollamaConnectionStatus = .noModels
            case .success(let descriptors):
                let models = descriptors.map(OllamaInstalledModel.init(from:))
                let enriched = await Self.enrichWithMetadata(models)
                ollamaConnectionStatus = .available(enriched)
            case .failure:
                if let installation = OllamaInstallation.detected {
                    ollamaConnectionStatus = .notRunning(installation)
                } else {
                    ollamaConnectionStatus = .notInstalled
                }
            }
        }
    }

    // Ollama /api/show is per-model; parallelize so the list isn't gated by the
    // slowest model (a cold show call can take a few hundred ms). Missing metadata
    // is fine — the model still renders, just without the extra fields.
    private static func enrichWithMetadata(_ models: [OllamaInstalledModel]) async -> [OllamaInstalledModel] {
        await withTaskGroup(of: (Int, OllamaModelMetadata?).self) { group in
            for (index, model) in models.enumerated() {
                group.addTask {
                    let descriptor = await OllamaProvider().showModel(name: model.id)
                    return (index, descriptor.map { OllamaModelMetadata(from: $0) })
                }
            }
            var result = models
            for await (index, metadata) in group {
                result[index].metadata = metadata
            }
            return result
        }
    }

    func startOllama(
        onReady: (() -> Void)? = nil,
        onFailure: (() -> Void)? = nil
    ) {
        ollamaConnectionStatus = .starting
        overlayController.setFailureStatus("Starting Ollama…")
        overlayController.setFailureActions([])
        Task { [weak self] in
            let provider = OllamaProvider()
            let launched = await provider.startService()
            guard let self else { return }
            guard launched else {
                self.overlayController.setFailureStatus("Ollama could not be started. Check the installation, then try again.")
                onFailure?()
                if let installation = OllamaInstallation.detected {
                    ollamaConnectionStatus = .notRunning(installation)
                } else {
                    ollamaConnectionStatus = .notInstalled
                }
                return
            }
            let ready = await provider.waitForServiceReady(timeoutSeconds: 15, pollIntervalSeconds: 0.5)
            guard self.ollamaConnectionStatus == .starting else { return }
            if ready {
                self.overlayController.setFailureStatus("Ollama is ready. Click Retry to try again.")
                onReady?()
                self.checkOllamaConnection()
            } else if let installation = OllamaInstallation.detected {
                self.overlayController.setFailureStatus("Ollama is still starting. Try Retry in a moment.")
                onFailure?()
                ollamaConnectionStatus = .notRunning(installation)
            } else {
                self.overlayController.setFailureStatus("Ollama is still starting. Try Retry in a moment.")
                onFailure?()
                ollamaConnectionStatus = .notInstalled
            }
        }
    }

    func openOllamaDownloadPage() {
        NSWorkspace.shared.open(OllamaInstallation.downloadPageURL)
    }

    func stopOllama() {
        ollamaConnectionStatus = .checking
        Task { [weak self] in
            _ = await OllamaProvider().stopService()
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self else { return }
            self.checkOllamaConnection()
        }
    }

    func installModel(id: String) {
        guard modelInstallTasks[id] == nil else { return }
        dismissCancelHint(id: id)
        if modelMayAlreadyBeInstalled(id) {
            installsOfPresentModels.insert(id)
        } else {
            installsOfPresentModels.remove(id)
        }
        modelInstallStates[id] = .queued
        let task = Task { [weak self] in
            let result = await OllamaProvider().pullModel(name: id) { [weak self] raw in
                await MainActor.run {
                    guard let self else { return }
                    guard self.modelInstallStates[id] != nil else { return }
                    let progress = OllamaPullProgress(from: raw)
                    // Hold the last known byte counts through fraction-less chunks
                    // (verify / write manifest) so the bar doesn't flicker.
                    let stabilized: OllamaPullProgress
                    if progress.fraction == nil,
                       case .pulling(let previous) = self.modelInstallStates[id],
                       previous.fraction != nil {
                        stabilized = OllamaPullProgress(
                            status: progress.status,
                            completedBytes: previous.completedBytes,
                            totalBytes: previous.totalBytes
                        )
                    } else {
                        stabilized = progress
                    }
                    self.modelInstallStates[id] = .pulling(stabilized)
                }
            }
            await MainActor.run {
                guard let self else { return }
                self.modelInstallTasks[id] = nil
                switch result {
                case .success:
                    self.modelInstallStates.removeValue(forKey: id)
                    self.refreshAfterInstall(installedModel: id)
                case .failure(.cancelled):
                    break
                case .failure(let failure):
                    self.modelInstallStates[id] = .failed(failure.message)
                }
            }
        }
        modelInstallTasks[id] = task
    }

    private func modelMayAlreadyBeInstalled(_ id: String) -> Bool {
        switch ollamaConnectionStatus {
        case .available(let models):
            return OllamaProvider.isInstalled(id, among: models.map(\.id))
        case .notChecked, .checking:
            return true
        case .notInstalled, .notRunning, .starting, .noModels:
            return false
        }
    }

    func cancelInstall(id: String) {
        let shouldCleanup = ModelInstallCancellationPolicy.shouldDeletePartialModel(
            state: modelInstallStates[id],
            modelWasPresentBeforeInstall: installsOfPresentModels.contains(id)
        )
        modelInstallTasks[id]?.cancel()
        modelInstallTasks[id] = nil
        modelInstallStates.removeValue(forKey: id)
        guard shouldCleanup else { return }
        Task { _ = await OllamaProvider().deleteModel(name: id) }
        recentlyCancelledInstalls.insert(id)
        cancelHintClearTasks[id]?.cancel()
        cancelHintClearTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.cancelHintDisplayNanoseconds)
            guard let self, !Task.isCancelled else { return }
            self.recentlyCancelledInstalls.remove(id)
            self.cancelHintClearTasks[id] = nil
        }
    }

    func pauseInstall(id: String) {
        let snapshot: OllamaPullProgress
        switch modelInstallStates[id] {
        case .pulling(let progress):
            snapshot = progress
        case .queued:
            snapshot = OllamaPullProgress(status: "Paused", completedBytes: nil, totalBytes: nil)
        default:
            return
        }
        modelInstallTasks[id]?.cancel()
        modelInstallTasks[id] = nil
        modelInstallStates[id] = .paused(snapshot)
    }

    func dismissCancelHint(id: String) {
        cancelHintClearTasks[id]?.cancel()
        cancelHintClearTasks[id] = nil
        recentlyCancelledInstalls.remove(id)
    }

    func deleteInstalledModel(id: String) {
        guard !deletingModels.contains(id) else { return }
        let sizeBytesBeforeDelete: Int64?
        if case let .available(models) = ollamaConnectionStatus {
            sizeBytesBeforeDelete = models.first(where: { $0.id == id })?.sizeBytes
        } else {
            sizeBytesBeforeDelete = nil
        }
        deletingModels.insert(id)
        Task { [weak self] in
            let result = await OllamaProvider().deleteModel(name: id)
            guard let self else { return }
            self.deletingModels.remove(id)
            guard case .success = result else { return }
            self.publishDeletionNotice(modelID: id, freedBytes: sizeBytesBeforeDelete)
            let refreshed = await OllamaProvider().listModels()
            switch refreshed {
            case .success(let descriptors) where descriptors.isEmpty:
                self.ollamaConnectionStatus = .noModels
                if id == self.lensStore.selectedOllamaModel {
                    self.lensStore.setSelectedOllamaModel(OllamaProvider.defaultModelName)
                }
            case .success(let descriptors):
                let models = descriptors.map(OllamaInstalledModel.init(from:))
                let enriched = await Self.enrichWithMetadata(models)
                self.ollamaConnectionStatus = .available(enriched)
                if id == self.lensStore.selectedOllamaModel, let fallback = enriched.first {
                    self.lensStore.setSelectedOllamaModel(fallback.id)
                }
            case .failure:
                self.checkOllamaConnection()
            }
        }
    }

    func dismissDeletionNotice() {
        deletionNoticeClearTask?.cancel()
        deletionNoticeClearTask = nil
        lastDeletionNotice = nil
    }

    private func publishDeletionNotice(modelID: String, freedBytes: Int64?) {
        lastDeletionNotice = DeletionNotice(modelID: modelID, freedBytes: freedBytes)
        deletionNoticeClearTask?.cancel()
        deletionNoticeClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.deletionNoticeDisplayNanoseconds)
            guard let self, !Task.isCancelled else { return }
            if self.lastDeletionNotice?.modelID == modelID {
                self.lastDeletionNotice = nil
            }
            self.deletionNoticeClearTask = nil
        }
    }

    private func refreshAfterInstall(installedModel: String) {
        Task { [weak self] in
            let result = await OllamaProvider().listModels()
            guard let self else { return }
            switch result {
            case .success(let descriptors) where descriptors.isEmpty:
                ollamaConnectionStatus = .noModels
            case .success(let descriptors):
                let models = descriptors.map(OllamaInstalledModel.init(from:))
                let enriched = await Self.enrichWithMetadata(models)
                ollamaConnectionStatus = .available(enriched)
                let ids = enriched.map(\.id)
                if !ids.contains(lensStore.selectedOllamaModel), ids.contains(installedModel) {
                    lensStore.setSelectedOllamaModel(installedModel)
                }
                self.flagRecentlyInstalled(installedModel)
            case .failure:
                checkOllamaConnection()
            }
        }
    }

    private func flagRecentlyInstalled(_ id: String) {
        recentlyInstalledName = id
        recentlyInstalledClearTask?.cancel()
        recentlyInstalledClearTask = Task { [weak self] in
            // Hold just long enough for the row's onChange to fire; the visible flash
            // is a local animation on the row and lasts ~1s independent of this.
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, !Task.isCancelled else { return }
            if self.recentlyInstalledName == id {
                self.recentlyInstalledName = nil
            }
            self.recentlyInstalledClearTask = nil
        }
    }

    #if DEBUG
    func debugSetOllamaStatus(_ status: OllamaConnectionStatus) {
        ollamaConnectionStatus = status
    }
    #endif

    func capture() {
        cancelActiveRequest()
        capture(selectedLens: nil, repositionsOverlay: true)
    }

    private func capture(
        selectedLens: ExplanationLens?,
        repositionsOverlay: Bool,
        lensesOverride: [ExplanationLens]? = nil,
        onSelectionLost: (() -> Void)? = nil
    ) {
        activeRequestID = nil
        if repositionsOverlay {
            overlayController.dismiss()
        }

        guard let result = UniversalSelectionCapture.capture() else {
            isAccessibilityTrusted = false
            lastResult = "Allow Accessibility access, then try again."
            if let onSelectionLost {
                overlayController.showSelectionLost(onRetry: onSelectionLost)
            } else {
                overlayController.presentNotice(
                    "Accessibility access is off. Turn it on for SeeThis in System Settings → Privacy & Security → Accessibility.",
                    actions: [
                        OverlayFailureAction(id: "open-accessibility", title: "Open Accessibility Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    ]
                )
            }
            return
        }
        isAccessibilityTrusted = true
        if result.stage == .secureField {
            lastResult = "Secure field. Nothing captured."
            if let onSelectionLost {
                overlayController.showSelectionLost(onRetry: onSelectionLost)
            } else {
                overlayController.presentNotice("SeeThis doesn't read password fields.")
            }
            return
        }
        lastCaptureHostBundleIdentifier = result.hostBundleIdentifier
        lastCaptureHasSelection = !result.text.isEmpty
        captureRevision += 1

        let bundleIdentifier = result.hostBundleIdentifier
        let documentTitle = documentTitle(forHost: bundleIdentifier)
        let snapshot = SelectionSnapshot(
            hostBundleIdentifier: bundleIdentifier ?? "",
            selectedText: result.text,
            selectedRange: nil,
            documentTitle: documentTitle
        )
        let session = readingSession.matchesHost(bundleIdentifier) ? readingSession : .disabled

        present(
            snapshot,
            using: session,
            hostBundleIdentifier: bundleIdentifier,
            selectedLens: selectedLens,
            repositionsOverlay: repositionsOverlay,
            tutorialDemo: isTutorialDemoActive && selectedLens == nil,
            lensesOverride: lensesOverride
                ?? (isTutorialDemoActive ? Self.tutorialLenses : nil)
        )
        lastResult = captureStageSummary(result)
    }

    private func documentTitle(forHost bundleIdentifier: String?) -> String? {
        guard bundleIdentifier == HostBundleIdentifier.zotero,
              let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return UniversalSelectionCapture.focusedWindowTitle(of: application)
    }

    private func captureStageSummary(_ result: UniversalSelectionCaptureResult) -> String {
        let source: String
        switch result.stage {
        case .accessibility: source = "AX"
        case .menuBarCopy: source = "menu Copy"
        case .syntheticCopy: source = "⌘C"
        case .noSelection: return "No selection captured."
        case .secureField: return "Secure field. Nothing captured."
        }
        return "Captured \(result.text.count) chars via \(source)."
    }

    private func captureForLensSelection(_ lens: ExplanationLens) {
        cancelActiveRequest()
        lensSelectionRevision += 1

        let stashedHost = overlayController.activeHostBundleIdentifier
        let currentFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if LensSelectionCapturePolicy.shouldReuseActiveSnapshot(
            activeHostBundleIdentifier: stashedHost,
            frontmostBundleIdentifier: currentFrontmost,
            appBundleIdentifier: Bundle.main.bundleIdentifier
        ),
           let stashedHost,
           let snapshot = activeSnapshot,
           !snapshot.selectedText.isEmpty {
            if isTutorialDemoActive {
                overlayController.setTutorialDismissHint(true)
            }
            let session = readingSession.matchesHost(stashedHost) ? readingSession : .disabled
            present(
                snapshot,
                using: session,
                hostBundleIdentifier: stashedHost,
                selectedLens: lens,
                repositionsOverlay: false,
                tutorialDemo: false,
                lensesOverride: isTutorialDemoActive ? Self.tutorialLenses : nil
            )
            return
        }

        capture(
            selectedLens: lens,
            repositionsOverlay: false,
            lensesOverride: isTutorialDemoActive ? Self.tutorialLenses : nil,
            onSelectionLost: { [weak self] in
                self?.captureForLensSelection(lens)
            }
        )
        if isTutorialDemoActive {
            overlayController.setTutorialDismissHint(true)
        }
    }

    private func present(
        _ snapshot: SelectionSnapshot,
        using readingSession: ReadingSession,
        hostBundleIdentifier: String?,
        selectedLens: ExplanationLens?,
        repositionsOverlay: Bool,
        tutorialDemo: Bool = false,
        lensesOverride: [ExplanationLens]? = nil
    ) {
        activeSnapshot = snapshot
        activeSelectedLens = selectedLens
        let paperTitle = paperContextSession.titleForRequest(documentTitle: snapshot.documentTitle)
        let usingFullText = paperContextSession.isEnabled && readingSession.fullText != nil
        let contextWindow = usingFullText
            ? readingSession.fullTextWindow(around: snapshot.selectedText)
            : nil
        let localContext: String?
        if let contextWindow {
            localContext = contextWindow.text
        } else {
            localContext = paperContextSession.localContext(
                for: snapshot.selectedText,
                in: readingSession
            )
        }
        let localContextMatchStatus = paperContextSession.matchStatus(
            for: snapshot.selectedText,
            in: readingSession
        )
        readingContextDiagnostic = localContextMatchStatus?
            .diagnosticDescription ?? "Local context: no document source connected."
        let localSourceName: String?
        if paperContextSession.isEnabled, let displayName = readingSession.displayName {
            if let mode = contextWindow?.mode {
                switch mode {
                case .whole: localSourceName = "\(displayName) · full document"
                case .selectionWindow: localSourceName = "\(displayName) · selection window"
                case .prefix: localSourceName = "\(displayName) · document start"
                }
            } else {
                localSourceName = displayName
            }
        } else {
            localSourceName = nil
        }
        let localContextFallback: LocalContextFallback
        if let mode = contextWindow?.mode {
            localContextFallback = mode == .prefix ? .documentTooLargeToLocate : .none
        } else {
            switch localContextMatchStatus {
            case .some(.ambiguous): localContextFallback = .selectLongerPhrase
            case .some(.notFound): localContextFallback = .noMatch
            case .some(.matched), .none: localContextFallback = .none
            }
        }
        let actionOptions: [ReaderActionOption]
        if let lensesOverride {
            actionOptions = lensesOverride.map {
                ReaderActionOption(action: .lens($0), availability: .enabled)
            }
        } else {
            actionOptions = actionOptionsForOverlay()
        }
        let lenses = lensesOverride ?? actionOptions.compactMap { option in
            guard case let .lens(lens) = option.action else { return nil }
            return lens
        }
        let defaultAction = selectedLens == nil && lensesOverride == nil
            ? defaultActionForOverlay()
            : nil
        if activeSelectedLens == nil, case let .lens(defaultLens)? = defaultAction {
            activeSelectedLens = defaultLens
        }
        let model = lensStore.selectedOllamaModel
        let startRequest: (ExplanationLens) -> Void = { [weak self] lens in
            let action = LensActionResolver.resolve(
                lens,
                targetLanguage: self?.translateSettings.targetLanguageDisplayName ?? ""
            )
            let envelope = ContextEnvelope(
                selectedText: snapshot.selectedText,
                authorizedDocumentExcerpt: localContext,
                hostDocumentTitle: paperTitle
            )
            let presentation = InteractionPresentation(
                lenses: lenses,
                selectedLens: lens,
                usesPaperContext: paperTitle != nil,
                localSourceName: localSourceName,
                localContextFallback: localContextFallback,
                model: model,
                allowsFollowUp: lens.allowsFollowUp
            )
            self?.run(action, envelope: envelope, presentation: presentation)
        }
        let selectCurrentAction: (ReaderAction) -> Void = { [weak self] action in
            guard let self else { return }
            switch action {
            case let .lens(lens):
                self.captureForLensSelection(lens)
            case let .package(resolvedAction):
                self.runTranslateAction(
                    resolvedAction,
                    selection: snapshot.selectedText,
                    model: model,
                    presentation: InteractionPresentation(
                        actions: actionOptions.map(\.action),
                        selectedAction: action,
                        usesPaperContext: false,
                        model: model
                    )
                )
            }
        }
        let submitQuestion: (String) -> Void = { [weak self] question in
            self?.overlayController.setUserQuestionText(question)
            let request = InteractionRequest.userQuestionOnPassage(
                passage: snapshot.selectedText,
                paperTitle: paperTitle,
                localContext: localContext,
                question: question
            )
            let presentation = InteractionPresentation(
                lenses: lenses,
                selectedLens: nil,
                usesPaperContext: paperTitle != nil,
                localSourceName: localSourceName,
                localContextFallback: localContextFallback,
                model: model,
                allowsFollowUp: true
            )
            self?.run(request, presentation: presentation)
        }
        let hasSelection = !snapshot.selectedText.isEmpty
        if hasSelection, tutorialDemo {
            activeSelectedLens = nil
            overlayController.presentLensSelection(
                lenses: lenses,
                usesPaperContext: paperTitle != nil,
                localSourceName: localSourceName,
                localContextFallback: localContextFallback,
                model: model,
                selectionPreviewText: snapshot.selectedText,
                hostBundleIdentifier: hostBundleIdentifier,
                actionOptions: actionOptions,
                onActionSelected: selectCurrentAction,
                onQuestionSubmitted: submitQuestion
            )
        } else if hasSelection, let selectedLens {
            if repositionsOverlay {
                overlayController.presentRequest(
                    lenses: lenses,
                    selectedLens: selectedLens,
                    usesPaperContext: paperTitle != nil,
                    localSourceName: localSourceName,
                    localContextFallback: localContextFallback,
                    model: model,
                    selectionPreviewText: snapshot.selectedText,
                    hostBundleIdentifier: hostBundleIdentifier,
                    actionOptions: actionOptions,
                    onActionSelected: selectCurrentAction,
                    onQuestionSubmitted: submitQuestion
                )
                startRequest(selectedLens)
            } else if overlayController.updateVisibleRequest(
                lenses: lenses,
                selectedLens: selectedLens,
                usesPaperContext: paperTitle != nil,
                localSourceName: localSourceName,
                localContextFallback: localContextFallback,
                model: model,
                selectionPreviewText: snapshot.selectedText,
                actionOptions: actionOptions,
                onActionSelected: selectCurrentAction,
                onQuestionSubmitted: submitQuestion
            ) {
                startRequest(selectedLens)
            }
        } else if hasSelection, let defaultAction {
            let defaultLens: ExplanationLens?
            if case let .lens(lens) = defaultAction {
                defaultLens = lens
            } else {
                defaultLens = nil
            }
            overlayController.presentRequest(
                lenses: lenses,
                selectedLens: defaultLens,
                selectedAction: defaultAction,
                usesPaperContext: paperTitle != nil,
                localSourceName: localSourceName,
                localContextFallback: localContextFallback,
                model: model,
                selectionPreviewText: snapshot.selectedText,
                hostBundleIdentifier: hostBundleIdentifier,
                actionOptions: actionOptions,
                onActionSelected: selectCurrentAction,
                onQuestionSubmitted: submitQuestion
            )
            switch defaultAction {
            case let .lens(lens):
                startRequest(lens)
            case let .package(resolvedAction):
                runTranslateAction(
                    resolvedAction,
                    selection: snapshot.selectedText,
                    model: model,
                    presentation: InteractionPresentation(
                        actions: actionOptions.map(\.action),
                        selectedAction: defaultAction,
                        usesPaperContext: false,
                        model: model
                    )
                )
            }
        } else if hasSelection {
            overlayController.presentLensSelection(
                lenses: lenses,
                usesPaperContext: paperTitle != nil,
                localSourceName: localSourceName,
                localContextFallback: localContextFallback,
                model: model,
                selectionPreviewText: snapshot.selectedText,
                hostBundleIdentifier: hostBundleIdentifier,
                actionOptions: actionOptions,
                onActionSelected: selectCurrentAction,
                onQuestionSubmitted: submitQuestion
            )
        } else {
            let submitFreeformQuestion: (String) -> Void = { [weak self] question in
                self?.overlayController.setUserQuestionText(question)
                let presentation = InteractionPresentation(
                    lenses: [],
                    selectedLens: nil,
                    usesPaperContext: false,
                    localSourceName: nil,
                    localContextFallback: .none,
                    model: model,
                    allowsFollowUp: true
                )
                self?.run(.freeformQuestion(question: question), presentation: presentation)
            }
            overlayController.presentLensSelection(
                lenses: [],
                usesPaperContext: false,
                model: model,
                selectionPreviewText: "",
                hostBundleIdentifier: hostBundleIdentifier,
                onQuestionSubmitted: submitFreeformQuestion
            )
        }
    }

    private func makeTranslateCoordinator() -> TranslateActionCoordinator? {
        guard let composition = try? CapabilityRuntimeComposition(
            credentialStore: KeychainCredentialStore(),
            transport: URLSessionDeepLTransport(),
            directories: ActionPackageDirectories.production(),
            runtimeVersion: SemanticVersion(1, 0, 0),
            allowedNetworkHosts: [DeepLEndpoint.free.host],
            endpoint: .free
        ) else {
            return nil
        }
        return TranslateActionCoordinator(
            composition: composition,
            modelClient: actionModelClient
        )
    }

    private func runTranslateAction(
        _ action: ResolvedAction,
        selection: String,
        model: String,
        presentation: InteractionPresentation
    ) {
        guard action.id == TranslateActionCoordinator.actionID else { return }
        cancelActiveRequest()
        let requestID = UUID()
        activeRequestID = requestID
        overlayController.setFailureActions([])
        overlayController.setFailureStatus(nil)
        overlayController.setFirstRequestLoadingHint(false)
        overlayController.show(presentation.requesting())

        guard let coordinator = makeTranslateCoordinator() else {
            overlayController.setFirstRequestLoadingHint(false)
            overlayController.show(presentation.failure("Translate with DeepL is unavailable."))
            return
        }

        let targetLanguage = translateSettings.targetLanguageCode
        let grants = translateSettings.permissionGrants()
        activeRequestTask = Task { [weak self] in
            let result = await coordinator.execute(
                selection: selection,
                sourceLanguage: nil,
                targetLanguage: targetLanguage,
                model: model,
                grants: grants
            )
            guard let self, self.activeRequestID == requestID else { return }
            self.overlayController.setFirstRequestLoadingHint(false)
            switch result {
            case let .failure(error):
                self.overlayController.show(
                    presentation.failure(TranslateActionUserMessage.coordinatorFailure(error))
                )
            case let .success(outcome):
                switch outcome.result {
                case let .success(answer):
                    self.overlayController.show(presentation.answer(answer))
                case .failure(.cancelled):
                    return
                case let .failure(failure):
                    guard let message = TranslateActionUserMessage.runtimeFailure(failure) else {
                        return
                    }
                    self.overlayController.show(presentation.failure(message))
                }
            }
        }
    }

    private func run(
        _ action: ResolvedAction,
        envelope: ContextEnvelope,
        presentation: InteractionPresentation
    ) {
        cancelActiveRequest()
        let requestID = UUID()
        activeRequestID = requestID
        streamingAnswer = ""
        overlayController.setFollowUpFrame(presentation.followUpFrame)
        overlayController.setFailureActions([])
        overlayController.setFailureStatus(nil)
        let isFirstModelRequest = !hasIssuedModelRequest
        hasIssuedModelRequest = true
        overlayController.setFirstRequestLoadingHint(isFirstModelRequest)
        overlayController.show(presentation.requesting())
        let runtime = ActionWorkflowRuntime(modelClient: actionModelClient)
        activeRequestTask = Task { [weak self] in
            let outcome = await runtime.execute(
                action: action,
                envelope: envelope,
                model: presentation.model,
                onEvent: { [weak self] event in
                    guard case let .outputFragment(fragment) = event else { return }
                    await self?.receiveStreamEvent(
                        .fragment(fragment),
                        requestID: requestID,
                        presentation: presentation
                    )
                }
            )
            guard self?.activeRequestID == requestID else { return }
            switch outcome.result {
            case .success(let finalAnswer):
                self?.overlayController.setFirstRequestLoadingHint(false)
                if let continuation = outcome.continuation {
                    self?.wireFollowUp(
                        priorTurn: continuation.messages(answer: finalAnswer),
                        presentation: presentation
                    )
                } else {
                    self?.overlayController.setOnQuestionSubmitted(nil)
                }
                self?.overlayController.show(presentation.answer(finalAnswer))
            case .failure(.cancelled):
                break
            case .failure(let runtimeFailure):
                let failure: ChatFailure
                switch runtimeFailure {
                case .model(let modelFailure):
                    failure = modelFailure
                case .capability(.cancelled):
                    return
                case .capability:
                    failure = .invalidResponse
                case .missingRequiredSelection, .strategyUnavailable:
                    failure = .invalidResponse
                case .cancelled:
                    return
                }
                self?.overlayController.setFirstRequestLoadingHint(false)
                let retry = OverlayFailureAction(id: "retry", title: "Retry") { [weak self] in
                    self?.run(action, envelope: envelope, presentation: presentation)
                }
                var actions: [OverlayFailureAction] = []
                if case .unavailable = failure {
                    actions = [self?.makeStartOllamaAction(retry: retry) ?? retry]
                } else {
                    actions = [retry]
                }
                self?.overlayController.setFailureActions(actions)
                self?.overlayController.setOnQuestionSubmitted(nil)
                self?.overlayController.show(presentation.failure(failure.message))
            }
        }
    }

    private func run(_ request: InteractionRequest, presentation: InteractionPresentation) {
        cancelActiveRequest()
        let requestID = UUID()
        activeRequestID = requestID
        streamingAnswer = ""
        let messages = request.messages
        overlayController.setFollowUpFrame(presentation.followUpFrame)
        overlayController.setFailureActions([])
        overlayController.setFailureStatus(nil)
        let isFirstModelRequest = !hasIssuedModelRequest
        hasIssuedModelRequest = true
        overlayController.setFirstRequestLoadingHint(isFirstModelRequest)
        overlayController.show(presentation.requesting())
        let modelClient = actionModelClient
        activeRequestTask = Task { [weak self] in
            let result = await modelClient.streamChat(
                model: presentation.model,
                messages: messages,
                onEvent: { [weak self] event in
                    await self?.receiveStreamEvent(
                        event,
                        requestID: requestID,
                        presentation: presentation
                    )
                }
            )
            guard self?.activeRequestID == requestID else { return }
            switch result {
            case .success:
                self?.overlayController.setFirstRequestLoadingHint(false)
                let finalAnswer = self?.streamingAnswer ?? ""
                self?.wireFollowUp(
                    priorTurn: messages + [ChatMessage(role: .assistant, content: finalAnswer)],
                    presentation: presentation
                )
                self?.overlayController.show(presentation.answer(finalAnswer))
            case .failure(.cancelled):
                break
            case .failure(let failure):
                self?.overlayController.setFirstRequestLoadingHint(false)
                let retry = OverlayFailureAction(id: "retry", title: "Retry") { [weak self] in
                    self?.run(request, presentation: presentation)
                }
                var actions: [OverlayFailureAction] = []
                if case .unavailable = failure {
                    actions = [makeStartOllamaAction(retry: retry)]
                } else {
                    actions = [retry]
                }
                self?.overlayController.setFailureActions(actions)
                self?.overlayController.setOnQuestionSubmitted(nil)
                self?.overlayController.show(presentation.failure(failure.message))
            }
        }
    }

    private func makeStartOllamaAction(retry: OverlayFailureAction) -> OverlayFailureAction {
        OverlayFailureAction(id: "start-ollama", title: "Start Ollama") { [weak self] in
            self?.startOllama(
                onReady: { [weak self] in
                    self?.overlayController.setFailureActions([retry])
                },
                onFailure: { [weak self] in
                    guard let self else { return }
                    self.overlayController.setFailureActions([
                        self.makeStartOllamaAction(retry: retry)
                    ])
                }
            )
        }
    }

    private func wireFollowUp(
        priorTurn: [ChatMessage],
        presentation: InteractionPresentation
    ) {
        if presentation.allowsFollowUp {
            let priorAnswer = priorTurn.last(where: { $0.role == .assistant })?.content ?? ""
            overlayController.setOnQuestionSubmitted(
                makeFollowUpSubmit(
                    prior: priorTurn,
                    priorAnswer: priorAnswer,
                    base: presentation
                )
            )
        } else {
            overlayController.setOnQuestionSubmitted(nil)
        }
    }

    private func makeFollowUpSubmit(
        prior: [ChatMessage],
        priorAnswer: String,
        base: InteractionPresentation
    ) -> (String) -> Void {
        { [weak self] question in
            guard let self else { return }
            // Header slot keeps showing turn 1's question / lens name; the
            // follow-up question renders between the two answer boxes via
            // the followUpFrame.
            let followUpPresentation = InteractionPresentation(
                lenses: base.lenses,
                selectedLens: base.selectedLens,
                usesPaperContext: base.usesPaperContext,
                localSourceName: base.localSourceName,
                localContextFallback: base.localContextFallback,
                model: base.model,
                allowsFollowUp: false,
                followUpFrame: FollowUpFrame(
                    priorAnswer: priorAnswer,
                    currentQuestion: question
                )
            )
            self.run(
                .followUp(prior: prior, question: question),
                presentation: followUpPresentation
            )
        }
    }

    private func cancelActiveRequest() {
        activeRequestID = nil
        activeRequestTask?.cancel()
        activeRequestTask = nil
        streamingAnswer = ""
        overlayController.setFirstRequestLoadingHint(false)
    }

    private func clearActivePresentation() {
        activeSnapshot = nil
        activeSelectedLens = nil
    }

    private func receiveStreamEvent(
        _ event: ChatStreamEvent,
        requestID: UUID,
        presentation: InteractionPresentation
    ) {
        guard activeRequestID == requestID else { return }
        guard case let .fragment(fragment) = event else { return }
        overlayController.setFirstRequestLoadingHint(false)
        streamingAnswer += fragment
        overlayController.show(presentation.streaming(streamingAnswer))
    }
}
