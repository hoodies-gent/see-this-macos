import AppKit
import Foundation

// Wire decode of GET /api/tags. Emits provider-agnostic ModelDescriptors so
// nothing beyond OllamaProvider needs to know the tags payload's shape.
struct OllamaTagsResponse: Decodable {
    private struct Model: Decodable {
        let name: String
        let size: Int64?
    }

    private let models: [Model]

    var installedModels: [ModelDescriptor] {
        models.map { ModelDescriptor(id: $0.name, sizeBytes: $0.size) }
    }
}

// UI-layer view of one model's capability data. Constructed from a
// ModelDescriptor at the boundary between provider and UI.
nonisolated struct OllamaModelMetadata: Equatable, Hashable, Sendable {
    let contextLength: Int?
    let capabilities: [String]

    init(from descriptor: ModelDescriptor) {
        self.contextLength = descriptor.contextLength
        self.capabilities = descriptor.capabilities
    }
}

// UI-layer view of one installed model. Carries the id + size returned by
// listModels, plus the (optional) metadata that showModel fills in.
struct OllamaInstalledModel: Equatable, Identifiable, Hashable {
    let id: String
    let sizeBytes: Int64?
    var metadata: OllamaModelMetadata?

    init(id: String, sizeBytes: Int64?, metadata: OllamaModelMetadata? = nil) {
        self.id = id
        self.sizeBytes = sizeBytes
        self.metadata = metadata
    }

    init(from descriptor: ModelDescriptor) {
        self.init(id: descriptor.id, sizeBytes: descriptor.sizeBytes, metadata: nil)
    }

    var displaySize: String? {
        guard let sizeBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var contextLengthDisplay: String? {
        guard let value = metadata?.contextLength, value > 0 else { return nil }
        return Self.formatContextLength(value)
    }

    private static func formatContextLength(_ value: Int) -> String {
        if value >= 1024, value % 1024 == 0 {
            return "\(value / 1024)K"
        }
        if value >= 1000 {
            return "\(value / 1000)K"
        }
        return "\(value)"
    }

    var isEmbeddingOnly: Bool? {
        ModelRegistry.isEmbeddingOnly(liveCapabilities: metadata?.capabilities)
    }

    var isEmbeddingLike: Bool {
        ModelRegistry.looksLikeEmbeddingModel(id: id)
    }
}

struct RecommendedOllamaModel: Identifiable, Equatable {
    let id: String
    let downloadSize: String

    static let curated: [RecommendedOllamaModel] = [
        RecommendedOllamaModel(id: "gemma3:4b", downloadSize: "~3.3 GB"),
        RecommendedOllamaModel(id: "llama3.2:3b", downloadSize: "~2.0 GB"),
        RecommendedOllamaModel(id: "qwen2.5:3b", downloadSize: "~1.9 GB")
    ]
}

// UI-layer pull progress. Adds a fraction + a user-facing status string that
// smooths over the vocabulary of Ollama's raw pull events.
struct OllamaPullProgress: Equatable {
    let status: String
    let completedBytes: Int64?
    let totalBytes: Int64?

    init(status: String, completedBytes: Int64?, totalBytes: Int64?) {
        self.status = status
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
    }

    init(from progress: ModelPullProgress) {
        self.init(
            status: progress.status,
            completedBytes: progress.completedBytes,
            totalBytes: progress.totalBytes
        )
    }

    var fraction: Double? {
        guard let completedBytes, let totalBytes, totalBytes > 0 else { return nil }
        return min(1.0, max(0.0, Double(completedBytes) / Double(totalBytes)))
    }

    // Replaces Ollama's raw status ("pulling manifest", "pulling <digest>", …) with a
    // user-facing word. Most time is "Installing"; only the brief inter-layer verify
    // and end-of-pull finalize phases are named so the progress-bar reset between
    // layers is explained without adding vocabulary the user has to learn.
    var userFacingStatus: String {
        let lower = status.lowercased()
        if lower.contains("verifying") { return "Verifying…" }
        if lower.contains("writing") || lower.contains("removing") { return "Finalizing…" }
        // Bytes at 100% means the download is done — remaining work is verify/write
        // manifest even when Ollama hasn't emitted a status update to say so yet.
        if fraction == 1.0 { return "Finalizing…" }
        return "Installing…"
    }
}

enum OllamaInstallation: Equatable {
    case app(URL)
    case cli(URL)

    static let downloadPageURL = URL(string: "https://ollama.com/download")!
    static let libraryPageURL = URL(string: "https://ollama.com/library")!

    static let appPaths: [String] = [
        "/Applications/Ollama.app",
        NSString(string: "~/Applications/Ollama.app").expandingTildeInPath
    ]

    private static let cliPaths: [String] = [
        "/opt/homebrew/bin/ollama",
        "/usr/local/bin/ollama",
        "/usr/bin/ollama"
    ]

    static var detected: OllamaInstallation? {
        for path in appPaths where FileManager.default.fileExists(atPath: path) {
            return .app(URL(fileURLWithPath: path))
        }
        for path in cliPaths where FileManager.default.isExecutableFile(atPath: path) {
            return .cli(URL(fileURLWithPath: path))
        }
        return nil
    }

    static var isInstalled: Bool { detected != nil }
}
