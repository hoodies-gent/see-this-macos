import Foundation

nonisolated struct DeepLTranslationCapability: Capability, Sendable {
    static let capabilityID = "translate.deepl"
    static let credentialKey = CredentialKey(
        service: AppIdentity.keychainService,
        account: "deepl.api-key"
    )

    let endpoint: DeepLEndpoint
    private let credentialStore: any CredentialStore
    private let transport: any DeepLTransport

    init(
        credentialStore: any CredentialStore,
        transport: any DeepLTransport,
        endpoint: DeepLEndpoint = .free
    ) {
        self.credentialStore = credentialStore
        self.transport = transport
        self.endpoint = endpoint
    }

    static func requiredPermission(for endpoint: DeepLEndpoint) -> ActionPermission {
        .network(
            host: endpoint.host,
            egress: ["selection", "sourceLanguage", "targetLanguage"]
        )
    }

    var descriptor: CapabilityDescriptor {
        CapabilityDescriptor(
            id: Self.capabilityID,
            requiredPermissions: [Self.requiredPermission(for: endpoint)]
        )
    }

    func invoke(
        _ input: CapabilityInput
    ) async -> Result<CapabilityOutput, CapabilityError> {
        guard case let .translate(translation) = input,
              !translation.selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !translation.targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.invalidInput)
        }

        guard case let .success(credential?) = credentialStore.read(Self.credentialKey),
              !credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.missingCredential)
        }

        guard let body = formBody(translation) else {
            return .failure(.invalidInput)
        }

        let request = DeepLRequest(
            method: .post,
            url: endpoint.translationURL,
            headers: [
                "Authorization": "DeepL-Auth-Key \(credential)",
                "Content-Type": "application/x-www-form-urlencoded"
            ],
            body: body
        )

        switch await transport.send(request) {
        case let .failure(error):
            return .failure(map(error))
        case let .success(response):
            guard (200...299).contains(response.statusCode) else {
                return .failure(.providerRejected(statusCode: response.statusCode))
            }
            guard let translation = try? JSONDecoder().decode(
                DeepLTranslationResponse.self,
                from: response.data
            ),
            let text = translation.translations.first?.text,
            !text.isEmpty else {
                return .failure(.invalidResponse)
            }
            return .success(.text(text))
        }
    }

    private func formBody(_ input: TranslateCapabilityInput) -> Data? {
        var fields = [
            URLQueryItem(name: "text", value: input.selection),
            URLQueryItem(name: "target_lang", value: input.targetLanguage.uppercased())
        ]
        if let sourceLanguage = input.sourceLanguage,
           !sourceLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.insert(
                URLQueryItem(name: "source_lang", value: sourceLanguage.uppercased()),
                at: 1
            )
        }
        var components = URLComponents()
        components.queryItems = fields
        return components.percentEncodedQuery?.data(using: .utf8)
    }

    private func map(_ error: DeepLTransportError) -> CapabilityError {
        switch error {
        case .transport: .transport
        case .timeout: .timeout
        case .cancelled: .cancelled
        }
    }
}

nonisolated private struct DeepLTranslationResponse: Decodable {
    nonisolated struct Translation: Decodable {
        let text: String
    }

    let translations: [Translation]
}
