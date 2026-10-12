import AppKit
import SwiftUI

final class ReadingOverlayPanel: NSPanel {
    private var hostingView: NSHostingView<OverlayContent>?
    private var onFileDropped: ((URL) -> Void)?

    init() {
        super.init(
            contentRect: CGRect(origin: .zero, size: OverlayPlacement.panelSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        setContent(.requesting(usesPaperContext: false))
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func setContent(
        _ content: OverlayContentState,
        selectionPreviewText: String? = nil,
        userQuestionText: String? = nil,
        followUpFrame: FollowUpFrame? = nil,
        showsTutorialLensHint: Bool = false,
        showsTutorialDismissHint: Bool = false,
        showsFirstRequestLoadingHint: Bool = false,
        failureActions: [OverlayFailureAction] = [],
        failureStatusMessage: String? = nil,
        actionOptions: [ReaderActionOption]? = nil,
        selectedAction: ReaderAction? = nil,
        onActionSelected: ((ReaderAction) -> Void)? = nil,
        onQuestionSubmitted: ((String) -> Void)? = nil,
        onFileDropped: ((URL) -> Void)? = nil
    ) {
        self.onFileDropped = onFileDropped
        let rootView = OverlayContent(
            content: content,
            selectionPreviewText: selectionPreviewText,
            userQuestionText: userQuestionText,
            followUpFrame: followUpFrame,
            showsTutorialLensHint: showsTutorialLensHint,
            showsTutorialDismissHint: showsTutorialDismissHint,
            showsFirstRequestLoadingHint: showsFirstRequestLoadingHint,
            failureActions: failureActions,
            failureStatusMessage: failureStatusMessage,
            actionOptionsOverride: actionOptions,
            selectedActionOverride: selectedAction,
            onActionSelected: onActionSelected,
            onQuestionSubmitted: onQuestionSubmitted,
            onFileDropped: onFileDropped
        )
        if let hostingView {
            hostingView.rootView = rootView
        } else {
            let hostingView = NSHostingView(rootView: rootView)
            self.hostingView = hostingView
            contentView = hostingView
        }
    }

    func update(
        _ content: OverlayContentState,
        selectionPreviewText: String? = nil,
        userQuestionText: String? = nil,
        followUpFrame: FollowUpFrame? = nil,
        showsTutorialLensHint: Bool = false,
        showsTutorialDismissHint: Bool = false,
        showsFirstRequestLoadingHint: Bool = false,
        failureActions: [OverlayFailureAction] = [],
        failureStatusMessage: String? = nil,
        frame: CGRect,
        actionOptions: [ReaderActionOption]? = nil,
        selectedAction: ReaderAction? = nil,
        onActionSelected: ((ReaderAction) -> Void)? = nil,
        onQuestionSubmitted: ((String) -> Void)? = nil,
        onFileDropped: ((URL) -> Void)? = nil
    ) {
        setFrame(frame, display: false)
        setContent(
            content,
            selectionPreviewText: selectionPreviewText,
            userQuestionText: userQuestionText,
            followUpFrame: followUpFrame,
            showsTutorialLensHint: showsTutorialLensHint,
            showsTutorialDismissHint: showsTutorialDismissHint,
            showsFirstRequestLoadingHint: showsFirstRequestLoadingHint,
            failureActions: failureActions,
            failureStatusMessage: failureStatusMessage,
            actionOptions: actionOptions,
            selectedAction: selectedAction,
            onActionSelected: onActionSelected,
            onQuestionSubmitted: onQuestionSubmitted,
            onFileDropped: onFileDropped
        )
        displayIfNeeded()
    }
}
