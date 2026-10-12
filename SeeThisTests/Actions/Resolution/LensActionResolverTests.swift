import Foundation
import Testing
@testable import SeeThis

struct LensActionResolverTests {

    @Test @MainActor func readerActionRepresentsLensAndPackageActionsWithOneDisplayContract() {
        let lens = ReaderAction.lens(.plain)
        let package = ReaderAction.package(
            ResolvedAction(
                id: "translate",
                source: .package(version: SemanticVersion(1, 0, 0)),
                display: ActionDisplayInfo(name: "Translate with DeepL", allowsFollowUp: false),
                input: ActionInputRequirement(selection: .required),
                execution: .singleCapability(capabilityID: "translate.deepl"),
                resolvedPermissions: [
                    .network(host: "api-free.deepl.com", egress: ["selection", "targetLanguage"])
                ],
                budget: ActionBudget(maxModelCalls: 0, maxCapabilityCalls: 1),
                output: ActionOutputContract(kind: .text, format: .markdown)
            )
        )

        #expect(lens.id == ExplanationLens.plain.id)
        #expect(lens.display.name == ExplanationLens.plain.displayName)
        #expect(lens.display.allowsFollowUp == ExplanationLens.plain.allowsFollowUp)
        #expect(package.id == "translate")
        #expect(package.display.name == "Translate with DeepL")
        #expect(package.display.allowsFollowUp == false)
    }

