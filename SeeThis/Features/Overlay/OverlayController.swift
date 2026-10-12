import AppKit

struct OverlayPresentationState: Equatable {
    private(set) var isVisible = false

    mutating func beginPresentation() -> Bool {
        guard !isVisible else { return false }
        isVisible = true
        return true
    }

    mutating func endPresentation() -> Bool {
        guard isVisible else { return false }
        isVisible = false
        return true
    }
}

@MainActor
final class OverlayController {
    private let panel: ReadingOverlayPanel
    private let escapeMonitor = TemporaryEscapeHotKeyMonitor()
    private var presentationState = OverlayPresentationState()
    private var currentContent: OverlayContentState?
    private var selectionPreviewText: String?
    private var userQuestionText: String?
    private var followUpFrame: FollowUpFrame?
    private var onActionSelected: ((ReaderAction) -> Void)?
    private var visibleActionOptions: [ReaderActionOption]?
    private var selectedActionOverride: ReaderAction?
    private var onQuestionSubmitted: ((String) -> Void)?
    private var onDismiss: (() -> Void)?
    private var onFileDropped: ((URL) -> Void)?
    private var showsTutorialLensHint = false
    private var showsTutorialDismissHint = false
    private var showsFirstRequestLoadingHint = false
    private var failureActions: [OverlayFailureAction] = []
    private var failureStatusMessage: String?
    private(set) var activeHostBundleIdentifier: String?

