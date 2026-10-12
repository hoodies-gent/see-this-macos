import AppKit

enum OverlayActivityStatusText {
    static let preparing = "Preparing…"
    static let generating = "Generating…"
    static let translating = "Translating…"
    static let loadingModel = "Loading model…"
}

enum LocalContextFallback: Equatable {
    case none
    case selectLongerPhrase
    case noMatch
    case documentTooLargeToLocate

    var message: String? {
        switch self {
        case .none: nil
        case .selectLongerPhrase: "Select a longer phrase to use authorized local context."
        case .noMatch: "No match for this selection in the attached document."
        case .documentTooLargeToLocate: "Selection not located in the document; sending the document start instead."
        }
    }
}
struct FollowUpFrame: Equatable {
    let priorAnswer: String
    let currentQuestion: String
}

struct OverlayFailureAction: Identifiable {
    let id: String
    let title: String
    let perform: () -> Void
}

enum OverlayContentState {
    static let maximumAnswerHeight: CGFloat = 480
    case choosingLens(
        lenses: [ExplanationLens],
        usesPaperContext: Bool,
        localSourceName: String? = nil,
        localContextFallback: LocalContextFallback = .none,
        model: String = OllamaProvider.defaultModelName
    )
    case requesting(
        lenses: [ExplanationLens] = [],
        selectedLens: ExplanationLens? = nil,
        usesPaperContext: Bool,
        localSourceName: String? = nil,
        localContextFallback: LocalContextFallback = .none,
        model: String = OllamaProvider.defaultModelName
    )
    case streaming(
        String,
        lenses: [ExplanationLens] = [],
        selectedLens: ExplanationLens? = nil,
        usesPaperContext: Bool,
        localSourceName: String? = nil,
        localContextFallback: LocalContextFallback = .none,
        model: String = OllamaProvider.defaultModelName
    )
    case answer(
        String,
        lenses: [ExplanationLens] = [],
        selectedLens: ExplanationLens? = nil,
        usesPaperContext: Bool,
        localSourceName: String? = nil,
        localContextFallback: LocalContextFallback = .none,
        model: String = OllamaProvider.defaultModelName
    )
    case failure(
        String,
        lenses: [ExplanationLens] = [],
        selectedLens: ExplanationLens? = nil,
        model: String = OllamaProvider.defaultModelName
    )

    var contextLabel: String {
        switch self {
        case let .choosingLens(_, usesPaperContext, localSourceName, _, _),
             let .requesting(_, _, usesPaperContext, localSourceName, _, _),
             let .streaming(_, _, _, usesPaperContext, localSourceName, _, _),
             let .answer(_, _, _, usesPaperContext, localSourceName, _, _):
            if let localSourceName {
                return "Based on the selected passage and authorized local context (\(localSourceName))"
            }
            return usesPaperContext
                ? "Based on the selected passage and paper context"
                : "Based on the selected passage"
        case .failure:
            return "Based on the selected passage"
        }
    }

    var contextTagName: String? {
        switch self {
        case let .choosingLens(_, _, localSourceName, _, _),
             let .requesting(_, _, _, localSourceName, _, _),
             let .streaming(_, _, _, _, localSourceName, _, _),
             let .answer(_, _, _, _, localSourceName, _, _):
            localSourceName
        case .failure:
            nil
        }
    }

    var localContextNotice: String? {
        switch self {
        case let .choosingLens(_, _, _, fallback, _),
             let .requesting(_, _, _, _, fallback, _),
             let .streaming(_, _, _, _, _, fallback, _),
             let .answer(_, _, _, _, _, fallback, _):
            fallback.message
        case .failure:
            nil
        }
    }

    var isScrollableAnswer: Bool {
        switch self {
        case .streaming, .answer:
            return true
        default:
            return false
        }
    }

    var answerText: String? {
        switch self {
        case let .streaming(answer, _, _, _, _, _, _),
             let .answer(answer, _, _, _, _, _, _):
            return answer
        default:
            return nil
        }
    }

    var lensOptions: [ExplanationLens] {
        switch self {
        case let .choosingLens(lenses, _, _, _, _),
             let .requesting(lenses, _, _, _, _, _),
             let .streaming(_, lenses, _, _, _, _, _),
             let .answer(_, lenses, _, _, _, _, _),
             let .failure(_, lenses, _, _):
            lenses
        }
    }

    var actionOptions: [ReaderActionOption] {
        ReaderActionCatalog.options(
            lenses: lensOptions,
            packages: [],
            enabledPackageIDs: []
        )
    }

    var selectedLens: ExplanationLens? {
        switch self {
        case .choosingLens:
            nil
        case let .requesting(_, selectedLens, _, _, _, _),
             let .streaming(_, _, selectedLens, _, _, _, _),
             let .answer(_, _, selectedLens, _, _, _, _),
             let .failure(_, _, selectedLens, _):
            selectedLens
        }
    }

    var selectedAction: ReaderAction? {
        selectedLens.map(ReaderAction.lens)
    }

    var selectedLensDisplayName: String? {
        selectedLens?.displayName
    }

    var selectedActionDisplayName: String? {
        selectedAction?.display.name
    }

