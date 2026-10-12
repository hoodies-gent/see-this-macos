import Foundation

nonisolated enum PackageActionResolution: Equatable, Sendable {
    case resolved(ResolvedAction)
    case unavailable(ActionPackageDiagnostic)
}

nonisolated enum PackageActionResolver {
    static func resolve(_ package: LoadedActionPackage) -> PackageActionResolution {
        if case let .unavailable(diagnostic) = package.availability {
            return .unavailable(diagnostic)
        }

        let manifest = package.manifest
        return .resolved(
            ResolvedAction(
                id: manifest.id,
                source: .package(version: manifest.version),
                display: manifest.display,
                input: manifest.input,
                execution: resolvedExecution(manifest.execution),
                resolvedPermissions: manifest.permissions,
                budget: manifest.budget,
                output: manifest.output
            )
        )
    }

    private static func resolvedExecution(
        _ execution: ActionPackageExecutionStrategy
    ) -> ResolvedActionExecution {
        switch execution {
        case let .singleCapability(capabilityID):
            .singleCapability(capabilityID: capabilityID)
        case let .boundedAgent(prompt, capabilityIDs):
            .boundedAgent(prompt: prompt, capabilityIDs: capabilityIDs)
        }
    }
}
