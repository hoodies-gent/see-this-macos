import Testing
@testable import SeeThis

struct PermissionResolverTests {

    @Test func authorizesARegisteredCapabilityOnlyWithItsDeclaredAndGrantedPermission() throws {
        let permission = deeplPermission
        let capability = TestPermissionCapability(
            id: "test.translate",
            requiredPermissions: [permission]
        )
        let registry = try CapabilityRegistry(capabilities: [capability])
        let grants = ActionPermissionGrants([
            "translate.action": [permission]
        ])

        let result = PermissionResolver(
            allowedNetworkHosts: ["api-free.deepl.com"]
        ).resolve(
            actionID: "translate.action",
            capabilityID: "test.translate",
            declaredPermissions: [permission],
            grants: grants,
            registry: registry
        )

        guard case let .success(invocation) = result else {
            Issue.record("Expected the exact declared and granted permission to authorize")
            return
        }
        #expect(invocation.actionID == "translate.action")
        #expect(invocation.permissions == [permission])
        #expect(invocation.capability.descriptor.id == "test.translate")
    }

    @Test func rejectsAnUnknownCapabilityBeforeCheckingPermissions() throws {
        let permission = deeplPermission
        let registry = try CapabilityRegistry(capabilities: [])
        let grants = ActionPermissionGrants([
            "translate.action": [permission]
        ])

        let result = PermissionResolver(
            allowedNetworkHosts: ["api-free.deepl.com"]
        ).resolve(
            actionID: "translate.action",
            capabilityID: "unknown.capability",
            declaredPermissions: [permission],
            grants: grants,
            registry: registry
        )

        expectFailure(result, .unknownCapability("unknown.capability"))
    }

    @Test func rejectsARequiredPermissionMissingFromTheManifest() throws {
        let permission = deeplPermission
        let capability = TestPermissionCapability(
            id: "test.translate",
            requiredPermissions: [permission]
        )
        let registry = try CapabilityRegistry(capabilities: [capability])
        let grants = ActionPermissionGrants([
            "translate.action": [permission]
        ])

        let result = PermissionResolver(
            allowedNetworkHosts: ["api-free.deepl.com"]
        ).resolve(
            actionID: "translate.action",
            capabilityID: "test.translate",
            declaredPermissions: [],
            grants: grants,
            registry: registry
        )

        expectFailure(result, .permissionNotDeclared(permission))
    }

    @Test func rejectsADeclaredPermissionThatTheCapabilityDoesNotRequire() throws {
        let requiredPermission = ActionPermission.localDictionary
        let extraPermission = deeplPermission
        let capability = TestPermissionCapability(
            id: "test.dictionary",
            requiredPermissions: [requiredPermission]
        )
        let registry = try CapabilityRegistry(capabilities: [capability])
        let grants = ActionPermissionGrants([
            "lookup.action": [requiredPermission, extraPermission]
        ])

        let result = PermissionResolver(
            allowedNetworkHosts: ["api-free.deepl.com"]
        ).resolve(
            actionID: "lookup.action",
            capabilityID: "test.dictionary",
            declaredPermissions: [requiredPermission, extraPermission],
            grants: grants,
            registry: registry
        )

        expectFailure(result, .permissionNotRequired(extraPermission))
    }

    @Test func rejectsANetworkDestinationOutsideTheAppAllowlist() throws {
        let permission = ActionPermission.network(
            host: "evil.example.com",
            egress: ["selection"]
        )
        let capability = TestPermissionCapability(
            id: "test.translate",
            requiredPermissions: [permission]
        )
        let registry = try CapabilityRegistry(capabilities: [capability])
        let grants = ActionPermissionGrants([
            "translate.action": [permission]
        ])

        let result = PermissionResolver(
            allowedNetworkHosts: ["api-free.deepl.com"]
        ).resolve(
            actionID: "translate.action",
            capabilityID: "test.translate",
            declaredPermissions: [permission],
            grants: grants,
            registry: registry
        )

        expectFailure(
            result,
            .destinationNotAllowlisted(host: "evil.example.com")
        )
    }

    @Test func doesNotReuseAGrantedPermissionAcrossActions() throws {
        let permission = deeplPermission
        let capability = TestPermissionCapability(
            id: "test.translate",
            requiredPermissions: [permission]
        )
        let registry = try CapabilityRegistry(capabilities: [capability])
        let grants = ActionPermissionGrants([
            "other.action": [permission]
        ])

        let result = PermissionResolver(
            allowedNetworkHosts: ["api-free.deepl.com"]
        ).resolve(
            actionID: "translate.action",
            capabilityID: "test.translate",
            declaredPermissions: [permission],
            grants: grants,
            registry: registry
        )

        expectFailure(result, .permissionNotGranted(permission))
    }

    private var deeplPermission: ActionPermission {
        .network(
            host: "api-free.deepl.com",
            egress: ["selection", "sourceLanguage", "targetLanguage"]
        )
    }

    private func expectFailure(
        _ result: Result<AuthorizedCapabilityInvocation, PermissionResolverError>,
        _ expected: PermissionResolverError
    ) {
        guard case let .failure(error) = result else {
            Issue.record("Expected permission resolution to fail with \(expected)")
            return
        }
        #expect(error == expected)
    }
}

private struct TestPermissionCapability: Capability {
    let descriptor: CapabilityDescriptor

    init(id: String, requiredPermissions: [ActionPermission]) {
        descriptor = CapabilityDescriptor(
            id: id,
            requiredPermissions: requiredPermissions
        )
    }

    func invoke(
        _ input: CapabilityInput
    ) async -> Result<CapabilityOutput, CapabilityError> {
        .failure(.invalidInput)
    }
}
