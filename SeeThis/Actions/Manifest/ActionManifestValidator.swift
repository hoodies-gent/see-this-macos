import Foundation

nonisolated struct ActionManifestValidator: Sendable {
    private let runtimeVersion: SemanticVersion
    private let knownCapabilityIDs: Set<String>

    init(runtimeVersion: SemanticVersion, knownCapabilityIDs: Set<String>) {
        self.runtimeVersion = runtimeVersion
        self.knownCapabilityIDs = knownCapabilityIDs
    }

    func validate(data: Data) -> ActionManifestValidationResult {
        let document: ManifestDocument
        do {
            document = try JSONDecoder().decode(ManifestDocument.self, from: data)
        } catch {
            return failure(
                .invalidJSON,
                "The action package manifest is not valid JSON."
            )
        }

        guard document.schemaVersion == 1 else {
            return failure(
                .unsupportedSchemaVersion,
                "Only action package schemaVersion 1 is supported."
            )
        }
        guard let id = document.id, Self.isValidIdentifier(id) else {
            return failure(
                .invalidIdentifier,
                "The action package id must contain only letters, numbers, periods, hyphens, or underscores."
            )
        }
        guard let versionString = document.version,
              let version = SemanticVersion(parsing: versionString),
              let minimumVersionString = document.minRuntimeVersion,
              let minimumVersion = SemanticVersion(parsing: minimumVersionString) else {
            return failure(
                .invalidVersion,
                "version and minRuntimeVersion must use major.minor.patch format."
            )
        }
        guard minimumVersion <= runtimeVersion else {
            return failure(
                .incompatibleRuntimeVersion,
                "This action package requires runtime \(minimumVersion) or newer; the current runtime is \(runtimeVersion)."
            )
        }
        guard let displayDocument = document.display,
              let name = displayDocument.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty,
              let allowsFollowUp = displayDocument.allowsFollowUp else {
            return failure(
                .invalidDisplay,
                "display.name and display.allowsFollowUp are required."
            )
        }

        guard let selection = document.input?.selection else {
            return failure(
                .missingSelectionRequirement,
                "input.selection is required."
            )
        }
        guard selection == "required" else {
            return failure(
                .invalidInputRequirement,
                "input.selection must be required."
            )
        }

        let executionResult = validateExecution(document.execution)
        guard case let .success(execution) = executionResult else {
            return executionResult.failureResult
        }

        let permissionsResult = validatePermissions(document.permissions)
        guard case let .success(permissions) = permissionsResult else {
            return permissionsResult.failureResult
        }
        if let mismatch = validatePermissionMatch(
            execution: execution,
            permissions: permissions
        ) {
            return ActionManifestValidationResult(manifest: nil, diagnostics: [mismatch])
        }

        guard let budgetDocument = document.budget,
              let maxModelCalls = budgetDocument.maxModelCalls,
              let maxCapabilityCalls = budgetDocument.maxCapabilityCalls,
              maxModelCalls >= 0,
              maxCapabilityCalls >= 0 else {
            return failure(
                .invalidBudget,
                "budget must declare non-negative maxModelCalls and maxCapabilityCalls."
            )
        }
        let budget = ActionBudget(
            maxModelCalls: maxModelCalls,
            maxCapabilityCalls: maxCapabilityCalls
        )
        guard budget == expectedBudget(for: execution) else {
            return failure(
                .invalidBudget,
                "budget does not match the fixed limit for the declared execution strategy."
            )
        }

        guard document.output?.kind == "text",
              document.output?.format == "markdown" else {
            return failure(
                .invalidOutput,
                "output must declare text with markdown format."
            )
        }

        let manifest = ActionManifestV1(
            schemaVersion: 1,
            id: id,
            version: version,
            minRuntimeVersion: minimumVersion,
            display: ActionDisplayInfo(name: name, allowsFollowUp: allowsFollowUp),
            input: ActionInputRequirement(selection: .required),
            execution: execution,
            permissions: permissions,
            budget: budget,
            output: ActionOutputContract(kind: .text, format: .markdown)
        )
        return ActionManifestValidationResult(manifest: manifest, diagnostics: [])
    }

    private func validateExecution(
        _ document: ExecutionDocument?
    ) -> Result<ActionPackageExecutionStrategy, ActionManifestDiagnostic> {
        guard let strategy = document?.strategy else {
            return .failure(
                ActionManifestDiagnostic(
                    code: .unknownStrategy,
                    message: "execution.strategy is required."
                )
            )
        }

        switch strategy {
        case "modelPrompt":
            return .failure(
                ActionManifestDiagnostic(
                    code: .forbiddenStrategy,
                    message: "Execution strategy 'modelPrompt' is reserved for internal Lens actions."
                )
            )

        case "singleCapability":
            guard let capabilityID = Self.nonEmpty(document?.capability) else {
                return .failure(
                    ActionManifestDiagnostic(
                        code: .invalidExecution,
                        message: "singleCapability execution requires one capability id."
                    )
                )
            }
            guard knownCapabilityIDs.contains(capabilityID) else {
                return .failure(unknownCapabilityDiagnostic(capabilityID))
            }
            return .success(.singleCapability(capabilityID: capabilityID))

        case "boundedAgent":
            guard let prompt = Self.nonEmpty(document?.prompt),
                  let capabilityIDs = document?.capabilities,
                  !capabilityIDs.isEmpty,
                  capabilityIDs.allSatisfy({ Self.nonEmpty($0) != nil }) else {
                return .failure(
                    ActionManifestDiagnostic(
                        code: .invalidExecution,
                        message: "boundedAgent execution requires a prompt and at least one capability id."
                    )
                )
            }
            if let unknownID = capabilityIDs.first(where: { !knownCapabilityIDs.contains($0) }) {
                return .failure(unknownCapabilityDiagnostic(unknownID))
            }
            return .success(
                .boundedAgent(prompt: prompt, capabilityIDs: capabilityIDs)
            )

        default:
            return .failure(
                ActionManifestDiagnostic(
                    code: .unknownStrategy,
                    message: "Unknown execution strategy '\(strategy)'."
                )
            )
        }
    }

    private func validatePermissions(
        _ documents: [PermissionDocument]?
    ) -> Result<[ActionPermission], ActionManifestDiagnostic> {
        guard let documents else {
            return .failure(
                ActionManifestDiagnostic(
                    code: .invalidPermission,
                    message: "permissions is required."
                )
            )
        }

        var permissions: [ActionPermission] = []
        for document in documents {
            switch document.kind {
            case "localModel":
                permissions.append(.localModel)
            case "localDictionary":
                permissions.append(.localDictionary)
            case "authorizedDocument":
                permissions.append(.authorizedDocument)
            case "network":
                guard let host = Self.nonEmpty(document.host),
                      let egress = document.egress,
                      !egress.isEmpty,
                      egress.allSatisfy({ Self.nonEmpty($0) != nil }) else {
                    return .failure(
                        ActionManifestDiagnostic(
                            code: .invalidPermission,
                            message: "network permission requires an exact host and at least one egress field."
                        )
                    )
                }
                permissions.append(.network(host: host, egress: egress))
            case let kind?:
                return .failure(
                    ActionManifestDiagnostic(
                        code: .unknownPermission,
                        message: "Unknown permission '\(kind)'."
                    )
                )
            case nil:
                return .failure(
                    ActionManifestDiagnostic(
                        code: .invalidPermission,
                        message: "Each permission requires a kind."
                    )
                )
            }
        }
        guard Set(permissions).count == permissions.count else {
            return .failure(
                ActionManifestDiagnostic(
                    code: .invalidPermission,
                    message: "permissions must not contain duplicates."
                )
            )
        }
        return .success(permissions)
    }

    private func validatePermissionMatch(
        execution: ActionPackageExecutionStrategy,
        permissions: [ActionPermission]
    ) -> ActionManifestDiagnostic? {
        let hasLocalModel = permissions.contains(.localModel)
        let matches: Bool
        switch execution {
        case .singleCapability:
            matches = !hasLocalModel && !permissions.isEmpty
        case .boundedAgent:
            matches = hasLocalModel && permissions.contains(where: { $0 != .localModel })
        }
        guard !matches else { return nil }
        return ActionManifestDiagnostic(
            code: .permissionStrategyMismatch,
            message: "permissions do not match the declared execution strategy."
        )
    }

    private func expectedBudget(for execution: ActionPackageExecutionStrategy) -> ActionBudget {
        switch execution {
        case .singleCapability:
            ActionBudget(maxModelCalls: 0, maxCapabilityCalls: 1)
        case .boundedAgent:
            ActionBudget(maxModelCalls: 2, maxCapabilityCalls: 1)
        }
    }

    private func unknownCapabilityDiagnostic(_ capabilityID: String) -> ActionManifestDiagnostic {
        ActionManifestDiagnostic(
            code: .unknownCapability,
            message: "Unknown capability '\(capabilityID)'."
        )
    }

    private func failure(
        _ code: ActionManifestDiagnostic.Code,
        _ message: String
    ) -> ActionManifestValidationResult {
        ActionManifestValidationResult(
            manifest: nil,
            diagnostics: [ActionManifestDiagnostic(code: code, message: message)]
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }
}

private extension Result where Failure == ActionManifestDiagnostic {
    var failureResult: ActionManifestValidationResult {
        switch self {
        case .success:
            preconditionFailure("failureResult is only valid for a failed result")
        case let .failure(diagnostic):
            ActionManifestValidationResult(manifest: nil, diagnostics: [diagnostic])
        }
    }
}

private nonisolated struct ManifestDocument: Decodable {
    let schemaVersion: Int?
    let id: String?
    let version: String?
    let minRuntimeVersion: String?
    let display: DisplayDocument?
    let input: InputDocument?
    let execution: ExecutionDocument?
    let permissions: [PermissionDocument]?
    let budget: BudgetDocument?
    let output: OutputDocument?
}

private nonisolated struct DisplayDocument: Decodable {
    let name: String?
    let allowsFollowUp: Bool?
}

private nonisolated struct InputDocument: Decodable {
    let selection: String?
}

private nonisolated struct ExecutionDocument: Decodable {
    let strategy: String?
    let prompt: String?
    let capability: String?
    let capabilities: [String]?
}

private nonisolated struct PermissionDocument: Decodable {
    let kind: String?
    let host: String?
    let egress: [String]?
}

private nonisolated struct BudgetDocument: Decodable {
    let maxModelCalls: Int?
    let maxCapabilityCalls: Int?
}

private nonisolated struct OutputDocument: Decodable {
    let kind: String?
    let format: String?
}
