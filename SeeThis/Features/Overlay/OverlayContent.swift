import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum OverlayPanelAppearance {
    static let cornerRadius: CGFloat = 12
}

enum OverlayActivityStatusPlacement: Equatable {
    case modelLabelTrailing

    static let current = Self.modelLabelTrailing
    static let footerContainsActivityStatus = false
}

enum OverlayActivityStatusTypography: Equatable {
    case callout

    static let current = Self.callout

    var font: Font {
        switch self {
        case .callout:
            .callout
        }
    }
}

enum OverlayActivityIndicatorLayout {
    static let baseSideLength: CGFloat = 14
    static let scalesWithBodyFont = true
    static let visualScale: CGFloat = 0.72
}

enum OverlayActivityStatusLayout {
    static let modelToStatusSpacing: CGFloat = 6
    static let indicatorToLabelSpacing: CGFloat = 2
    static let groupVerticalOffset: CGFloat = 1
}

enum AnswerCopyFeedback: Equatable {
    case ready
    case copied

    static let displayDurationNanoseconds: UInt64 = 1_000_000_000

    var label: String {
        self == .copied ? "Copied" : "Copy"
    }

    mutating func markCopied() {
        self = .copied
    }

    mutating func reset() {
        self = .ready
    }
}

enum OverlaySelectionPreviewLayout {
    static let maximumLineCount = 1
    static let leadingRuleHeight: CGFloat = 20
    static let allowsTextSelection = false
}

enum OverlayFooterLayout {
    static let rowHeight: CGFloat = 24
}

