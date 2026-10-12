import Foundation
import Testing
@testable import SeeThis

struct DeepLCredentialValidatorTests {
    @Test func validKeyUsesUsageEndpointWithoutReaderContent() async throws {
        let transport = CredentialValidationRecordingTransport(
            result: .success(
                DeepLTransportResponse(
                    statusCode: 200,
                    data: Data(#"{"character_count":12,"character_limit":500000}"#.utf8)
                )
            )
        )
        let validator = DeepLCredentialValidator(transport: transport, endpoint: .free)

        guard case .success = await validator.validate("synthetic-key") else {
            Issue.record("Expected the synthetic usage response to validate.")
            return
        }
        let request = try #require(await transport.requests().first)
        #expect(request.method == .get)
        #expect(request.url == DeepLEndpoint.free.usageURL)
        #expect(request.headers == ["Authorization": "DeepL-Auth-Key synthetic-key"])
        #expect(request.body == nil)
    }

    @Test func emptyKeyIsRejectedWithoutANetworkRequest() async {
        let transport = CredentialValidationRecordingTransport(
            result: .success(DeepLTransportResponse(statusCode: 200, data: Data()))
        )
        let validator = DeepLCredentialValidator(transport: transport, endpoint: .free)

        guard case let .failure(error) = await validator.validate(" \n ") else {
            Issue.record("Expected an empty credential to be rejected.")
            return
        }
        #expect(error == .invalidCredential)
        #expect(await transport.requests().isEmpty)
    }

    @Test(arguments: [401, 403])
    func authenticationFailureRejectsTheCandidate(statusCode: Int) async {
        let transport = CredentialValidationRecordingTransport(
            result: .success(
                DeepLTransportResponse(
                    statusCode: statusCode,
                    data: Data(#"{"message":"sensitive provider detail"}"#.utf8)
                )
            )
        )
        let validator = DeepLCredentialValidator(transport: transport, endpoint: .free)

        let result = await validator.validate("synthetic-key")

        guard case let .failure(error) = result else {
            Issue.record("Expected the provider to reject the credential.")
            return
        }
        #expect(error == .rejected)
        #expect(String(describing: result).contains("sensitive provider detail") == false)
    }

    @Test func transportFailuresStayTypedAndContentFree() async {
        let expected: [(DeepLTransportError, DeepLCredentialValidationError)] = [
            (.timeout, .timeout),
            (.cancelled, .cancelled),
            (.transport, .transport)
        ]

        for (transportError, expectedError) in expected {
            let validator = DeepLCredentialValidator(
                transport: CredentialValidationRecordingTransport(result: .failure(transportError)),
                endpoint: .free
            )
            guard case let .failure(error) = await validator.validate("synthetic-key") else {
                Issue.record("Expected the transport failure to be preserved.")
                continue
            }
            #expect(error == expectedError)
        }
    }

    @Test func malformedSuccessfulResponseIsRejected() async {
        let validator = DeepLCredentialValidator(
            transport: CredentialValidationRecordingTransport(
                result: .success(
                    DeepLTransportResponse(statusCode: 200, data: Data("not-json".utf8))
                )
            ),
            endpoint: .free
        )

        guard case let .failure(error) = await validator.validate("synthetic-key") else {
            Issue.record("Expected malformed usage data to be rejected.")
            return
        }
        #expect(error == .invalidResponse)
    }

    @Test func unexpectedProviderStatusDoesNotExposeResponseContent() async {
        let validator = DeepLCredentialValidator(
            transport: CredentialValidationRecordingTransport(
                result: .success(
                    DeepLTransportResponse(
                        statusCode: 429,
                        data: Data(#"{"message":"sensitive provider detail"}"#.utf8)
                    )
                )
            ),
            endpoint: .free
        )

        let result = await validator.validate("synthetic-key")

        guard case let .failure(error) = result else {
            Issue.record("Expected the provider status to be preserved.")
            return
        }
        #expect(error == .providerRejected(statusCode: 429))
        #expect(String(describing: result).contains("sensitive provider detail") == false)
    }
}

private actor CredentialValidationRecordingTransport: DeepLTransport {
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
