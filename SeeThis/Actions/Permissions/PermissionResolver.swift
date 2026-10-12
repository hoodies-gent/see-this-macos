import Foundation

nonisolated struct ActionPermissionGrants: Sendable {
    private let grantsByActionID: [String: Set<ActionPermission>]

    init(_ grants: [String: [ActionPermission]]) {
        grantsByActionID = grants.reduce(into: [:]) { result, entry in
            result[entry.key] = Set(entry.value)
        }
    }

    func contains(actionID: String, permission: ActionPermission) -> Bool {
        grantsByActionID[actionID]?.contains(permission) == true
    }
}

nonisolated enum PermissionResolverError: Error, Equatable, Sendable {
    case unknownCapability(String)
    case invalidPermissions
    case permissionNotDeclared(ActionPermission)
    case permissionNotRequired(ActionPermission)
    case destinationNotAllowlisted(host: String)
    case permissionNotGranted(ActionPermission)
}

nonisolated struct AuthorizedCapabilityInvocation: Sendable {
    let actionID: String
    let capability: any Capability
    let permissions: [ActionPermission]
}

nonisolated struct PermissionResolver: Sendable {
    private let allowedNetworkHosts: Set<String>

    init(allowedNetworkHosts: Set<String>) {
        self.allowedNetworkHosts = allowedNetworkHosts
    }

    func resolve(
        actionID: String,
        capabilityID: String,
        declaredPermissions: [ActionPermission],
        grants: ActionPermissionGrants,
        registry: CapabilityRegistry
    ) -> Result<AuthorizedCapabilityInvocation, PermissionResolverError> {
        guard case let .success(capability) = registry.resolve(capabilityID) else {
            return .failure(.unknownCapability(capabilityID))
        }

        let requiredPermissions = capability.descriptor.requiredPermissions
        guard Set(requiredPermissions).count == requiredPermissions.count,
              Set(declaredPermissions).count == declaredPermissions.count else {
            return .failure(.invalidPermissions)
        }

        for permission in requiredPermissions + declaredPermissions {
            if case let .network(host, _) = permission,
               !allowedNetworkHosts.contains(host) {
                return .failure(.destinationNotAllowlisted(host: host))
            }
        }

        if let missingPermission = requiredPermissions.first(
            where: { !declaredPermissions.contains($0) }
        ) {
            return .failure(.permissionNotDeclared(missingPermission))
        }
        if let extraPermission = declaredPermissions.first(
            where: { !requiredPermissions.contains($0) }
        ) {
            return .failure(.permissionNotRequired(extraPermission))
        }
        if let ungrantedPermission = requiredPermissions.first(
            where: { !grants.contains(actionID: actionID, permission: $0) }
        ) {
            return .failure(.permissionNotGranted(ungrantedPermission))
        }

        return .success(
            AuthorizedCapabilityInvocation(
                actionID: actionID,
                capability: capability,
                permissions: requiredPermissions
            )
        )
    }
}
