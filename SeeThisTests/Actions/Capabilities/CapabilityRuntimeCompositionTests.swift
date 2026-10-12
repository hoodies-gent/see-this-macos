import Foundation
import Testing
@testable import SeeThis

struct CapabilityRuntimeCompositionTests {
    @Test func registersDeepLAndResolvesTheBundledTranslateContract() throws {
        let workspace = try PackageWorkspace()
        defer { workspace.remove() }
        try workspace.writeTranslateManifest()

        let composition = try CapabilityRuntimeComposition(
            credentialStore: EmptyCredentialStore(),
            transport: EmptyDeepLTransport(),
            directories: workspace.directories,
            runtimeVersion: SemanticVersion(1, 0, 0),
            allowedNetworkHosts: ["api-free.deepl.com"]
        )

        #expect(composition.registry.registeredIDs == [DeepLTranslationCapability.capabilityID])
        let catalog = composition.loadPackages()
        let package = try #require(catalog.packages.first)
        #expect(package.manifest.id == "translate")
        #expect(package.isAvailable)

        let resolution = PackageActionResolver.resolve(package)
        guard case let .resolved(action) = resolution else {
            Issue.record("Expected the available Translate package to resolve.")
            return
        }
        guard case let .network(host, egress) = action.resolvedPermissions[0] else {
            Issue.record("Expected Translate to declare a network permission.")
            return
        }
        let grants = ActionPermissionGrants([
            action.id: [.network(host: host, egress: egress)]
        ])

        let authorization = composition.permissionResolver.resolve(
            actionID: action.id,
            capabilityID: "translate.deepl",
            declaredPermissions: action.resolvedPermissions,
            grants: grants,
            registry: composition.registry
        )

        guard case let .success(invocation) = authorization else {
            Issue.record("Expected explicit Translate permission to authorize.")
            return
        }
        #expect(invocation.actionID == "translate")
        #expect(invocation.capability.descriptor.id == "translate.deepl")
        #expect(invocation.permissions == action.resolvedPermissions)
    }
}

private struct EmptyCredentialStore: CredentialStore {
    func read(_ key: CredentialKey) -> Result<String?, CredentialStoreError> {
        .success(nil)
    }

    func write(_ credential: String, for key: CredentialKey) -> Result<Void, CredentialStoreError> {
        .success(())
    }

    func delete(_ key: CredentialKey) -> Result<Void, CredentialStoreError> {
        .success(())
    }
}

private struct EmptyDeepLTransport: DeepLTransport {
    func send(_ request: DeepLRequest) async -> Result<DeepLTransportResponse, DeepLTransportError> {
        .failure(.cancelled)
    }
}

private struct PackageWorkspace {
    let root: URL
    let bundled: URL
    let user: URL

    var directories: ActionPackageDirectories {
        ActionPackageDirectories(bundled: bundled, user: user)
    }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CapabilityRuntimeCompositionTests-\(UUID().uuidString)")
        bundled = root.appendingPathComponent("Bundled", isDirectory: true)
        user = root.appendingPathComponent("User", isDirectory: true)
        try FileManager.default.createDirectory(
            at: bundled,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: user,
            withIntermediateDirectories: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func writeTranslateManifest() throws {
        let manifest = """
        {
          "schemaVersion": 1,
          "id": "translate",
          "version": "1.0.0",
          "minRuntimeVersion": "1.0.0",
          "display": { "name": "Translate", "allowsFollowUp": false },
          "input": { "selection": "required" },
          "execution": { "strategy": "singleCapability", "capability": "translate.deepl" },
          "permissions": [{ "kind": "network", "host": "api-free.deepl.com", "egress": ["selection", "sourceLanguage", "targetLanguage"] }],
          "budget": { "maxModelCalls": 0, "maxCapabilityCalls": 1 },
          "output": { "kind": "text", "format": "markdown" }
        }
        """
        try Data(manifest.utf8).write(to: bundled.appendingPathComponent("translate.json"))
    }
}
