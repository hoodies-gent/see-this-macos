import Foundation
import Testing
@testable import SeeThis

struct DeepLProviderTests {
    @Test func translatesOnlyTheSelectionAndLanguageParameters() async throws {
        let credential = "synthetic-\(UUID().uuidString)"
        let transport = RecordingDeepLTransport(
            result: .success(
                DeepLTransportResponse(
                    statusCode: 200,
                    data: Data(
                        #"{"translations":[{"detected_source_language":"EN","text":"Translated terminology."}]}"#.utf8
                    )
                )
            )
        )
        let provider = DeepLTranslationCapability(
            credentialStore: FakeCredentialStore(result: .success(credential)),
            transport: transport,
            endpoint: .free
        )

        let result = await provider.invoke(
            .translate(
                TranslateCapabilityInput(
                    selection: "Synthetic academic selection.",
                    sourceLanguage: "en",
                    targetLanguage: "de"
                )
            )
        )

        #expect(result == .success(.text("Translated terminology.")))
        let request = try #require(await transport.requests().first)
        #expect(request.method == .post)
        #expect(request.url == DeepLEndpoint.free.translationURL)
        #expect(request.headers["Authorization"] == "DeepL-Auth-Key \(credential)")
        #expect(request.headers["Content-Type"] == "application/x-www-form-urlencoded")

        let body = try #require(request.body)
        let fields = try #require(formFields(from: body))
        #expect(fields == [
            "text": "Synthetic academic selection.",
            "source_lang": "EN",
            "target_lang": "DE"
        ])
    }

    @Test func missingCredentialProducesNoTransportRequest() async {
        let transport = RecordingDeepLTransport(
            result: .success(DeepLTransportResponse(statusCode: 200, data: Data()))
        )
        let provider = DeepLTranslationCapability(
            credentialStore: FakeCredentialStore(result: .success(nil)),
            transport: transport,
            endpoint: .free
        )

        let result = await provider.invoke(
            .translate(
                TranslateCapabilityInput(
                    selection: "Synthetic selection.",
                    sourceLanguage: nil,
                    targetLanguage: "DE"
                )
            )
        )

        #expect(result == .failure(.missingCredential))
        #expect(await transport.requests().isEmpty)
    }

    @Test func invalidInputProducesNoTransportRequest() async {
        let transport = RecordingDeepLTransport(
            result: .success(DeepLTransportResponse(statusCode: 200, data: Data()))
        )
        let provider = DeepLTranslationCapability(
            credentialStore: FakeCredentialStore(result: .success("synthetic")),
            transport: transport,
            endpoint: .free
        )

        let result = await provider.invoke(
            .translate(
                TranslateCapabilityInput(
                    selection: " \n",
                    sourceLanguage: nil,
                    targetLanguage: "DE"
                )
            )
        )

        #expect(result == .failure(.invalidInput))
        #expect(await transport.requests().isEmpty)
    }

    @Test func mapsProviderStatusWithoutReturningResponseContent() async {
        let transport = RecordingDeepLTransport(
            result: .success(
                DeepLTransportResponse(
                    statusCode: 429,
                    data: Data(#"{"message":"synthetic provider detail"}"#.utf8)
                )
            )
        )
        let provider = DeepLTranslationCapability(
            credentialStore: FakeCredentialStore(result: .success("synthetic")),
            transport: transport,
            endpoint: .free
        )

        let result = await provider.invoke(validInput)

        #expect(result == .failure(.providerRejected(statusCode: 429)))
        #expect(String(describing: result).contains("synthetic provider detail") == false)
    }

    @Test func mapsTransportTimeoutAndCancellation() async {
        let timeoutProvider = DeepLTranslationCapability(
            credentialStore: FakeCredentialStore(result: .success("synthetic")),
            transport: RecordingDeepLTransport(result: .failure(.timeout)),
            endpoint: .free
        )
        let cancellationProvider = DeepLTranslationCapability(
            credentialStore: FakeCredentialStore(result: .success("synthetic")),
            transport: RecordingDeepLTransport(result: .failure(.cancelled)),
            endpoint: .free
        )

        #expect(await timeoutProvider.invoke(validInput) == .failure(.timeout))
        #expect(await cancellationProvider.invoke(validInput) == .failure(.cancelled))
    }

    @Test func malformedSuccessfulResponseIsRejected() async {
        let provider = DeepLTranslationCapability(
            credentialStore: FakeCredentialStore(result: .success("synthetic")),
            transport: RecordingDeepLTransport(
                result: .success(
                    DeepLTransportResponse(statusCode: 200, data: Data("not-json".utf8))
                )
            ),
            endpoint: .free
        )

        #expect(await provider.invoke(validInput) == .failure(.invalidResponse))
    }

    private var validInput: CapabilityInput {
        .translate(
            TranslateCapabilityInput(
                selection: "Synthetic selection.",
                sourceLanguage: nil,
                targetLanguage: "DE"
            )
        )
    }

    private func formFields(from body: Data) -> [String: String]? {
        guard let encoded = String(data: body, encoding: .utf8) else {
            return nil
        }
        var components = URLComponents()
        components.percentEncodedQuery = encoded
        return Dictionary(
            uniqueKeysWithValues: components.queryItems?.compactMap { item in
                guard let value = item.value else { return nil }
                return (item.name, value)
            } ?? []
        )
    }
}

private final class FakeCredentialStore: CredentialStore, @unchecked Sendable {
    private let result: Result<String?, CredentialStoreError>

    init(result: Result<String?, CredentialStoreError>) {
        self.result = result
    }

    func read(_ key: CredentialKey) -> Result<String?, CredentialStoreError> {
        result
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
