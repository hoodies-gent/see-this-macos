import Foundation
import Testing
@testable import SeeThis

struct TranslateActionCoordinatorTests {

    @Test func mapsCoordinatorFailuresWithoutExposingCredentialsOrSelection() {
        #expect(
            TranslateActionUserMessage.coordinatorFailure(.permission(.permissionNotGranted(
                .network(host: "api-free.deepl.com", egress: ["selection"])
            ))) == "Authorize the DeepL destination in Settings before translating."
        )
        #expect(
            TranslateActionUserMessage.runtimeFailure(.capability(.timeout))
                == "DeepL translation timed out."
        )
        #expect(TranslateActionUserMessage.runtimeFailure(.cancelled) == nil)
    }
    @Test func authorizedTranslateExecutesTheResolvedPackageAction() async throws {
        let transport = RecordingDeepLTransport(
            result: .success(
                DeepLTransportResponse(
                    statusCode: 200,
                    data: Data(#"{"translations":[{"text":"Translated selection."}]}"#.utf8)
                )
            )
        )
        let workspace = try PackageWorkspace()
        defer { workspace.remove() }
        try workspace.writeTranslateManifest()
        let composition = try makeComposition(
            workspace: workspace,
            credentialStore: FixedCredentialStore(value: "synthetic-\(UUID().uuidString)"),
            transport: transport
        )
        let coordinator = TranslateActionCoordinator(
            composition: composition,
            modelClient: RecordingModelClient()
        )

        let permission = translatePermission
        let result = await coordinator.execute(
            selection: "Synthetic academic selection.",
            sourceLanguage: "EN",
            targetLanguage: "DE",
            model: "unused-model",
            grants: ActionPermissionGrants(["translate": [permission]])
        )

        guard case let .success(outcome) = result else {
            Issue.record("Expected authorized Translate execution to succeed.")
            return
        }
        #expect(outcome.result == .success("Translated selection."))
        #expect(outcome.trace.actionID == "translate")
        #expect(outcome.trace.modelCallCount == 0)
        #expect(outcome.trace.capabilityCallCount == 1)
        #expect(outcome.trace.contextSources == [.selection])
        #expect(outcome.trace.destination == .network(host: "api-free.deepl.com"))

        let request = try #require(await transport.requests().first)
        #expect(request.method == .post)
        #expect(request.url == DeepLEndpoint.free.translationURL)
        #expect(await transport.requests().count == 1)
        let requestBody = try #require(request.body)
        #expect(String(data: requestBody, encoding: .utf8)?.contains("academic") == true)
    }

    @Test func missingGrantStopsBeforeTheProviderTransport() async throws {
        let transport = RecordingDeepLTransport(
            result: .success(DeepLTransportResponse(statusCode: 200, data: Data()))
        )
        let workspace = try PackageWorkspace()
        defer { workspace.remove() }
        try workspace.writeTranslateManifest()
        let composition = try makeComposition(
            workspace: workspace,
            credentialStore: FixedCredentialStore(value: "synthetic-\(UUID().uuidString)"),
            transport: transport
        )
        let coordinator = TranslateActionCoordinator(
            composition: composition,
            modelClient: RecordingModelClient()
        )

        let result = await coordinator.execute(
            selection: "Synthetic selection.",
            sourceLanguage: nil,
            targetLanguage: "DE",
            model: "unused-model",
            grants: ActionPermissionGrants([:])
        )

        #expect(
            result
                == .failure(
                    .permission(
                        .permissionNotGranted(translatePermission)
                    )
                )
        )
        #expect(await transport.requests().isEmpty)
    }

    private var translatePermission: ActionPermission {
        .network(
            host: "api-free.deepl.com",
            egress: ["selection", "sourceLanguage", "targetLanguage"]
        )
    }

    private func makeComposition(
        workspace: PackageWorkspace,
        credentialStore: any CredentialStore,
        transport: any DeepLTransport
    ) throws -> CapabilityRuntimeComposition {
        try CapabilityRuntimeComposition(
            credentialStore: credentialStore,
            transport: transport,
            directories: workspace.directories,
            runtimeVersion: SemanticVersion(1, 0, 0),
            allowedNetworkHosts: ["api-free.deepl.com"]
        )
    }
}

private actor RecordingModelClient: ActionModelClient {
    func streamChat(
        model: String,
        messages: [ChatMessage],
        onEvent: @escaping @Sendable (ChatStreamEvent) async -> Void
    ) async -> Result<Void, ChatFailure> {
        .failure(.unavailable)
    }
}

private struct FixedCredentialStore: CredentialStore {
    let value: String?

    func read(_ key: CredentialKey) -> Result<String?, CredentialStoreError> {
        .success(value)
    }

    func write(_ credential: String, for key: CredentialKey) -> Result<Void, CredentialStoreError> {
        .success(())
    }

    func delete(_ key: CredentialKey) -> Result<Void, CredentialStoreError> {
        .success(())
    }
}

private actor RecordingDeepLTransport: DeepLTransport {
    private let result: Result<DeepLTransportResponse, DeepLTransportError>
    private var recordedRequests: [DeepLRequest] = []

    init(result: Result<DeepLTransportResponse, DeepLTransportError>) {
        self.result = result
    }

    func send(_ request: DeepLRequest) async -> Result<DeepLTransportResponse, DeepLTransportError> {
        recordedRequests.append(request)
        return result
    }

    func requests() -> [DeepLRequest] {
        recordedRequests
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
            .appendingPathComponent("TranslateActionCoordinatorTests-\(UUID().uuidString)")
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
