import Foundation

nonisolated struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init?(parsing value: String) {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2]) else {
            return nil
        }
        self.init(major, minor, patch)
    }

    var description: String {
        "\(major).\(minor).\(patch)"
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

nonisolated struct ActionManifestV1: Equatable, Sendable {
    let schemaVersion: Int
    let id: String
    let version: SemanticVersion
    let minRuntimeVersion: SemanticVersion
    let display: ActionDisplayInfo
    let input: ActionInputRequirement
    let execution: ActionPackageExecutionStrategy
    let permissions: [ActionPermission]
    let budget: ActionBudget
    let output: ActionOutputContract
}

nonisolated struct ActionDisplayInfo: Equatable, Sendable {
    let name: String
    let allowsFollowUp: Bool
}

nonisolated struct ActionInputRequirement: Equatable, Sendable {
    enum Selection: Equatable, Sendable {
        case required
    }

    let selection: Selection
}

nonisolated enum ActionPackageExecutionStrategy: Equatable, Sendable {
    case singleCapability(capabilityID: String)
    case boundedAgent(prompt: String, capabilityIDs: [String])
}

nonisolated enum ActionPermission: Equatable, Hashable, Sendable {
    case localModel
    case localDictionary
    case authorizedDocument
    case network(host: String, egress: [String])
}

nonisolated struct ActionBudget: Equatable, Sendable {
    let maxModelCalls: Int
    let maxCapabilityCalls: Int
}

nonisolated struct ActionOutputContract: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case text
    }

    enum Format: Equatable, Sendable {
        case markdown
    }

    let kind: Kind
    let format: Format
}

nonisolated struct ActionManifestDiagnostic: Error, Equatable, Sendable, CustomStringConvertible {
    enum Code: String, Equatable, Sendable {
        case invalidJSON = "manifest.invalid_json"
        case unsupportedSchemaVersion = "manifest.unsupported_schema_version"
        case invalidIdentifier = "manifest.invalid_id"
        case invalidVersion = "manifest.invalid_version"
        case incompatibleRuntimeVersion = "manifest.incompatible_runtime_version"
        case invalidDisplay = "manifest.invalid_display"
        case missingSelectionRequirement = "manifest.missing_selection_requirement"
        case invalidInputRequirement = "manifest.invalid_input_requirement"
        case unknownStrategy = "manifest.unknown_strategy"
        case forbiddenStrategy = "manifest.forbidden_strategy"
        case invalidExecution = "manifest.invalid_execution"
        case unknownCapability = "manifest.unknown_capability"
        case unknownPermission = "manifest.unknown_permission"
        case invalidPermission = "manifest.invalid_permission"
        case permissionStrategyMismatch = "manifest.permission_strategy_mismatch"
        case invalidBudget = "manifest.invalid_budget"
        case invalidOutput = "manifest.invalid_output"
    }

    let code: Code
    let message: String

    var description: String {
        "\(code.rawValue): \(message)"
    }
}

nonisolated struct ActionManifestValidationResult: Equatable, Sendable {
    let manifest: ActionManifestV1?
    let diagnostics: [ActionManifestDiagnostic]
}
