enum InteractionRequest {
    case userQuestionOnPassage(
        passage: String,
        paperTitle: String?,
        localContext: String?,
        question: String
    )
    case freeformQuestion(question: String)
    case followUp(prior: [ChatMessage], question: String)

    var messages: [ChatMessage] {
        switch self {
        case let .userQuestionOnPassage(passage, paperTitle, localContext, question):
            return buildPassageMessages(
                passage: passage,
                paperTitle: paperTitle,
                localContext: localContext,
                intent: .userQuestion(question)
            )
        case let .freeformQuestion(question):
            return buildFreeformMessages(userQuestion: question)
        case let .followUp(prior, question):
            return prior + [ChatMessage(role: .user, content: question)]
        }
    }
}

struct InteractionPresentation {
    let actions: [ReaderAction]
    let selectedAction: ReaderAction?
    let usesPaperContext: Bool
    let localSourceName: String?
    let localContextFallback: LocalContextFallback
    let model: String
    let allowsFollowUp: Bool
    let followUpFrame: FollowUpFrame?

    var lenses: [ExplanationLens] {
        actions.compactMap { action in
            guard case let .lens(lens) = action else { return nil }
            return lens
        }
    }

    var selectedLens: ExplanationLens? {
        guard case let .lens(lens) = selectedAction else { return nil }
        return lens
    }

    init(
        actions: [ReaderAction],
        selectedAction: ReaderAction?,
        usesPaperContext: Bool,
        localSourceName: String? = nil,
        localContextFallback: LocalContextFallback = .none,
        model: String,
        allowsFollowUp: Bool = false,
        followUpFrame: FollowUpFrame? = nil
    ) {
        self.actions = actions
        self.selectedAction = selectedAction
        self.usesPaperContext = usesPaperContext
        self.localSourceName = localSourceName
        self.localContextFallback = localContextFallback
        self.model = model
        self.allowsFollowUp = allowsFollowUp
        self.followUpFrame = followUpFrame
    }

    init(
        lenses: [ExplanationLens],
        selectedLens: ExplanationLens?,
        usesPaperContext: Bool,
        localSourceName: String? = nil,
        localContextFallback: LocalContextFallback = .none,
        model: String,
        allowsFollowUp: Bool = false,
        followUpFrame: FollowUpFrame? = nil
    ) {
        self.init(
            actions: lenses.map(ReaderAction.lens),
            selectedAction: selectedLens.map(ReaderAction.lens),
            usesPaperContext: usesPaperContext,
            localSourceName: localSourceName,
            localContextFallback: localContextFallback,
            model: model,
            allowsFollowUp: allowsFollowUp,
            followUpFrame: followUpFrame
        )
    }

    func requesting() -> OverlayContentState {
        .requesting(
            lenses: lenses,
            selectedLens: selectedLens,
            usesPaperContext: usesPaperContext,
            localSourceName: localSourceName,
            localContextFallback: localContextFallback,
            model: model
        )
    }

    func streaming(_ answer: String) -> OverlayContentState {
        .streaming(
            answer,
            lenses: lenses,
            selectedLens: selectedLens,
            usesPaperContext: usesPaperContext,
            localSourceName: localSourceName,
            localContextFallback: localContextFallback,
            model: model
        )
    }

    func answer(_ answer: String) -> OverlayContentState {
        .answer(
            answer,
            lenses: lenses,
            selectedLens: selectedLens,
            usesPaperContext: usesPaperContext,
            localSourceName: localSourceName,
            localContextFallback: localContextFallback,
            model: model
        )
    }

    func failure(_ message: String) -> OverlayContentState {
        .failure(message, lenses: lenses, selectedLens: selectedLens, model: model)
    }
}
