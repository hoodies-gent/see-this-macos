import Foundation

nonisolated enum CapabilityRegistryError: Error, Equatable, Sendable {
    case duplicateCapability(String)
    case unknownCapability(String)
}

nonisolated struct CapabilityRegistry: Sendable {
    private let capabilitiesByID: [String: any Capability]

    let registeredIDs: [String]

    init(capabilities: [any Capability]) throws {
        var capabilitiesByID: [String: any Capability] = [:]
        for capability in capabilities {
            let id = capability.descriptor.id
            guard capabilitiesByID[id] == nil else {
                throw CapabilityRegistryError.duplicateCapability(id)
            }
            capabilitiesByID[id] = capability
        }
        self.capabilitiesByID = capabilitiesByID
        registeredIDs = capabilitiesByID.keys.sorted()
    }

    func resolve(
        _ id: String
    ) -> Result<any Capability, CapabilityRegistryError> {
        guard let capability = capabilitiesByID[id] else {
            return .failure(.unknownCapability(id))
        }
        return .success(capability)
    }
}