struct OverlayContent: View {
    let content: OverlayContentState
    let selectionPreviewText: String?
    let userQuestionText: String?
    let followUpFrame: FollowUpFrame?
    let showsTutorialLensHint: Bool
    let showsTutorialDismissHint: Bool
    let showsFirstRequestLoadingHint: Bool
    let failureActions: [OverlayFailureAction]
    let failureStatusMessage: String?
    let actionOptionsOverride: [ReaderActionOption]?
    let selectedActionOverride: ReaderAction?
    let onActionSelected: ((ReaderAction) -> Void)?
    let onQuestionSubmitted: ((String) -> Void)?
    let onFileDropped: ((URL) -> Void)?
    @State private var copyFeedback = AnswerCopyFeedback.ready
    @State private var copyFeedbackToken: UUID?
    @State private var followsLatestStreamingContent = true
    @State private var hasUnreadStreamingContent = false
    @State private var hoveredAction: ReaderAction?
    @State private var isCopyButtonHovered = false
    @State private var isFileDropTargeted = false
    @State private var questionDraft = ""
    @State private var isTutorialLensPulseActive = false
    @State private var hoveredFailureActionID: String?
    @ScaledMetric(relativeTo: .body)
    private var activityIndicatorSideLength = OverlayActivityIndicatorLayout.baseSideLength

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: OverlayActivityStatusLayout.modelToStatusSpacing) {
                Text(content.modelLabel)
                    .font(.body)
                if let activityStatusLabel = content.activityStatusLabel(
                    for: selectedActionOverride ?? content.selectedAction
                ),
                   !showsFirstRequestLoadingHint || !content.isRequesting {
                    HStack(spacing: OverlayActivityStatusLayout.indicatorToLabelSpacing) {
                        ProgressView()
                            .controlSize(.small)
                            .frame(
                                width: activityIndicatorSideLength,
                                height: activityIndicatorSideLength
                            )
                            .scaleEffect(OverlayActivityIndicatorLayout.visualScale)
                        Text(activityStatusLabel)
                            .font(OverlayActivityStatusTypography.current.font)
                            .foregroundStyle(.secondary)
                    }
                    .offset(y: OverlayActivityStatusLayout.groupVerticalOffset)
                }
                if showsFirstRequestLoadingHint && content.isRequesting {
                    HStack(spacing: OverlayActivityStatusLayout.indicatorToLabelSpacing) {
                        ProgressView()
                            .controlSize(.small)
                            .frame(
                                width: activityIndicatorSideLength,
                                height: activityIndicatorSideLength
                            )
                            .scaleEffect(OverlayActivityIndicatorLayout.visualScale)
                        Text(OverlayActivityStatusText.loadingModel)
                            .font(OverlayActivityStatusTypography.current.font)
                            .foregroundStyle(.secondary)
                    }
                    .offset(y: OverlayActivityStatusLayout.groupVerticalOffset)
                }
                Spacer(minLength: 8)
                if showsTutorialDismissHint && content.answerText != nil {
                    TutorialDismissArrow()
                }
                HStack(spacing: 4) {
                    Text("Press")
                    Text("esc")
                        .font(.caption.monospaced())
                        .frame(minWidth: 22, alignment: .center)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 0.5)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                        )
                    Text("to dismiss")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            if let selectionPreviewText, !selectionPreviewText.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(
                            width: 2,
                            height: OverlaySelectionPreviewLayout.leadingRuleHeight
                        )
                    Text(selectionPreviewText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(OverlaySelectionPreviewLayout.maximumLineCount)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 2)
            }
            if let contextTagName = content.contextTagName {
                HStack(spacing: 6) {
                    Text("Context:")
                        .font(ContextTagTypography.label.font)
                        .foregroundStyle(.secondary)
                    ContextTag(name: contextTagName)
                }
            }
            if let selectedActionDisplayName = content.selectedActionDisplayName
                ?? selectedActionOverride?.display.name {
                Text(selectedActionDisplayName)
                    .font(LensStatusTypography.current.font)
                    .foregroundStyle(.secondary)
            } else if showsSubmittedQuestion, let userQuestionText {
                Text(userQuestionText)
                    .font(LensStatusTypography.current.font)
                    .foregroundStyle(.secondary)
            }
            if let followUpFrame {
                priorAnswerBox(text: followUpFrame.priorAnswer)
                Text(followUpFrame.currentQuestion)
                    .font(LensStatusTypography.current.font)
                    .foregroundStyle(.secondary)
            }
            if let answer = content.answerText {
                NativeMarkdownAnswer(
                    text: OverlayMarkdownRenderer.nativeText(for: answer),
                    followsLatestContent: followsLatestStreamingContent,
                    onUserScroll: {
                        guard content.isStreaming else { return }
                        followsLatestStreamingContent = false
                        hasUnreadStreamingContent = true
                    }
                )
                    .frame(maxHeight: .infinity)
                    .background(
                        Color.primary.opacity(OverlayMarkdownAppearance.answerBackgroundOpacity),
                        in: RoundedRectangle(
                            cornerRadius: OverlayMarkdownAppearance.answerCornerRadius,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: OverlayMarkdownAppearance.answerCornerRadius,
                            style: .continuous
                        )
                        .stroke(
                            Color.primary.opacity(OverlayMarkdownAppearance.answerBorderOpacity),
                            lineWidth: 1
                        )
                    }
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: OverlayMarkdownAppearance.answerCornerRadius,
                            style: .continuous
                        )
                    )
                    .onChange(of: answer) { _, _ in
                        guard content.isStreaming, !followsLatestStreamingContent else { return }
                        hasUnreadStreamingContent = true
                    }
                    .onChange(of: content.isStreaming) { _, isStreaming in
                        if !isStreaming { hasUnreadStreamingContent = false }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if hasUnreadStreamingContent {
                            Button("New content") {
                                followsLatestStreamingContent = true
                                hasUnreadStreamingContent = false
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
            } else {
                switch content {
                case .choosingLens:
                    if !showsQuestionField {
                        Text("Choose an explanation lens")
                    }
                case .requesting, .streaming:
                    EmptyView()
                case .failure(let message, _, _, _):
                    VStack(alignment: .leading, spacing: 8) {
                        Text(failureStatusMessage ?? message)
                            .foregroundStyle(.secondary)
                        if !failureActions.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(failureActions) { action in
                                    Button(action.title, action: action.perform)
                                        .buttonStyle(.borderless)
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(Color.accentColor.opacity(
                                                    hoveredFailureActionID == action.id ? 0.2 : 0.1
                                                ))
                                        )
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .stroke(Color.accentColor.opacity(
                                                    hoveredFailureActionID == action.id ? 0.8 : 0.4
                                                ), lineWidth: 1)
                                        }
                                        .onHover { isHovering in
                                            hoveredFailureActionID = isHovering ? action.id : nil
                                        }
                                }
                            }
                        }
                    }
                case .answer:
                    EmptyView()
                }
            }
            if showsTutorialLensHint, let target = content.tutorialLensHintTarget {
                TutorialLensCoachCard(lensName: target.displayName)
            }
            if let layout = actionLayout {
                switch layout {
                case .horizontalSingleRow:
                    HStack(spacing: OverlayLensListLayout.horizontalSpacing) {
                        ForEach(actionOptions) { option in
                            actionButton(for: option)
                        }
                        Spacer(minLength: 0)
                    }
                case .horizontalWrapped:
                    LensButtonFlow(
                        horizontalSpacing: OverlayLensListLayout.horizontalSpacing,
                        verticalSpacing: OverlayLensListLayout.verticalSpacing
                    ) {
                        ForEach(actionOptions) { option in
                            actionButton(for: option)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                case .verticalFullWidth:
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: OverlayLensListLayout.verticalSpacing) {
                            ForEach(actionOptions) { option in
                                actionButton(for: option)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
            .frame(maxHeight: OverlayLensListLayout.maximumStackHeight)
                }
            }
            if showsQuestionField, let onQuestionSubmitted {
                TextField(questionFieldPlaceholder, text: $questionDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submitQuestion(handler: onQuestionSubmitted) }
            }
            if let localContextNotice = content.localContextNotice {
                Text(localContextNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, showsFooter ? OverlayFooterLayout.rowHeight + 8 : 0)
        .padding(20)
        .frame(
            width: OverlayPlacement.panelSize.width,
            height: content.preferredPanelSize(
                selectionPreviewIsVisible: hasSelectionPreview,
                followUpFrame: followUpFrame,
                showsTutorialLensHint: showsTutorialLensHint,
                actionOptions: actionOptions
            ).height,
            alignment: .topLeading
        )
        .background(
            Color(nsColor: .windowBackgroundColor),
            in: RoundedRectangle(
                cornerRadius: OverlayPanelAppearance.cornerRadius,
                style: .continuous
            )
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: OverlayPanelAppearance.cornerRadius,
                style: .continuous
            )
        )
        .overlay(alignment: .bottom) {
            if showsFooter {
                HStack {
                    if content.showsCopyAction, let answer = content.answerText {
                        Button {
                            NSPasteboard.general.clearContents()
                            guard NSPasteboard.general.setString(
                                answer,
                                forType: .string
                            ) else {
                                return
                            }
                            copyFeedback.markCopied()
                            let feedbackToken = UUID()
                            copyFeedbackToken = feedbackToken
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: AnswerCopyFeedback.displayDurationNanoseconds)
                                guard copyFeedbackToken == feedbackToken else { return }
                                copyFeedback.reset()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: copyFeedback == .copied ? "checkmark" : "doc.on.doc")
                                    .frame(width: 12, height: 12)
                                Text(copyFeedback.label)
                            }
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                        }
                        .buttonStyle(.borderless)
                        .overlay {
                            if isCopyButtonHovered {
                                RoundedRectangle(cornerRadius: LensHoverAppearance.cornerRadius)
                                    .fill(Color.primary.opacity(LensHoverAppearance.backgroundOpacity))
                                    .allowsHitTesting(false)
                            }
                        }
                        .onHover { isCopyButtonHovered = $0 }
                    }
                    Spacer()
                    if !actionOptions.isEmpty {
                        Button {
                            SettingsNavigation.openLensesSettings {
                                SettingsNavigation.requestSettingsWindow()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "slider.horizontal.3")
                                Text("Customize lenses…")
                            }
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.borderless)
                        .hoverHighlight()
                        .help("Create and edit the instructions used by your lenses")
                    }
                }
                .frame(height: OverlayFooterLayout.rowHeight)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .overlay {
            if isFileDropTargeted {
                ZStack {
                    Color.accentColor.opacity(0.08)
                    RoundedRectangle(cornerRadius: OverlayPanelAppearance.cornerRadius, style: .continuous)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    Text("Drop PDF, TXT, or Markdown to attach context")
                        .font(.callout)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                }
                .padding(6)
                .clipShape(RoundedRectangle(cornerRadius: OverlayPanelAppearance.cornerRadius, style: .continuous))
                .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: onFileDropped == nil ? nil : $isFileDropTargeted) { providers in
            guard let onFileDropped else { return false }
            return OverlayContent.loadDroppedURL(from: providers, completion: onFileDropped)
        }
        .onAppear {
            isTutorialLensPulseActive = showsTutorialLensHint
        }
        .onChange(of: showsTutorialLensHint) { _, isEnabled in
            isTutorialLensPulseActive = isEnabled
        }
    }

    private var actionOptions: [ReaderActionOption] {
        actionOptionsOverride ?? content.actionOptions
    }

    private var actionLayout: LensChooserLayout? {
        guard !actionOptions.isEmpty else { return nil }
        return OverlayLensListLayout.plan(
            buttonLabels: actionOptions.map { $0.display.name },
            availableWidth: OverlayPlacement.panelSize.width - 40
        ).layout
    }

    private var showsFooter: Bool {
        content.showsCopyAction || !actionOptions.isEmpty
    }

    private var hasSelectionPreview: Bool {
        !(selectionPreviewText ?? "").isEmpty
    }

    private var showsQuestionField: Bool {
        onQuestionSubmitted != nil
            && content.showsQuestionField(hasSelectionPreview: hasSelectionPreview)
    }

    private var questionFieldPlaceholder: String {
        if case .answer = content { return "Ask one follow-up…" }
        return hasSelectionPreview ? "Ask about this…" : "Ask a question…"
    }

    @ViewBuilder
    private func priorAnswerBox(text: String) -> some View {
        NativeMarkdownAnswer(
            text: OverlayMarkdownRenderer.nativeText(for: text),
            followsLatestContent: false,
            onUserScroll: {}
        )
        .frame(height: OverlayContentState.measureAnswerHeight(text))
        .background(
            Color.primary.opacity(OverlayMarkdownAppearance.answerBackgroundOpacity),
            in: RoundedRectangle(
                cornerRadius: OverlayMarkdownAppearance.answerCornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: OverlayMarkdownAppearance.answerCornerRadius,
                style: .continuous
            )
            .stroke(
                Color.primary.opacity(OverlayMarkdownAppearance.answerBorderOpacity),
                lineWidth: 1
            )
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: OverlayMarkdownAppearance.answerCornerRadius,
                style: .continuous
            )
        )
    }

    private var showsSubmittedQuestion: Bool {
        guard let userQuestionText, !userQuestionText.isEmpty else { return false }
        if case .choosingLens = content { return false }
        return true
    }

    private func submitQuestion(handler: (String) -> Void) {
        let trimmed = questionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        questionDraft = ""
        handler(trimmed)
    }

    @ViewBuilder
    private func actionButton(for option: ReaderActionOption) -> some View {
        let action = option.action
        let isTutorialTarget = showsTutorialLensHint
            && content.tutorialLensHintTarget?.id == action.id
        Button {
            onActionSelected?(action)
        } label: {
            Text(action.display.name)
        }
        .buttonStyle(.bordered)
        .disabled(!option.isEnabled)
        .opacity(option.isEnabled ? 1 : 0.55)
        .overlay {
            ZStack {
                if hoveredAction == action {
                    RoundedRectangle(cornerRadius: LensHoverAppearance.cornerRadius)
                        .fill(Color.primary.opacity(LensHoverAppearance.backgroundOpacity))
                        .allowsHitTesting(false)
                }
                if isTutorialTarget {
                    RoundedRectangle(cornerRadius: LensHoverAppearance.cornerRadius)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .scaleEffect(isTutorialLensPulseActive ? 1.08 : 1)
                        .opacity(isTutorialLensPulseActive ? 0.45 : 1)
                        .animation(
                            .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                            value: isTutorialLensPulseActive
                        )
                        .allowsHitTesting(false)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if isTutorialTarget {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
                    .offset(x: 8, y: -8)
                    .opacity(isTutorialLensPulseActive ? 1 : 0.45)
                    .animation(
                        .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                        value: isTutorialLensPulseActive
                    )
            }
        }
        .onHover { isHovering in
            hoveredAction = isHovering ? action : nil
            if isHovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private struct TutorialLensCoachCard: View {
        let lensName: String
        @State private var isPulsing = false

        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: "cursorarrow.click")
                    .foregroundStyle(Color.accentColor)
                    .scaleEffect(isPulsing ? 1.12 : 1)
                Text("Click “\(lensName)” to try another explanation")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
        }
    }

    static func loadDroppedURL(
        from providers: [NSItemProvider],
        completion: @escaping (URL) -> Void
    ) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            switch item {
            case let data as Data:
                url = URL(dataRepresentation: data, relativeTo: nil)
            case let string as String:
                url = URL(string: string)
            case let concrete as URL:
                url = concrete
            default:
                url = nil
            }
            guard let url else { return }
            DispatchQueue.main.async {
                completion(url)
            }
        }
        return true
    }

    private struct TutorialDismissArrow: View {
        var body: some View {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.6)
                let pulse = (sin(phase * 2 * .pi / 1.6) + 1) / 2
                Image(systemName: "arrow.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .offset(x: CGFloat((pulse - 0.5) * 3))
                    .opacity(0.35 + pulse * 0.65)
                    .scaleEffect(0.95 + pulse * 0.1)
            }
            .frame(width: 12, height: 16)
            .allowsHitTesting(false)
        }
    }
}
