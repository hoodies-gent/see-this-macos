import Foundation

nonisolated enum TranslateActionCoordinatorError: Error, Equatable, Sendable {
    case packageNotFound
    case packageUnavailable(ActionPackageDiagnostic)
    case permission(PermissionResolverError)
}

nonisolated enum TranslateActionUserMessage {
    static func coordinatorFailure(_ error: TranslateActionCoordinatorError) -> String {
        switch error {
        case .permission(.permissionNotGranted(.network)):
            return "Authorize the DeepL destination in Settings before translating."
        case .permission:
            return "Translate with DeepL is unavailable."
        case .packageNotFound, .packageUnavailable:
            return "Translate with DeepL is unavailable."
        }
    }

    static func runtimeFailure(_ failure: ActionRuntimeFailure) -> String? {
        switch failure {
        case .cancelled, .capability(.cancelled):
            return nil
        case .capability(.missingCredential):
            return "Configure a DeepL credential in Settings before translating."
        case .capability(.permissionDenied), .capability(.destinationNotAllowed):
            return "Authorize the DeepL destination in Settings before translating."
        case .capability(.timeout):
            return "DeepL translation timed out."
        case .capability(.providerRejected):
            return "DeepL rejected the translation request."
        case .capability(.invalidResponse):
            return "DeepL returned an invalid response."
        case .capability(.transport):
            return "Could not reach DeepL. Check your connection and try again."
        case .capability(.invalidInput), .missingRequiredSelection:
            return "Select text before translating."
        case .model, .strategyUnavailable:
            return "Translation failed."
        }
    }
}

nonisolated struct TranslateActionCoordinator: Sendable {
    static let actionID = "translate"

    private let composition: CapabilityRuntimeComposition
    private let runtime: ActionWorkflowRuntime

    init(
        composition: CapabilityRuntimeComposition,
        modelClient: any ActionModelClient
    ) {
        self.composition = composition
        runtime = ActionWorkflowRuntime(modelClient: modelClient)
    }

    func execute(
        selection: String,
        sourceLanguage: String?,
        targetLanguage: String,
        model: String,
        grants: ActionPermissionGrants
    ) async -> Result<ActionExecutionOutcome, TranslateActionCoordinatorError> {
        let catalog = composition.loadPackages()
        guard let package = catalog.packages.first(where: { $0.manifest.id == Self.actionID }) else {
            return .failure(.packageNotFound)
        }
        guard package.isAvailable else {
            if case let .unavailable(diagnostic) = package.availability {
                return .failure(.packageUnavailable(diagnostic))
            }
            return .failure(.packageNotFound)
        }
        guard case let .resolved(action) = PackageActionResolver.resolve(package),
              case let .singleCapability(capabilityID) = action.execution else {
            return .failure(.packageNotFound)
        }

        let authorization = composition.permissionResolver.resolve(
            actionID: action.id,
            capabilityID: capabilityID,
            declaredPermissions: action.resolvedPermissions,
            grants: grants,
            registry: composition.registry
        )
        guard case let .success(invocation) = authorization else {
            if case let .failure(error) = authorization {
                return .failure(.permission(error))
            }
            return .failure(.permission(.unknownCapability(capabilityID)))
        }

        let outcome = await runtime.execute(
            action: action,
            envelope: ContextEnvelope(selectedText: selection),
            model: model,
            capabilityInvocation: invocation,
            capabilityInput: .translate(
                TranslateCapabilityInput(
                    selection: selection,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage
                )
            )
        )
        return .success(outcome)
    }
}