    init(panel: ReadingOverlayPanel? = nil) {
        self.panel = panel ?? ReadingOverlayPanel()
        NotificationCenter.default.addObserver(
            forName: .seeThisSettingsWindowRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    func setOnDismiss(_ onDismiss: (() -> Void)?) {
        self.onDismiss = onDismiss
    }

    func setOnFileDropped(_ onFileDropped: ((URL) -> Void)?) {
        self.onFileDropped = onFileDropped
    }

    func setTutorialLensHint(_ isEnabled: Bool) {
        guard showsTutorialLensHint != isEnabled else { return }
        showsTutorialLensHint = isEnabled
        if let currentContent {
            show(currentContent)
        }
    }

    func setTutorialDismissHint(_ isEnabled: Bool) {
        guard showsTutorialDismissHint != isEnabled else { return }
        showsTutorialDismissHint = isEnabled
        if let currentContent {
            show(currentContent)
        }
    }

    func setFirstRequestLoadingHint(_ isEnabled: Bool) {
        guard showsFirstRequestLoadingHint != isEnabled else { return }
        showsFirstRequestLoadingHint = isEnabled
        if let currentContent {
            show(currentContent)
        }
    }

    func setFailureActions(_ actions: [OverlayFailureAction]) {
        failureActions = actions
        if let currentContent {
            show(currentContent)
        }
    }

    func setFailureStatus(_ message: String?) {
        failureStatusMessage = message
        if let currentContent {
            show(currentContent)
        }
    }

    func showSelectionLost(onRetry: @escaping () -> Void) {
        guard let currentContent else { return }
        selectionPreviewText = nil
        setFailureActions([
            OverlayFailureAction(id: "retry-selection", title: "Retry", perform: onRetry)
        ])
        setFailureStatus(nil)
        show(currentContent.replacingFailureMessage(
            "Selection is no longer available. Select text again, then click Retry."
        ))
    }

    func presentNotice(_ message: String, actions: [OverlayFailureAction] = []) {
        onActionSelected = nil
        onQuestionSubmitted = nil
        visibleActionOptions = nil
        selectedActionOverride = nil
        selectionPreviewText = nil
        userQuestionText = nil
        followUpFrame = nil
        activeHostBundleIdentifier = nil
        failureActions = actions
        failureStatusMessage = nil
        present(.failure(message), atMouseLocation: NSEvent.mouseLocation)
    }

    func presentRequest(
        lenses: [ExplanationLens] = [],
        selectedLens: ExplanationLens? = nil,
        selectedAction: ReaderAction? = nil,
        usesPaperContext: Bool,
        localSourceName: String? = nil,
        localContextFallback: LocalContextFallback = .none,
        model: String,
        selectionPreviewText: String,
        hostBundleIdentifier: String? = nil,
        actionOptions: [ReaderActionOption]? = nil,
        onActionSelected: ((ReaderAction) -> Void)? = nil,
        onLensSelected: ((ExplanationLens) -> Void)? = nil,
        onQuestionSubmitted: ((String) -> Void)? = nil
    ) {
        self.onActionSelected = onActionSelected ?? actionHandler(for: onLensSelected)
        self.onQuestionSubmitted = onQuestionSubmitted
        self.visibleActionOptions = actionOptions
        self.selectedActionOverride = selectedAction ?? selectedLens.map(ReaderAction.lens)
        self.selectionPreviewText = selectionPreviewText
        self.userQuestionText = nil
        self.followUpFrame = nil
        self.activeHostBundleIdentifier = hostBundleIdentifier
        present(
            .requesting(
                lenses: lenses,
                selectedLens: selectedLens,
                usesPaperContext: usesPaperContext,
                localSourceName: localSourceName,
                localContextFallback: localContextFallback,
                model: model
            ),
            atMouseLocation: NSEvent.mouseLocation
        )
    }

    func presentLensSelection(
        lenses: [ExplanationLens],
        usesPaperContext: Bool,
        localSourceName: String? = nil,
        localContextFallback: LocalContextFallback = .none,
        model: String,
        selectionPreviewText: String,
        hostBundleIdentifier: String? = nil,
        actionOptions: [ReaderActionOption]? = nil,
        onActionSelected: ((ReaderAction) -> Void)? = nil,
        onLensSelected: ((ExplanationLens) -> Void)? = nil,
        onQuestionSubmitted: ((String) -> Void)? = nil
    ) {
        self.onActionSelected = onActionSelected ?? actionHandler(for: onLensSelected)
        self.onQuestionSubmitted = onQuestionSubmitted
        self.visibleActionOptions = actionOptions
        self.selectedActionOverride = nil
        self.selectionPreviewText = selectionPreviewText
        self.userQuestionText = nil
        self.followUpFrame = nil
        self.activeHostBundleIdentifier = hostBundleIdentifier
        present(
            .choosingLens(
                lenses: lenses,
                usesPaperContext: usesPaperContext,
                localSourceName: localSourceName,
                localContextFallback: localContextFallback,
                model: model
            ),
            atMouseLocation: NSEvent.mouseLocation
        )
    }

    #if DEBUG
    func presentPreview(
        answer: String,
        model: String,
        selectionPreviewText: String
    ) {
        self.selectionPreviewText = selectionPreviewText
        onActionSelected = nil
        present(
            .answer(answer, usesPaperContext: false, model: model),
            atMouseLocation: NSEvent.mouseLocation
        )
    }
    #endif

    func updateVisibleRequest(
        lenses: [ExplanationLens],
        selectedLens: ExplanationLens,
        usesPaperContext: Bool,
        localSourceName: String? = nil,
        localContextFallback: LocalContextFallback = .none,
        model: String,
        selectionPreviewText: String,
        actionOptions: [ReaderActionOption]? = nil,
        onActionSelected: ((ReaderAction) -> Void)? = nil,
        onLensSelected: ((ExplanationLens) -> Void)? = nil,
        onQuestionSubmitted: ((String) -> Void)? = nil
    ) -> Bool {
        guard presentationState.isVisible else { return false }
        self.onActionSelected = onActionSelected ?? actionHandler(for: onLensSelected)
        self.onQuestionSubmitted = onQuestionSubmitted
        self.visibleActionOptions = actionOptions
        self.selectedActionOverride = .lens(selectedLens)
        self.selectionPreviewText = selectionPreviewText
        self.userQuestionText = nil
        self.followUpFrame = nil
        show(
            .requesting(
                lenses: lenses,
                selectedLens: selectedLens,
                usesPaperContext: usesPaperContext,
                localSourceName: localSourceName,
                localContextFallback: localContextFallback,
                model: model
            )
        )
        return true
    }

    func show(_ content: OverlayContentState) {
        guard presentationState.isVisible else { return }
        currentContent = content
        resizeVisiblePanel(for: content)
        panel.setContent(
            content,
            selectionPreviewText: selectionPreviewText,
            userQuestionText: userQuestionText,
            followUpFrame: followUpFrame,
            showsTutorialLensHint: showsTutorialLensHint,
            showsTutorialDismissHint: showsTutorialDismissHint,
            showsFirstRequestLoadingHint: showsFirstRequestLoadingHint,
            failureActions: failureActions,
            failureStatusMessage: failureStatusMessage,
            actionOptions: visibleActionOptions,
            selectedAction: selectedActionOverride,
            onActionSelected: { [weak self] action in
                self?.selectAction(action)
            },
            onQuestionSubmitted: forwardedQuestionHandler,
            onFileDropped: { [weak self] url in
                self?.onFileDropped?(url)
            }
        )
    }

    func setUserQuestionText(_ text: String?) {
        userQuestionText = text
        if let currentContent { show(currentContent) }
    }

    func setFollowUpFrame(_ frame: FollowUpFrame?) {
        followUpFrame = frame
        if let currentContent { show(currentContent) }
    }

    func setOnQuestionSubmitted(_ handler: ((String) -> Void)?) {
        onQuestionSubmitted = handler
        if let currentContent { show(currentContent) }
    }

    private var forwardedQuestionHandler: ((String) -> Void)? {
        onQuestionSubmitted == nil
            ? nil
            : { [weak self] question in self?.onQuestionSubmitted?(question) }
    }

    func refreshVisibleLenses(_ lenses: [ExplanationLens]) {
        guard let currentContent else { return }
        show(currentContent.refreshingLenses(lenses))
    }

    func refreshVisibleActions(_ options: [ReaderActionOption]) {
        guard let currentContent else { return }
        visibleActionOptions = options
        let visibleIDs = Set(options.map(\.id))
        if let selectedActionOverride, !visibleIDs.contains(selectedActionOverride.id) {
            self.selectedActionOverride = nil
        }
        let lenses = options.compactMap { option -> ExplanationLens? in
            guard case let .lens(lens) = option.action else { return nil }
            return lens
        }
        show(currentContent.refreshingLenses(lenses))
    }

    func resizeVisiblePanel(for content: OverlayContentState) {
        guard content.isScrollableAnswer else { return }
        let currentFrame = panel.frame
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(currentFrame) }) else { return }
        let desiredHeight = min(
            content.preferredPanelSize(
                selectionPreviewIsVisible: selectionPreviewText?.isEmpty == false,
                followUpFrame: followUpFrame,
                showsTutorialLensHint: showsTutorialLensHint,
                actionOptions: visibleActionOptions
            ).height,
            currentFrame.maxY - screen.visibleFrame.minY
        )
        guard desiredHeight > currentFrame.height else { return }
        panel.setFrame(
            CGRect(
                x: currentFrame.minX,
                y: currentFrame.maxY - desiredHeight,
                width: currentFrame.width,
                height: desiredHeight
            ),
            display: false
        )
    }

