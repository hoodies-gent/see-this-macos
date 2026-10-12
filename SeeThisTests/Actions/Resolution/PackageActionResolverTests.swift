import Testing
@testable import SeeThis

struct PackageActionResolverTests {

    @Test func resolvesAvailableSingleCapabilityPackageWithoutWideningAuthority() {
        let package = makePackage(
            execution: .singleCapability(capabilityID: "test.dictionary"),
            permissions: [.localDictionary],
            budget: ActionBudget(maxModelCalls: 0, maxCapabilityCalls: 1)
        )

        let resolution = PackageActionResolver.resolve(package)

        #expect(
            resolution == .resolved(
                ResolvedAction(
                    id: "community.lookup",
                    source: .package(version: SemanticVersion(1, 2, 3)),
                    display: ActionDisplayInfo(name: "Lookup", allowsFollowUp: false),
                    input: ActionInputRequirement(selection: .required),
                    execution: .singleCapability(capabilityID: "test.dictionary"),
                    resolvedPermissions: [.localDictionary],
                    budget: ActionBudget(maxModelCalls: 0, maxCapabilityCalls: 1),
                    output: ActionOutputContract(kind: .text, format: .markdown)
                )
            )
        )
    }

    @Test func resolvesAvailableBoundedAgentPackageWithoutChangingItsLimits() {
        let package = makePackage(
            execution: .boundedAgent(
                prompt: "Use the capability only when needed.",
                capabilityIDs: ["test.dictionary"]
            ),
            permissions: [.localModel, .localDictionary],
            budget: ActionBudget(maxModelCalls: 2, maxCapabilityCalls: 1)
        )

        let resolution = PackageActionResolver.resolve(package)

        guard case let .resolved(action) = resolution else {
            Issue.record("Expected the available package to resolve")
            return
        }
        #expect(
            action.execution == .boundedAgent(
                prompt: "Use the capability only when needed.",
                capabilityIDs: ["test.dictionary"]
            )
        )
        #expect(action.resolvedPermissions == [.localModel, .localDictionary])
        #expect(action.budget == ActionBudget(maxModelCalls: 2, maxCapabilityCalls: 1))
    }

    @Test func unavailablePackageDoesNotProduceAResolvedAction() {
        let diagnostic = ActionPackageDiagnostic(
            code: "package.capability_unavailable",
            message: "Required capability 'test.dictionary' is not available.",
            fileName: "lookup.json"
        )
        let package = makePackage(
            execution: .singleCapability(capabilityID: "test.dictionary"),
            permissions: [.localDictionary],
            budget: ActionBudget(maxModelCalls: 0, maxCapabilityCalls: 1),
            availability: .unavailable(diagnostic)
        )

        let resolution = PackageActionResolver.resolve(package)

        #expect(resolution == .unavailable(diagnostic))
    }

    private func makePackage(
        execution: ActionPackageExecutionStrategy,
        permissions: [ActionPermission],
        budget: ActionBudget,
        availability: ActionPackageAvailability = .available
    ) -> LoadedActionPackage {
        LoadedActionPackage(
            manifest: ActionManifestV1(
                schemaVersion: 1,
                id: "community.lookup",
                version: SemanticVersion(1, 2, 3),
                minRuntimeVersion: SemanticVersion(1, 0, 0),
                display: ActionDisplayInfo(name: "Lookup", allowsFollowUp: false),
                input: ActionInputRequirement(selection: .required),
                execution: execution,
                permissions: permissions,
                budget: budget,
                output: ActionOutputContract(kind: .text, format: .markdown)
            ),
            origin: .user,
            fileURL: nil,
            availability: availability
        )
    }
}
