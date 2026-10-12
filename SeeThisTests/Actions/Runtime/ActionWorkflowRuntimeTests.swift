import Foundation
import Testing
@testable import SeeThis

struct ActionWorkflowRuntimeTests {

    @Test func modelPromptStreamsOneLocalModelCallAndReturnsAContentFreeTrace() async throws {
        let model = RecordingActionModelClient(
            events: [.fragment("Bounded "), .fragment("answer."), .finished],
            result: .success(())
        )
        let events = RuntimeEventRecorder()
        let runtime = ActionWorkflowRuntime(modelClient: model)

        let outcome = await runtime.execute(
            action: modelPromptAction(prompt: "Explain with the declared focus."),
            envelope: ContextEnvelope(
                selectedText: "Synthetic selection.",
                authorizedDocumentExcerpt: "Synthetic authorized excerpt.",
                hostDocumentTitle: "Synthetic paper title"
            ),
            model: "test-model"
        ) { event in
            await events.append(event)
        }

        #expect(outcome.result == .success("Bounded answer."))
        #expect(
            await events.values()
                == [.outputFragment("Bounded "), .outputFragment("answer.")]
        )
        #expect(outcome.trace.actionID == "custom-explain")
        #expect(outcome.trace.source == .lens)
        #expect(outcome.trace.strategy == .modelPrompt)
        #expect(
            outcome.trace.contextSources
                == [.selection, .hostDocumentMetadata, .authorizedDocument]
        )
        #expect(outcome.trace.resolvedPermissions == [.localModel])
        #expect(
            outcome.trace.budget
                == ActionBudget(maxModelCalls: 1, maxCapabilityCalls: 0)
        )
        #expect(outcome.trace.modelCallCount == 1)
        #expect(outcome.trace.capabilityCallCount == 0)
        #expect(outcome.trace.destination == .localModel)
        #expect(outcome.trace.finishedAt >= outcome.trace.startedAt)
        #expect(outcome.trace.termination == .completed)

        let requests = await model.requests()
        let request = try #require(requests.first)
        #expect(requests.count == 1)
        #expect(request.model == "test-model")
        #expect(request.messages.count == 2)
        #expect(request.messages[0].role == .system)
        #expect(request.messages[0].content.contains("<passage>\nSynthetic selection.\n</passage>"))
        #expect(
            request.messages[0].content.contains(
                "<local_context>\nSynthetic authorized excerpt.\n</local_context>"
            )
        )
        #expect(
            request.messages[0].content.contains(
                "<paper_title>\nSynthetic paper title\n</paper_title>"
            )
        )
        #expect(request.messages[1] == ChatMessage(
            role: .user,
            content: "Explain with the declared focus."
        ))

        let continuation = try #require(outcome.continuation)
        #expect(
            continuation.messages(answer: "Bounded answer.") == request.messages + [
                ChatMessage(role: .assistant, content: "Bounded answer.")
            ]
        )
        #expect(
            continuation.messages(
                answer: "Bounded answer.",
                question: "What does that imply?"
            ) == request.messages + [
                ChatMessage(role: .assistant, content: "Bounded answer."),
                ChatMessage(role: .user, content: "What does that imply?")
            ]
        )
    }

    @Test func missingSelectionIsRejectedBeforeTheModelBoundary() async {
        let model = RecordingActionModelClient()
        let runtime = ActionWorkflowRuntime(modelClient: model)

        let outcome = await runtime.execute(
            action: modelPromptAction(),
            envelope: ContextEnvelope(selectedText: "  \n"),
            model: "test-model"
        )

        #expect(outcome.result == .failure(.missingRequiredSelection))
        #expect(outcome.trace.modelCallCount == 0)
        #expect(
            outcome.trace.termination
                == .rejected(code: "runtime.selection_required")
        )
        #expect(outcome.continuation == nil)
        #expect(await model.requests().isEmpty)
    }

    @Test func capabilityStrategyCannotReachTheModelBoundaryWithoutAuthorization() async {
        let model = RecordingActionModelClient()
        let runtime = ActionWorkflowRuntime(modelClient: model)
        let action = ResolvedAction(
            id: "community.lookup",
            source: .package(version: SemanticVersion(1, 0, 0)),
            display: ActionDisplayInfo(name: "Lookup", allowsFollowUp: false),
            input: ActionInputRequirement(selection: .required),
            execution: .singleCapability(capabilityID: "test.lookup"),
            resolvedPermissions: [.localDictionary],
            budget: ActionBudget(maxModelCalls: 0, maxCapabilityCalls: 1),
            output: ActionOutputContract(kind: .text, format: .markdown)
        )

        let outcome = await runtime.execute(
            action: action,
            envelope: ContextEnvelope(selectedText: "Synthetic selection."),
            model: "test-model"
        )

        #expect(outcome.result == .failure(.capability(.permissionDenied)))
        #expect(outcome.trace.actionID == "community.lookup")
        #expect(outcome.trace.source == .package(version: SemanticVersion(1, 0, 0)))
        #expect(outcome.trace.modelCallCount == 0)
        #expect(outcome.trace.capabilityCallCount == 0)
        #expect(
            outcome.trace.termination
                == .rejected(code: "runtime.capability_not_authorized")
        )
        #expect(outcome.continuation == nil)
        #expect(await model.requests().isEmpty)
    }

    @Test func singleCapabilityInvokesOnlyTheAuthorizedCapability() async throws {
        let model = RecordingActionModelClient()
        let permission = deeplPermission
        let capability = RecordingRuntimeCapability(
            id: "translate.deepl",
            requiredPermissions: [permission],
            result: .success(.text("Translated selection."))
        )
        let invocation = AuthorizedCapabilityInvocation(
            actionID: "translate.action",
            capability: capability,
            permissions: [permission]
        )
        let input: CapabilityInput = .translate(
            TranslateCapabilityInput(
                selection: "Synthetic selection.",
                sourceLanguage: "EN",
                targetLanguage: "DE"
            )
        )
        let runtime = ActionWorkflowRuntime(modelClient: model)

        let outcome = await runtime.execute(
            action: capabilityAction,
            envelope: ContextEnvelope(
                selectedText: "Synthetic selection.",
                authorizedDocumentExcerpt: "Must not be sent.",
                hostDocumentTitle: "Must not be sent."
            ),
            model: "test-model",
            capabilityInvocation: invocation,
            capabilityInput: input
        )

        #expect(outcome.result == .success("Translated selection."))
        #expect(outcome.continuation == nil)
        #expect(outcome.trace.strategy == .singleCapability)
        #expect(outcome.trace.contextSources == [.selection])
        #expect(outcome.trace.resolvedPermissions == [permission])
        #expect(outcome.trace.modelCallCount == 0)
        #expect(outcome.trace.capabilityCallCount == 1)
        #expect(outcome.trace.destination == .network(host: "api-free.deepl.com"))
        #expect(outcome.trace.termination == .completed)
        #expect(await model.requests().isEmpty)
        #expect(await capability.inputs() == [input])
    }

    @Test func singleCapabilityRequiresAnInvocationResolvedForTheAction() async throws {
        let model = RecordingActionModelClient()
        let permission = deeplPermission
        let capability = RecordingRuntimeCapability(
            id: "translate.deepl",
            requiredPermissions: [permission]
        )
        let runtime = ActionWorkflowRuntime(modelClient: model)

        let outcome = await runtime.execute(
            action: capabilityAction,
            envelope: ContextEnvelope(selectedText: "Synthetic selection."),
            model: "test-model",
            capabilityInput: .translate(
                TranslateCapabilityInput(
                    selection: "Synthetic selection.",
                    sourceLanguage: nil,
                    targetLanguage: "DE"
                )
            )
        )

        #expect(outcome.result == .failure(.capability(.permissionDenied)))
        #expect(outcome.trace.capabilityCallCount == 0)
        #expect(
            outcome.trace.termination
                == .rejected(code: "runtime.capability_not_authorized")
        )
        #expect(await capability.inputs().isEmpty)
    }

    @Test func singleCapabilityReturnsTypedFailureWithoutLeakingInput() async throws {
        let model = RecordingActionModelClient()
        let permission = deeplPermission
        let capability = RecordingRuntimeCapability(
            id: "translate.deepl",
            requiredPermissions: [permission],
            result: .failure(.missingCredential)
        )
        let invocation = AuthorizedCapabilityInvocation(
            actionID: "translate.action",
            capability: capability,
            permissions: [permission]
        )
        let runtime = ActionWorkflowRuntime(modelClient: model)

        let outcome = await runtime.execute(
            action: capabilityAction,
            envelope: ContextEnvelope(selectedText: "Sensitive synthetic selection."),
            model: "test-model",
            capabilityInvocation: invocation,
            capabilityInput: .translate(
                TranslateCapabilityInput(
                    selection: "Sensitive synthetic selection.",
                    sourceLanguage: nil,
                    targetLanguage: "DE"
                )
            )
        )

        #expect(outcome.result == .failure(.capability(.missingCredential)))
        #expect(String(describing: outcome).contains("Sensitive synthetic selection.") == false)
        #expect(outcome.trace.capabilityCallCount == 1)
        #expect(outcome.trace.termination == .failed(code: "runtime.capability_failure"))
    }

    @Test func modelFailureIsReturnedWithTheConsumedBudget() async {
        let model = RecordingActionModelClient(result: .failure(.timeout))
        let runtime = ActionWorkflowRuntime(modelClient: model)

        let outcome = await runtime.execute(
            action: modelPromptAction(),
            envelope: ContextEnvelope(selectedText: "Synthetic selection."),
            model: "test-model"
        )

        #expect(outcome.result == .failure(.model(.timeout)))
        #expect(outcome.trace.modelCallCount == 1)
        #expect(outcome.trace.capabilityCallCount == 0)
        #expect(outcome.trace.termination == .failed(code: "runtime.model_failure"))
        #expect(outcome.continuation == nil)
    }

    @Test func modelCancellationTerminatesWithoutAnOutput() async {
        let model = RecordingActionModelClient(result: .failure(.cancelled))
        let runtime = ActionWorkflowRuntime(modelClient: model)

        let outcome = await runtime.execute(
            action: modelPromptAction(),
            envelope: ContextEnvelope(selectedText: "Synthetic selection."),
            model: "test-model"
        )

        #expect(outcome.result == .failure(.cancelled))
        #expect(outcome.trace.modelCallCount == 1)
        #expect(outcome.trace.termination == .cancelled)
        #expect(outcome.continuation == nil)
    }

    private func modelPromptAction(
        prompt: String = "Explain the selection."
    ) -> ResolvedAction {
        ResolvedAction(
            id: "custom-explain",
            source: .lens,
            display: ActionDisplayInfo(name: "Explain", allowsFollowUp: true),
            input: ActionInputRequirement(selection: .required),
            execution: .modelPrompt(prompt: prompt),
            resolvedPermissions: [.localModel],
            budget: ActionBudget(maxModelCalls: 1, maxCapabilityCalls: 0),
            output: ActionOutputContract(kind: .text, format: .markdown)
        )
    }

    private var capabilityAction: ResolvedAction {
        ResolvedAction(
            id: "translate.action",
            source: .package(version: SemanticVersion(1, 0, 0)),
            display: ActionDisplayInfo(name: "Translate", allowsFollowUp: false),
            input: ActionInputRequirement(selection: .required),
            execution: .singleCapability(capabilityID: "translate.deepl"),
            resolvedPermissions: [deeplPermission],
            budget: ActionBudget(maxModelCalls: 0, maxCapabilityCalls: 1),
            output: ActionOutputContract(kind: .text, format: .markdown)
        )
    }

    private var deeplPermission: ActionPermission {
        .network(
            host: "api-free.deepl.com",
            egress: ["selection", "sourceLanguage", "targetLanguage"]
        )
    }
}