    var tutorialLensHintTarget: ExplanationLens? {
        lensOptions.first { $0.id != selectedLens?.id }
    }

    func replacingLocalSourceName(_ name: String?) -> OverlayContentState {
        switch self {
        case let .choosingLens(lenses, usesPaperContext, _, localContextFallback, model):
            return .choosingLens(
                lenses: lenses,
                usesPaperContext: usesPaperContext,
                localSourceName: name,
                localContextFallback: localContextFallback,
                model: model
            )
        case let .requesting(lenses, selectedLens, usesPaperContext, _, localContextFallback, model):
            return .requesting(
                lenses: lenses,
                selectedLens: selectedLens,
                usesPaperContext: usesPaperContext,
                localSourceName: name,
                localContextFallback: localContextFallback,
                model: model
            )
        case let .streaming(answer, lenses, selectedLens, usesPaperContext, _, localContextFallback, model):
            return .streaming(
                answer,
                lenses: lenses,
                selectedLens: selectedLens,
                usesPaperContext: usesPaperContext,
                localSourceName: name,
                localContextFallback: localContextFallback,
                model: model
            )
        case let .answer(answer, lenses, selectedLens, usesPaperContext, _, localContextFallback, model):
            return .answer(
                answer,
                lenses: lenses,
                selectedLens: selectedLens,
                usesPaperContext: usesPaperContext,
                localSourceName: name,
                localContextFallback: localContextFallback,
                model: model
            )
        case .failure:
            return self
        }
    }

    func replacingFailureMessage(_ message: String) -> OverlayContentState {
        switch self {
        case let .choosingLens(lenses, _, _, _, model):
            return .failure(message, lenses: lenses, selectedLens: nil, model: model)
        case let .requesting(lenses, selectedLens, _, _, _, model),
             let .streaming(_, lenses, selectedLens, _, _, _, model),
             let .answer(_, lenses, selectedLens, _, _, _, model):
            return .failure(message, lenses: lenses, selectedLens: selectedLens, model: model)
        case let .failure(_, lenses, selectedLens, model):
            return .failure(message, lenses: lenses, selectedLens: selectedLens, model: model)
        }
    }

    func refreshingLenses(_ lenses: [ExplanationLens]) -> OverlayContentState {
        func refreshedSelection(_ selectedLens: ExplanationLens?) -> ExplanationLens? {
            selectedLens.flatMap { selectedLens in
                lenses.first { $0.id == selectedLens.id }
            }
        }

        switch self {
        case let .choosingLens(_, usesPaperContext, localSourceName, localContextFallback, model):
            return .choosingLens(
                lenses: lenses,
                usesPaperContext: usesPaperContext,
                localSourceName: localSourceName,
                localContextFallback: localContextFallback,
                model: model
            )
        case let .requesting(_, selectedLens, usesPaperContext, localSourceName, localContextFallback, model):
            return .requesting(
                lenses: lenses,
                selectedLens: refreshedSelection(selectedLens),
                usesPaperContext: usesPaperContext,
                localSourceName: localSourceName,
                localContextFallback: localContextFallback,
                model: model
            )
        case let .streaming(answer, _, selectedLens, usesPaperContext, localSourceName, localContextFallback, model):
            return .streaming(
                answer,
                lenses: lenses,
                selectedLens: refreshedSelection(selectedLens),
                usesPaperContext: usesPaperContext,
                localSourceName: localSourceName,
                localContextFallback: localContextFallback,
                model: model
            )
        case let .answer(answer, _, selectedLens, usesPaperContext, localSourceName, localContextFallback, model):
            return .answer(
                answer,
                lenses: lenses,
                selectedLens: refreshedSelection(selectedLens),
                usesPaperContext: usesPaperContext,
                localSourceName: localSourceName,
                localContextFallback: localContextFallback,
                model: model
            )
        case let .failure(message, _, selectedLens, model):
            return .failure(
                message,
                lenses: lenses,
                selectedLens: refreshedSelection(selectedLens),
                model: model
            )
        }
    }

    var lensStatusText: String {
        guard let selectedLens else { return "Choose an explanation lens" }
        switch self {
        case .choosingLens:
            return "Choose an explanation lens"
        case .requesting:
            return "Explaining with: \(selectedLens.displayName)"
        case .streaming:
            return "Explaining with: \(selectedLens.displayName)"
        case .answer:
            return "Explained with: \(selectedLens.displayName)"
        case .failure:
            return "Last tried: \(selectedLens.displayName)"
        }
    }

    func requestingContent(for lens: ExplanationLens) -> OverlayContentState? {
        guard lensOptions.contains(lens) else { return nil }
        switch self {
        case let .choosingLens(lenses, usesPaperContext, localSourceName, localContextFallback, model):
            return .requesting(
                lenses: lenses,
                selectedLens: lens,
                usesPaperContext: usesPaperContext,
                localSourceName: localSourceName,
                localContextFallback: localContextFallback,
                model: model
            )
        case let .requesting(lenses, _, usesPaperContext, localSourceName, localContextFallback, model),
             let .streaming(_, lenses, _, usesPaperContext, localSourceName, localContextFallback, model),
             let .answer(_, lenses, _, usesPaperContext, localSourceName, localContextFallback, model):
            return .requesting(
                lenses: lenses,
                selectedLens: lens,
                usesPaperContext: usesPaperContext,
                localSourceName: localSourceName,
                localContextFallback: localContextFallback,
                model: model
            )
        case let .failure(_, lenses, _, model):
            return .requesting(lenses: lenses, selectedLens: lens, usesPaperContext: false, model: model)
        }
    }

