import Foundation

nonisolated enum DeepLEndpoint: Equatable, Sendable {
    case free
    case pro

    var translationURL: URL {
        switch self {
        case .free:
            URL(string: "https://api-free.deepl.com/v2/translate")!
        case .pro:
            URL(string: "https://api.deepl.com/v2/translate")!
        }
    }

    var usageURL: URL {
        switch self {
        case .free:
            URL(string: "https://api-free.deepl.com/v2/usage")!
        case .pro:
            URL(string: "https://api.deepl.com/v2/usage")!
        }
    }

    var host: String {
        switch self {
        case .free: "api-free.deepl.com"
        case .pro: "api.deepl.com"
        }
    }
}

nonisolated enum DeepLHTTPMethod: String, Equatable, Sendable {
    case get = "GET"
    case post = "POST"
}

nonisolated struct DeepLRequest: Equatable, Sendable {
    let method: DeepLHTTPMethod
    let url: URL
    let headers: [String: String]
    let body: Data?
}

nonisolated struct DeepLTransportResponse: Equatable, Sendable {
    let statusCode: Int
    let data: Data
}

nonisolated enum DeepLTransportError: Error, Equatable, Sendable {
    case transport
    case timeout
    case cancelled
}

nonisolated protocol DeepLTransport: Sendable {
    func send(_ request: DeepLRequest) async -> Result<DeepLTransportResponse, DeepLTransportError>
}

nonisolated struct URLSessionDeepLTransport: DeepLTransport, Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: DeepLRequest) async -> Result<DeepLTransportResponse, DeepLTransportError> {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (header, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: header)
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.transport)
            }
            return .success(
                DeepLTransportResponse(
                    statusCode: httpResponse.statusCode,
                    data: data
                )
            )
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch let error as URLError where error.code == .timedOut {
            return .failure(.timeout)
        } catch {
            if Task.isCancelled {
                return .failure(.cancelled)
            }
            return .failure(.transport)
        }
    }
}
