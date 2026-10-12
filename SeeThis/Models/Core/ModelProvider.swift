import Foundation

// Provider-agnostic chat message. Roles map 1:1 to the chat-completion vocabulary
// every backend the app targets already speaks (system / user / assistant).
nonisolated struct ChatMessage: Equatable, Sendable {
    nonisolated enum Role: String, Sendable {
        case system
        case user
        case assistant
    }

    let role: Role
    let content: String
}

// One decoded event from a streaming chat call. `.finished` fires exactly once
// per successful stream, after all fragments; `.fragment("")` is never emitted.
nonisolated enum ChatStreamEvent: Equatable, Sendable {
    case fragment(String)
    case finished
}

// Failure surface shared by every provider. Individual providers translate
// their own error shapes into these cases; UI only ever branches on this enum.
nonisolated enum ChatFailure: Error, Equatable, Sendable {
    case unavailable
    case cancelled
    case timeout
    case modelUnavailable(model: String)
    case invalidResponse
    case pullFailed(reason: String)

    var message: String {
        switch self {
        case .unavailable:
            return "Ollama is not running. Start Ollama, then try again."
        case .cancelled:
            return ""
        case .timeout:
            return "Ollama took too long to load this model. Check Ollama, then try again."
        case .modelUnavailable(let model):
            return "Ollama model \(model) is not available. Run ollama pull \(model)."
        case .invalidResponse:
            return "Error: Ollama could not produce a usable explanation."
        case .pullFailed(let reason):
            return Self.friendlyPullMessage(rawReason: reason)
        }
    }

    private static func friendlyPullMessage(rawReason: String) -> String {
        let lower = rawReason.lowercased()
        if lower.contains("no such host") || lower.contains("connection refused") || lower.contains("timeout") {
            return "Error: Couldn't reach ollama.com. Check your internet, then retry."
        }
        if lower.contains("manifest") || lower.contains("does not exist") || lower.contains("not found") || lower.contains("invalid") {
            return "Error: Ollama doesn't recognize this model name. Check the spelling, or browse ollama.com/library."
        }
        return "Error: \(rawReason)"
    }
}

// Everything the app needs to know about one installed model. Capability data
// (context length, structured-output, etc.) is optional — some providers /
// endpoints don't report it, and callers must degrade gracefully.
struct ModelDescriptor: Equatable, Hashable, Sendable {
    let id: String
    let sizeBytes: Int64?
    let contextLength: Int?
    let capabilities: [String]

    init(
        id: String,
        sizeBytes: Int64? = nil,
        contextLength: Int? = nil,
        capabilities: [String] = []
    ) {
        self.id = id
        self.sizeBytes = sizeBytes
        self.contextLength = contextLength
        self.capabilities = capabilities
    }
}

// Raw progress from a model pull. Provider-facing UI wording (Installing / Verifying / …)
// is layered on top by the provider adapter, not the protocol.
struct ModelPullProgress: Equatable, Sendable {
    let status: String
    let completedBytes: Int64?
    let totalBytes: Int64?
}

nonisolated protocol ActionModelClient: Sendable {
    func streamChat(
        model: String,
        messages: [ChatMessage],
        onEvent: @escaping @Sendable (ChatStreamEvent) async -> Void
    ) async -> Result<Void, ChatFailure>
}

// The single seam the rest of the app uses to talk to a chat backend.
// Method set is deliberately wide enough to cover the Ollama-specific model
// management UI so callers never need to reach past the protocol; providers
// that don't manage a local service can return `false` / `.unavailable`.
protocol ModelProvider: ActionModelClient {
    func listModels() async -> Result<[ModelDescriptor], ChatFailure>

    func showModel(name: String) async -> ModelDescriptor?

    func pullModel(
        name: String,
        onProgress: @escaping @Sendable (ModelPullProgress) async -> Void
    ) async -> Result<Void, ChatFailure>

    func deleteModel(name: String) async -> Result<Void, ChatFailure>

    func waitForServiceReady(
        timeoutSeconds: Double,
        pollIntervalSeconds: Double
    ) async -> Bool

    @MainActor func startService() async -> Bool

    @MainActor func stopService() async -> Bool
}
