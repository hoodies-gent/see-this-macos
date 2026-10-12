import Foundation

nonisolated struct ContextEnvelope: Equatable, Sendable {
    let selectedText: String?
    let authorizedDocumentExcerpt: String?
    let hostDocumentTitle: String?

    init(
        selectedText: String?,
        authorizedDocumentExcerpt: String? = nil,
        hostDocumentTitle: String? = nil
    ) {
        self.selectedText = selectedText
        self.authorizedDocumentExcerpt = authorizedDocumentExcerpt
        self.hostDocumentTitle = hostDocumentTitle
    }
}

nonisolated enum ActionStrategyKind: String, Equatable, Sendable {
    case modelPrompt
    case singleCapability
    case boundedAgent
}

nonisolated enum ActionRuntimeEvent: Equatable, Sendable {
    case outputFragment(String)
}

nonisolated enum ActionContextSource: String, Equatable, Sendable {
    case selection
    case hostDocumentMetadata
    case authorizedDocument
}

nonisolated enum ActionExecutionDestination: Equatable, Sendable {
    case localModel
    case network(host: String)
}

nonisolated enum ActionExecutionTermination: Equatable, Sendable {
    case completed
    case rejected(code: String)
    case failed(code: String)
    case cancelled
}

nonisolated struct ActionExecutionTrace: Equatable, Sendable {
    let actionID: String
    let source: ResolvedActionSource
    let strategy: ActionStrategyKind
    let contextSources: [ActionContextSource]
    let resolvedPermissions: [ActionPermission]
    let budget: ActionBudget
    let modelCallCount: Int
    let capabilityCallCount: Int
    let destination: ActionExecutionDestination?
    let startedAt: Date
    let finishedAt: Date
    let termination: ActionExecutionTermination
}

nonisolated enum ActionRuntimeFailure: Error, Equatable, Sendable {
    case missingRequiredSelection
    case strategyUnavailable(ActionStrategyKind)
    case capability(CapabilityError)
    case model(ChatFailure)
    case cancelled
}

nonisolated struct ActionExecutionOutcome: Equatable, Sendable {
    let result: Result<String, ActionRuntimeFailure>
    let continuation: ActionContinuation?
    let trace: ActionExecutionTrace
}

nonisolated struct ActionContinuation: Equatable, Sendable {
    private let initialMessages: [ChatMessage]

    fileprivate init(initialMessages: [ChatMessage]) {
        self.initialMessages = initialMessages
    }

    func messages(answer: String) -> [ChatMessage] {
        initialMessages + [ChatMessage(role: .assistant, content: answer)]
    }

    func messages(answer: String, question: String) -> [ChatMessage] {
        messages(answer: answer) + [ChatMessage(role: .user, content: question)]
    }
}