    private func present(
        _ content: OverlayContentState,
        atMouseLocation mouseLocation: CGPoint,
        onLensSelected: ((ExplanationLens) -> Void)? = nil
    ) {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
        guard let screen else {
            dismiss()
            return
        }
        let overlayFrame = OverlayPlacement.frame(
            atMouseLocation: mouseLocation,
            in: screen.visibleFrame,
            panelSize: content.preferredPanelSize(
                selectionPreviewIsVisible: selectionPreviewText?.isEmpty == false,
                followUpFrame: followUpFrame,
                showsTutorialLensHint: showsTutorialLensHint,
                actionOptions: visibleActionOptions
            )
        )

        if presentationState.beginPresentation() {
            guard escapeMonitor.start(onEscape: { [weak self] in
                self?.dismiss()
            }) else {
                _ = presentationState.endPresentation()
                return
            }
        }

        currentContent = content
        panel.update(
            content,
            selectionPreviewText: selectionPreviewText,
            userQuestionText: userQuestionText,
            followUpFrame: followUpFrame,
            showsTutorialLensHint: showsTutorialLensHint,
            showsTutorialDismissHint: showsTutorialDismissHint,
            showsFirstRequestLoadingHint: showsFirstRequestLoadingHint,
            failureActions: failureActions,
            failureStatusMessage: failureStatusMessage,
            frame: overlayFrame,
            actionOptions: visibleActionOptions,
            selectedAction: selectedActionOverride,
            onActionSelected: { [weak self] action in
                self?.selectAction(action)
            },
            onQuestionSubmitted: forwardedQuestionHandler,
            onFileDropped: { [weak self] url in
                self?.onFileDropped?(url)
            }
        )
        panel.orderFrontRegardless()
    }

    func dismiss() {
        panel.orderOut(nil)
        currentContent = nil
        selectionPreviewText = nil
        userQuestionText = nil
        followUpFrame = nil
        onActionSelected = nil
        visibleActionOptions = nil
        selectedActionOverride = nil
        onQuestionSubmitted = nil
        activeHostBundleIdentifier = nil
        showsTutorialLensHint = false
        showsTutorialDismissHint = false
        showsFirstRequestLoadingHint = false
        failureActions = []
        failureStatusMessage = nil
        onDismiss?()
        if presentationState.endPresentation() {
            escapeMonitor.stop()
        }
    }

    func updateLocalSourceName(_ name: String?) {
        guard let currentContent else { return }
        show(currentContent.replacingLocalSourceName(name))
    }

    private func actionHandler(
        for lensHandler: ((ExplanationLens) -> Void)?
    ) -> ((ReaderAction) -> Void)? {
        lensHandler.map { handler in
            { action in
                guard case let .lens(lens) = action else { return }
                handler(lens)
            }
        }
    }

    private func selectAction(_ action: ReaderAction) {
        let isLensStateTransition = currentContent?.requestingContent(for: action) != nil
        let isEnabledPackage = visibleActionOptions?.contains {
            $0.id == action.id && $0.isEnabled
        } == true
        guard isLensStateTransition || isEnabledPackage else { return }
        selectedActionOverride = action
        onActionSelected?(action)
    }
}