    func requestingContent(for action: ReaderAction) -> OverlayContentState? {
        guard case let .lens(lens) = action else { return nil }
        return requestingContent(for: lens)
    }

    var isRequesting: Bool {
        if case .requesting = self {
            return true
        }
        if case .streaming = self {
            return true
        }
        return false
    }

    var lensActionLayout: LensChooserLayout? {
        guard !actionOptions.isEmpty else { return nil }
        return OverlayLensListLayout.plan(
            buttonLabels: actionOptions.map { $0.display.name },
            availableWidth: OverlayPlacement.panelSize.width - 40
        ).layout
    }

    var modelLabel: String {
        let model: String
        switch self {
        case let .choosingLens(_, _, _, _, value),
             let .requesting(_, _, _, _, _, value),
             let .streaming(_, _, _, _, _, _, value),
             let .answer(_, _, _, _, _, _, value),
             let .failure(_, _, _, value):
            model = value
        }
        return "\(model) (local)"
    }

    func preferredPanelSize(
        selectionPreviewIsVisible: Bool = false,
        followUpFrame: FollowUpFrame? = nil,
        showsTutorialLensHint: Bool = false,
        actionOptions: [ReaderActionOption]? = nil
    ) -> CGSize {
        let resolvedActionOptions = actionOptions ?? self.actionOptions
        let lensHeight = OverlayLensListLayout.plan(
            buttonLabels: resolvedActionOptions.map { $0.display.name },
            availableWidth: OverlayPlacement.panelSize.width - 40
        ).sectionHeight
        let answerHeight = preferredAnswerHeight
        let selectionPreviewHeight: CGFloat = selectionPreviewIsVisible ? 36 : 0
        let contextTagHeight: CGFloat = contextTagName == nil ? 0 : 28
        let questionFieldHeight: CGFloat = showsQuestionField(hasSelectionPreview: selectionPreviewIsVisible) ? 36 : 0
        let followUpHeight: CGFloat
        if let followUpFrame {
            followUpHeight = Self.measureAnswerHeight(followUpFrame.priorAnswer) + 8 + 20 + 8
        } else {
            followUpHeight = 0
        }
        let tutorialLensHintHeight: CGFloat = showsTutorialLensHint ? 52 : 0
        let footerHeight: CGFloat = showsCopyAction || !resolvedActionOptions.isEmpty
            ? OverlayFooterLayout.rowHeight + 8
            : 0
        let height = 40 + selectionPreviewHeight + contextTagHeight + 16 + 8 + tutorialLensHintHeight + lensHeight + questionFieldHeight + 8 + followUpHeight + answerHeight + footerHeight + 40
        return CGSize(width: OverlayPlacement.panelSize.width, height: height)
    }

    private var preferredAnswerHeight: CGFloat {
        Self.measureAnswerHeight(answerText)
    }

    static func measureAnswerHeight(_ text: String?) -> CGFloat {
        guard let text, !text.isEmpty else { return 28 }
        let measuredHeight = (text as NSString).boundingRect(
            with: CGSize(width: OverlayPlacement.panelSize.width - 40, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)],
            context: nil
        ).height
        return min(max(ceil(measuredHeight), 28), maximumAnswerHeight)
    }

    var isStreaming: Bool {
        if case .streaming = self { return true }
        return false
    }

    var showsStreamingProgress: Bool {
        isStreaming
    }

    var activityStatusLabel: String? {
        switch self {
        case .requesting:
            OverlayActivityStatusText.preparing
        case .streaming:
            OverlayActivityStatusText.generating
        default:
            nil
        }
    }

    func activityStatusLabel(for action: ReaderAction?) -> String? {
        if case .requesting = self,
           action?.id == TranslateActionCoordinator.actionID {
            return OverlayActivityStatusText.translating
        }
        return activityStatusLabel
    }

    var showsDragHandle: Bool { false }

    var showsCopyAction: Bool {
        if case .answer = self { return true }
        return false
    }

    var allowsTextSelection: Bool { isScrollableAnswer }

    // Question field appears while the reader is composing input for the model:
    // - `.choosingLens` with a captured selection (lens buttons alongside)
    // - `.choosingLens` with no lenses (freeform-no-selection path)
    // - `.answer` when the caller has wired a follow-up handler
    // The follow-up gate itself is `onQuestionSubmitted != nil` on the panel side,
    // so this predicate only cares about the state shape.
    func showsQuestionField(hasSelectionPreview: Bool) -> Bool {
        switch self {
        case .choosingLens:
            return lensOptions.isEmpty || hasSelectionPreview
        case .answer:
            return true
        case .requesting, .streaming, .failure:
            return false
        }
    }
}