private actor RuntimeEventRecorder {
    private var events: [ActionRuntimeEvent] = []

    func append(_ event: ActionRuntimeEvent) {
        events.append(event)
    }

    func values() -> [ActionRuntimeEvent] {
        events
    }
}

private actor RecordingActionModelClient: ActionModelClient {
    struct Request: Equatable, Sendable {
        let model: String
        let messages: [ChatMessage]
    }

    private let events: [ChatStreamEvent]
    private let result: Result<Void, ChatFailure>
    private var recordedRequests: [Request] = []

    init(
        events: [ChatStreamEvent] = [],
        result: Result<Void, ChatFailure> = .success(())
    ) {
        self.events = events
        self.result = result
    }

    func streamChat(
        model: String,
        messages: [ChatMessage],
        onEvent: @escaping @Sendable (ChatStreamEvent) async -> Void
    ) async -> Result<Void, ChatFailure> {
        recordedRequests.append(Request(model: model, messages: messages))
        for event in events {
            await onEvent(event)
        }
        return result
    }

    func requests() -> [Request] {
        recordedRequests
    }
}

private actor RecordingRuntimeCapability: Capability {
    nonisolated let descriptor: CapabilityDescriptor

    private let result: Result<CapabilityOutput, CapabilityError>
    private var recordedInputs: [CapabilityInput] = []

    init(
        id: String,
        requiredPermissions: [ActionPermission],
        result: Result<CapabilityOutput, CapabilityError> = .success(.text("Translated text."))
    ) {
        descriptor = CapabilityDescriptor(id: id, requiredPermissions: requiredPermissions)
        self.result = result
    }

    func invoke(_ input: CapabilityInput) async -> Result<CapabilityOutput, CapabilityError> {
        recordedInputs.append(input)
        return result
    }

    func inputs() -> [CapabilityInput] {
        recordedInputs
    }
}