    @Test @MainActor func overlayStateProjectsLensSelectionThroughReaderAction() throws {
        let secondLens = ExplanationLens.custom(displayName: "Synthetic focus", preference: "Synthetic.")
        let state = OverlayContentState.choosingLens(
            lenses: [.plain, secondLens],
            usesPaperContext: false
        )

        #expect(state.actionOptions.map(\.id) == ["plain", secondLens.id])
        #expect(state.selectedAction == nil)

        let requesting = try #require(
            state.requestingContent(for: .lens(secondLens))
        )
        #expect(requesting.selectedAction?.id == secondLens.id)
        #expect(requesting.selectedAction?.display.name == "Synthetic focus")
    }

    @Test @MainActor func overlayStateRejectsPackageActionUntilPackagePresentationIsConfigured() {
        let state = OverlayContentState.choosingLens(
            lenses: [.plain],
            usesPaperContext: false
        )
        let package = ReaderAction.package(
            ResolvedAction(
                id: "translate",
                source: .package(version: SemanticVersion(1, 0, 0)),
                display: ActionDisplayInfo(name: "Translate with DeepL", allowsFollowUp: false),
                input: ActionInputRequirement(selection: .required),
                execution: .singleCapability(capabilityID: "translate.deepl"),
                resolvedPermissions: [],
                budget: ActionBudget(maxModelCalls: 0, maxCapabilityCalls: 1),
                output: ActionOutputContract(kind: .text, format: .markdown)
            )
        )

        #expect(state.requestingContent(for: package) == nil)
    }

    @Test @MainActor func interactionPresentationKeepsUnifiedActionsBeforeOverlayMigration() {
        let package = ReaderAction.package(
            ResolvedAction(
                id: "translate",
                source: .package(version: SemanticVersion(1, 0, 0)),
                display: ActionDisplayInfo(name: "Translate with DeepL", allowsFollowUp: false),
                input: ActionInputRequirement(selection: .required),
                execution: .singleCapability(capabilityID: "translate.deepl"),
                resolvedPermissions: [],
                budget: ActionBudget(maxModelCalls: 0, maxCapabilityCalls: 1),
                output: ActionOutputContract(kind: .text, format: .markdown)
            )
        )

        let presentation = InteractionPresentation(
            actions: [.lens(.plain), package],
            selectedAction: package,
            usesPaperContext: false,
            model: "test-model"
        )

        #expect(presentation.actions.map(\.id) == ["plain", "translate"])
        #expect(presentation.selectedAction?.id == "translate")
        #expect(presentation.lenses == [.plain])
        #expect(presentation.selectedLens == nil)
    }

    @Test func readerActionCatalogKeepsLensOrderAndAddsResolvedPackages() {
        let package = LoadedActionPackage(
            manifest: ActionManifestV1(
                schemaVersion: 1,
                id: "translate",
                version: SemanticVersion(1, 0, 0),
                minRuntimeVersion: SemanticVersion(1, 0, 0),
                display: ActionDisplayInfo(name: "Translate with DeepL", allowsFollowUp: false),
                input: ActionInputRequirement(selection: .required),
                execution: .singleCapability(capabilityID: "translate.deepl"),
                permissions: [],
                budget: ActionBudget(maxModelCalls: 0, maxCapabilityCalls: 1),
                output: ActionOutputContract(kind: .text, format: .markdown)
            ),
            origin: .bundled,
            fileURL: nil,
            availability: .available
        )

        let actions = ReaderActionCatalog.resolve(
            lenses: [.plain],
            packages: [package]
        )

        #expect(actions.map(\.id) == ["plain", "translate"])
        #expect(actions.last?.display.name == "Translate with DeepL")
    }

    @Test func readerActionCatalogMarksUnconfiguredPackagesDisabled() {
        let package = LoadedActionPackage(
            manifest: ActionManifestV1(
                schemaVersion: 1,
                id: "translate",
                version: SemanticVersion(1, 0, 0),
                minRuntimeVersion: SemanticVersion(1, 0, 0),
                display: ActionDisplayInfo(name: "Translate with DeepL", allowsFollowUp: false),
                input: ActionInputRequirement(selection: .required),
                execution: .singleCapability(capabilityID: "translate.deepl"),
                permissions: [],
                budget: ActionBudget(maxModelCalls: 0, maxCapabilityCalls: 1),
                output: ActionOutputContract(kind: .text, format: .markdown)
            ),
            origin: .bundled,
            fileURL: nil,
            availability: .available
        )

        let options = ReaderActionCatalog.options(
            lenses: [.plain],
            packages: [package],
            enabledPackageIDs: []
        )

        #expect(options.map(\.id) == ["plain", "translate"])
        #expect(options[0].availability == .enabled)
        #expect(options[1].availability == .disabled(reason: .externalActionNotConfigured))
    }

    @Test func readerActionCatalogProjectsOnlyVisibleEnabledActionsInStoredOrder() {
        let packageAction = ResolvedAction(
            id: "translate",
            source: .package(version: SemanticVersion(1, 0, 0)),
            display: ActionDisplayInfo(name: "Translate with DeepL", allowsFollowUp: false),
            input: ActionInputRequirement(selection: .required),
            execution: .singleCapability(capabilityID: "translate.deepl"),
            resolvedPermissions: [],
            budget: ActionBudget(maxModelCalls: 0, maxCapabilityCalls: 1),
            output: ActionOutputContract(kind: .text, format: .markdown)
        )
        let actions: [ReaderAction] = [
            .lens(.plain),
            .lens(.translation(targetLanguage: "German")),
            .package(packageAction)
        ]

        let enabled = ReaderActionCatalog.options(
            actions: actions,
            orderedIDs: ["translate", "plain", "translate-local"],
            visibleIDs: ["translate", "plain", "translate-local"],
            enabledPackageIDs: ["translate"]
        )
        let packageUnavailable = ReaderActionCatalog.options(
            actions: actions,
            orderedIDs: ["translate", "plain", "translate-local"],
            visibleIDs: ["translate", "plain", "translate-local"],
            enabledPackageIDs: []
        )
        let packageHidden = ReaderActionCatalog.options(
            actions: actions,
            orderedIDs: ["translate", "plain", "translate-local"],
            visibleIDs: ["plain", "translate-local"],
            enabledPackageIDs: ["translate"]
        )

        #expect(enabled.map(\.id) == ["translate", "plain", "translate-local"])
        #expect(enabled.allSatisfy { $0.isEnabled })
        #expect(packageUnavailable.map(\.id) == ["plain", "translate-local"])
        #expect(packageHidden.map(\.id) == ["plain", "translate-local"])
    }

    @Test @MainActor func resolvesLocalTranslationLensIntoOneLocalModelCall() {
        let lens = ExplanationLens.translation(targetLanguage: "German")

        let action = LensActionResolver.resolve(lens)

        #expect(action.id == "translate-local")
        #expect(action.source == .lens)
        #expect(action.display.name == "Translate")
        #expect(action.display.allowsFollowUp == false)
        #expect(action.input.selection == .required)
        #expect(
            action.execution == .modelPrompt(
                prompt: "Translate the selected passage into German. Preserve academic terminology, proper nouns, symbols, formulas, citations, and formatting. Return only the translation; do not explain or summarize.",
                framing: .productOwned
            )
        )
        #expect(action.resolvedPermissions == [.localModel])
        #expect(action.budget == ActionBudget(maxModelCalls: 1, maxCapabilityCalls: 0))
    }

    @Test @MainActor func resolvesTargetLanguageVariableInACustomLensPrompt() {
        let lens = ExplanationLens(
            id: "custom-translation",
            displayName: "Careful translation",
            preference: "Translate into {{target_language}} and preserve terminology.",
            kind: .custom
        )

        let action = LensActionResolver.resolve(lens, targetLanguage: "Japanese")

        #expect(
            action.execution == .modelPrompt(
                prompt: "Translate into Japanese and preserve terminology.",
                framing: .readerAuthored
            )
        )
    }

    @Test @MainActor func resolvesBuiltInLensesIntoFixedLocalModelActions() {
        let fixture = isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let store = LensStore(defaults: fixture.defaults)

        let projection = LensActionResolver.project(store: store, targetLanguage: "German")

        #expect(
            projection.actions.map(\.id)
                == ["plain", "translate-local"]
        )
        #expect(projection.inlineActionIDs == projection.actions.map(\.id))
        #expect(projection.defaultActionID == nil)

        let projectedLenses: [ExplanationLens] = [
            .plain,
            .translation(targetLanguage: "German")
        ]
        for (lens, action) in zip(projectedLenses, projection.actions) {
            #expect(action.source == .lens)
            #expect(action.id == lens.id)
            #expect(action.display.name == lens.displayName)
            #expect(action.display.allowsFollowUp == lens.allowsFollowUp)
            #expect(action.input.selection == .required)
            #expect(
                action.execution == .modelPrompt(
                    prompt: lens.preference,
                    framing: lens.isBuiltIn ? .productOwned : .readerAuthored
                )
            )
            #expect(action.resolvedPermissions == [.localModel])
            #expect(action.budget == ActionBudget(maxModelCalls: 1, maxCapabilityCalls: 0))
            #expect(action.output == ActionOutputContract(kind: .text, format: .markdown))
        }
    }

    @Test @MainActor func preservesStoredCustomLensOrderDefaultPromptAndFollowUp() throws {
        let fixture = isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let customID = "legacy-custom-id"
        let payload: [String: Any] = [
            "customLenses": [[
                "id": customID,
                "displayName": "Legacy focus",
                "preference": "Use the exact legacy prompt.",
                "kind": "custom",
                "allowsFollowUp": false
            ]],
            "removedBuiltInLensIDs": [],
            "inlineLensIDs": ["plain", customID],
            "defaultLensID": customID,
            "selectedOllamaModel": OllamaProvider.defaultModelName,
            "lensOrder": [customID, "plain", "define-terms", "argument-role", "uncertainty-focus"]
        ]
        fixture.defaults.set(
            try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
            forKey: "explanationLensSettings"
        )
        let store = LensStore(defaults: fixture.defaults)

        let projection = LensActionResolver.project(store: store, targetLanguage: "German")
        let customAction = try #require(
            projection.actions.first(where: { $0.id == customID })
        )

        #expect(projection.actions.first?.id == customID)
        #expect(projection.inlineActionIDs == [customID, "plain", "translate-local"])
        #expect(projection.defaultActionID == customID)
        #expect(customAction.source == .lens)
        #expect(customAction.display.name == "Legacy focus")
        #expect(customAction.display.allowsFollowUp == false)
        #expect(
            customAction.execution == .modelPrompt(
                prompt: "Use the exact legacy prompt.",
                framing: .readerAuthored
            )
        )
        #expect(customAction.resolvedPermissions == [.localModel])
        #expect(customAction.budget == ActionBudget(maxModelCalls: 1, maxCapabilityCalls: 0))
    }

    @Test @MainActor func removedBuiltInLensDoesNotResolveIntoAnAction() {
        let fixture = isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let store = LensStore(defaults: fixture.defaults)
        store.addCustomLens(displayName: "Synthetic focus", preference: "Synthetic.")
        #expect(store.removeLens(id: "plain"))

        let projection = LensActionResolver.project(store: store, targetLanguage: "German")

        #expect(!projection.actions.contains { $0.id == "plain" })
        #expect(!projection.inlineActionIDs.contains("plain"))
    }

    @Test @MainActor func resolvedLensExecutesThroughTheWorkflowRuntimeOnce() async throws {
        let model = LensRuntimeRecordingModelClient(
            events: [.fragment("Runtime answer."), .finished]
        )
        let action = LensActionResolver.resolve(.plain)

        let outcome = await ActionWorkflowRuntime(modelClient: model).execute(
            action: action,
            envelope: ContextEnvelope(
                selectedText: "Synthetic selection.",
                authorizedDocumentExcerpt: "Authorized excerpt.",
                hostDocumentTitle: "Document title"
            ),
            model: "test-model"
        )

        #expect(outcome.result == .success("Runtime answer."))
        #expect(outcome.trace.actionID == ExplanationLens.plain.id)
        #expect(outcome.trace.source == .lens)
        #expect(outcome.trace.modelCallCount == 1)
        #expect(outcome.continuation != nil)

        let requests = await model.requests()
        let request = try #require(requests.first)
        #expect(requests.count == 1)
        #expect(
            request.messages == buildPassageMessages(
                passage: "Synthetic selection.",
                paperTitle: "Document title",
                localContext: "Authorized excerpt.",
                intent: .lens(.plain)
            )
        )
    }

    @Test @MainActor func customLensRuntimeMessagesPreserveReaderPreferenceFraming() async throws {
        let model = LensRuntimeRecordingModelClient(events: [])
        let lens = ExplanationLens(
            id: "custom-focus",
            displayName: "Custom focus",
            preference: "Use the exact reader-authored preference.",
            kind: .custom
        )

        _ = await ActionWorkflowRuntime(modelClient: model).execute(
            action: LensActionResolver.resolve(lens),
            envelope: ContextEnvelope(selectedText: "Synthetic selection."),
            model: "test-model"
        )

        let request = try #require(await model.requests().first)
        #expect(
            request.messages == buildPassageMessages(
                passage: "Synthetic selection.",
                intent: .lens(lens)
            )
        )
    }

    private func isolatedDefaults() -> (suiteName: String, defaults: UserDefaults) {
        let suiteName = "LensActionResolverTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (suiteName, defaults)
    }
}

private actor LensRuntimeRecordingModelClient: ActionModelClient {
    struct Request: Equatable, Sendable {
        let model: String
        let messages: [ChatMessage]
    }

    private let events: [ChatStreamEvent]
    private var recordedRequests: [Request] = []

    init(events: [ChatStreamEvent]) {
        self.events = events
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
        return .success(())
    }

    func requests() -> [Request] {
        recordedRequests
    }
}
