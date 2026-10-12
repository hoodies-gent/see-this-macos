import Foundation

nonisolated struct CapabilityRuntimeComposition: Sendable {
    let registry: CapabilityRegistry
    let packageLoader: ActionPackageLoader
    let permissionResolver: PermissionResolver
    let directories: ActionPackageDirectories

    init(
        credentialStore: any CredentialStore,
        transport: any DeepLTransport,
        directories: ActionPackageDirectories,
        runtimeVersion: SemanticVersion,
        allowedNetworkHosts: Set<String>,
        endpoint: DeepLEndpoint = .free
    ) throws {
        let deepL = DeepLTranslationCapability(
            credentialStore: credentialStore,
            transport: transport,
            endpoint: endpoint
        )
        let registry = try CapabilityRegistry(capabilities: [deepL])
        let registeredIDs = Set(registry.registeredIDs)

        self.registry = registry
        self.directories = directories
        packageLoader = ActionPackageLoader(
            validator: ActionManifestValidator(
                runtimeVersion: runtimeVersion,
                knownCapabilityIDs: registeredIDs
            ),
            availableCapabilityIDs: registeredIDs
        )
        permissionResolver = PermissionResolver(
            allowedNetworkHosts: allowedNetworkHosts
        )
    }

    func loadPackages() -> ActionPackageCatalog {
        packageLoader.load(from: directories)
    }
}