nonisolated struct ActionWorkflowRuntime: Sendable {
    private let modelClient: any ActionModelClient

    init(modelClient: any ActionModelClient) {
        self.modelClient = modelClient
    }

    func execute(
        action: ResolvedAction,
        envelope: ContextEnvelope,
        model: String,
        capabilityInvocation: AuthorizedCapabilityInvocation? = nil,
        capabilityInput: CapabilityInput? = nil,
        onEvent: @escaping @Sendable (ActionRuntimeEvent) async -> Void = { _ in }
    ) async -> ActionExecutionOutcome {
        let startedAt = Date()
        let strategy = ActionStrategyKind(action.execution)

        guard case let .modelPrompt(prompt, framing) = action.execution else {
            if case let .singleCapability(capabilityID) = action.execution {
                return await executeSingleCapability(
                    action: action,
                    capabilityID: capabilityID,
                    envelope: envelope,
                    capabilityInvocation: capabilityInvocation,
                    capabilityInput: capabilityInput,
                    startedAt: startedAt
                )
            }
            return outcome(
                action: action,
                strategy: strategy,
                result: .failure(.strategyUnavailable(strategy)),
                modelCallCount: 0,
                startedAt: startedAt,
                termination: .rejected(code: "runtime.strategy_unavailable")
            )
        }

        guard let selection = envelope.selectedText,
              !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return outcome(
                action: action,
                strategy: strategy,
                result: .failure(.missingRequiredSelection),
                modelCallCount: 0,
                startedAt: startedAt,
                termination: .rejected(code: "runtime.selection_required")
            )
        }

        guard !Task.isCancelled else {
            return outcome(
                action: action,
                strategy: strategy,
                result: .failure(.cancelled),
                modelCallCount: 0,
                startedAt: startedAt,
                termination: .cancelled
            )
        }

        let contextSources = contextSources(for: envelope)
        let messages = buildResolvedLensMessages(
            passage: selection,
            paperTitle: envelope.hostDocumentTitle,
            localContext: envelope.authorizedDocumentExcerpt,
            prompt: prompt,
            includesReaderPreferenceFraming: framing == .readerAuthored
        )
        let output = ActionOutputAccumulator()
        let result = await modelClient.streamChat(
            model: model,
            messages: messages
        ) { event in
            guard case let .fragment(fragment) = event else { return }
            await output.append(fragment)
            await onEvent(.outputFragment(fragment))
        }

        switch result {
        case .success:
            return outcome(
                action: action,
                strategy: strategy,
                result: .success(await output.value()),
                modelCallCount: 1,
                contextSources: contextSources,
                resolvedPermissions: action.resolvedPermissions,
                destination: .localModel,
                continuation: ActionContinuation(initialMessages: messages),
                startedAt: startedAt,
                termination: .completed
            )
        case .failure(.cancelled):
            return outcome(
                action: action,
                strategy: strategy,
                result: .failure(.cancelled),
                modelCallCount: 1,
                contextSources: contextSources,
                resolvedPermissions: action.resolvedPermissions,
                destination: .localModel,
                startedAt: startedAt,
                termination: .cancelled
            )
        case let .failure(failure):
            return outcome(
                action: action,
                strategy: strategy,
                result: .failure(.model(failure)),
                modelCallCount: 1,
                contextSources: contextSources,
                resolvedPermissions: action.resolvedPermissions,
                destination: .localModel,
                startedAt: startedAt,
                termination: .failed(code: "runtime.model_failure")
            )
        }
    }

    private func executeSingleCapability(
        action: ResolvedAction,
        capabilityID: String,
        envelope: ContextEnvelope,
        capabilityInvocation: AuthorizedCapabilityInvocation?,
        capabilityInput: CapabilityInput?,
        startedAt: Date
    ) async -> ActionExecutionOutcome {
        guard action.budget == ActionBudget(maxModelCalls: 0, maxCapabilityCalls: 1) else {
            return outcome(
                action: action,
                strategy: .singleCapability,
                result: .failure(.strategyUnavailable(.singleCapability)),
                modelCallCount: 0,
                startedAt: startedAt,
                termination: .rejected(code: "runtime.strategy_unavailable")
            )
        }

        guard let capabilityInvocation,
              capabilityInvocation.actionID == action.id,
              capabilityInvocation.capability.descriptor.id == capabilityID,
              capabilityInvocation.permissions == action.resolvedPermissions else {
            return outcome(
                action: action,
                strategy: .singleCapability,
                result: .failure(.capability(.permissionDenied)),
                modelCallCount: 0,
                resolvedPermissions: action.resolvedPermissions,
                startedAt: startedAt,
                termination: .rejected(code: "runtime.capability_not_authorized")
            )
        }

        guard let capabilityInput,
              inputSelection(capabilityInput) == envelope.selectedText,
              !inputSelection(capabilityInput).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return outcome(
                action: action,
                strategy: .singleCapability,
                result: .failure(.capability(.invalidInput)),
                modelCallCount: 0,
                contextSources: [.selection],
                resolvedPermissions: capabilityInvocation.permissions,
                destination: executionDestination(for: capabilityInvocation.permissions),
                startedAt: startedAt,
                termination: .rejected(code: "runtime.capability_input_invalid")
            )
        }

        guard !Task.isCancelled else {
            return outcome(
                action: action,
                strategy: .singleCapability,
                result: .failure(.cancelled),
                modelCallCount: 0,
                contextSources: [.selection],
                resolvedPermissions: capabilityInvocation.permissions,
                destination: executionDestination(for: capabilityInvocation.permissions),
                startedAt: startedAt,
                termination: .cancelled
            )
        }

        let destination = executionDestination(for: capabilityInvocation.permissions)
        switch await capabilityInvocation.capability.invoke(capabilityInput) {
        case let .success(.text(text)):
            return outcome(
                action: action,
                strategy: .singleCapability,
                result: .success(text),
                modelCallCount: 0,
                capabilityCallCount: 1,
                contextSources: [.selection],
                resolvedPermissions: capabilityInvocation.permissions,
                destination: destination,
                startedAt: startedAt,
                termination: .completed
            )
        case .failure(.cancelled):
            return outcome(
                action: action,
                strategy: .singleCapability,
                result: .failure(.capability(.cancelled)),
                modelCallCount: 0,
                capabilityCallCount: 1,
                contextSources: [.selection],
                resolvedPermissions: capabilityInvocation.permissions,
                destination: destination,
                startedAt: startedAt,
                termination: .cancelled
            )
        case let .failure(error):
            return outcome(
                action: action,
                strategy: .singleCapability,
                result: .failure(.capability(error)),
                modelCallCount: 0,
                capabilityCallCount: 1,
                contextSources: [.selection],
                resolvedPermissions: capabilityInvocation.permissions,
                destination: destination,
                startedAt: startedAt,
                termination: .failed(code: "runtime.capability_failure")
            )
        }
    }

    private func inputSelection(_ input: CapabilityInput) -> String {
        switch input {
        case let .translate(translation):
            translation.selection
        }
    }

    private func executionDestination(
        for permissions: [ActionPermission]
    ) -> ActionExecutionDestination? {
        permissions.compactMap { permission -> ActionExecutionDestination? in
            guard case let .network(host, _) = permission else { return nil }
            return .network(host: host)
        }.first
    }

    private func contextSources(for envelope: ContextEnvelope) -> [ActionContextSource] {
        var sources: [ActionContextSource] = [.selection]
        if let title = envelope.hostDocumentTitle, !title.isEmpty {
            sources.append(.hostDocumentMetadata)
        }
        if let excerpt = envelope.authorizedDocumentExcerpt, !excerpt.isEmpty {
            sources.append(.authorizedDocument)
        }
        return sources
    }

    private func outcome(
        action: ResolvedAction,
        strategy: ActionStrategyKind,
        result: Result<String, ActionRuntimeFailure>,
        modelCallCount: Int,
        capabilityCallCount: Int = 0,
        contextSources: [ActionContextSource] = [],
        resolvedPermissions: [ActionPermission] = [],
        destination: ActionExecutionDestination? = nil,
        continuation: ActionContinuation? = nil,
        startedAt: Date,
        termination: ActionExecutionTermination
    ) -> ActionExecutionOutcome {
        ActionExecutionOutcome(
            result: result,
            continuation: continuation,
            trace: ActionExecutionTrace(
                actionID: action.id,
                source: action.source,
                strategy: strategy,
                contextSources: contextSources,
                resolvedPermissions: resolvedPermissions,
                budget: action.budget,
                modelCallCount: modelCallCount,
                capabilityCallCount: capabilityCallCount,
                destination: destination,
                startedAt: startedAt,
                finishedAt: Date(),
                termination: termination
            )
        )
    }
}

private nonisolated extension ActionStrategyKind {
    init(_ strategy: ResolvedActionExecution) {
        switch strategy {
        case .modelPrompt:
            self = .modelPrompt
        case .singleCapability:
            self = .singleCapability
        case .boundedAgent:
            self = .boundedAgent
        }
    }
}

private actor ActionOutputAccumulator {
    private var output = ""

    func append(_ fragment: String) {
        output += fragment
    }

    func value() -> String {
        output
    }
}
