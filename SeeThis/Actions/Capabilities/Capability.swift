import Foundation

nonisolated struct TranslateCapabilityInput: Equatable, Sendable {
    let selection: String
    let sourceLanguage: String?
    let targetLanguage: String
}

nonisolated enum CapabilityInput: Equatable, Sendable {
    case translate(TranslateCapabilityInput)
}

nonisolated enum CapabilityOutput: Equatable, Sendable {
    case text(String)
}

nonisolated enum CapabilityError: Error, Equatable, Sendable {
    case invalidInput
    case missingCredential
    case permissionDenied
    case destinationNotAllowed
    case providerRejected(statusCode: Int)
    case invalidResponse
    case transport
    case timeout
    case cancelled
}

nonisolated struct CapabilityDescriptor: Equatable, Sendable {
    let id: String
    let requiredPermissions: [ActionPermission]
}

nonisolated protocol Capability: Sendable {
    var descriptor: CapabilityDescriptor { get }

    func invoke(
        _ input: CapabilityInput
    ) async -> Result<CapabilityOutput, CapabilityError>
}
