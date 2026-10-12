import Foundation

nonisolated enum DeepLCredentialValidationError: Error, Equatable, Sendable {
    case invalidCredential
    case rejected
    case timeout
    case transport
    case cancelled
    case invalidResponse
    case providerRejected(statusCode: Int)
}

nonisolated protocol DeepLCredentialValidating: Sendable {
    func validate(
        _ credential: String
    ) async -> Result<Void, DeepLCredentialValidationError>
}

nonisolated struct DeepLCredentialValidator: DeepLCredentialValidating, Sendable {
    private let transport: any DeepLTransport
    private let endpoint: DeepLEndpoint

    init(
        transport: any DeepLTransport,
        endpoint: DeepLEndpoint = .free
    ) {
        self.transport = transport
        self.endpoint = endpoint
    }

    func validate(
        _ credential: String
    ) async -> Result<Void, DeepLCredentialValidationError> {
        let candidate = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            return .failure(.invalidCredential)
        }

        let request = DeepLRequest(
            method: .get,
            url: endpoint.usageURL,
            headers: ["Authorization": "DeepL-Auth-Key \(candidate)"],
            body: nil
        )

        switch await transport.send(request) {
        case let .failure(error):
            return .failure(map(error))
        case let .success(response):
            switch response.statusCode {
            case 200...299:
                guard (try? JSONDecoder().decode(
                    DeepLUsageResponse.self,
                    from: response.data
                )) != nil else {
                    return .failure(.invalidResponse)
                }
                return .success(())
            case 401, 403:
                return .failure(.rejected)
            default:
                return .failure(.providerRejected(statusCode: response.statusCode))
            }
        }
    }

    private func map(
        _ error: DeepLTransportError
    ) -> DeepLCredentialValidationError {
        switch error {
        case .transport: .transport
        case .timeout: .timeout
        case .cancelled: .cancelled
        }
    }
}

nonisolated private struct DeepLUsageResponse: Decodable {
    let characterCount: Int
    let characterLimit: Int

    enum CodingKeys: String, CodingKey {
        case characterCount = "character_count"
        case characterLimit = "character_limit"
    }
}
