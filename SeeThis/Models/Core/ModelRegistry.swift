import Foundation

// Curated per-model capability lookup. Keeps model-specific knowledge in one
// place so lens and overlay code branch on capability answers, not on model
// names. Grows fields as the UI needs them.
enum ModelRegistry {

    // Decisive answer to "is this an embedding-only model, unusable for chat?"
    // Only live capability data from /api/show speaks here — Ollama marks
    // chat-capable models with "completion". Returns nil when no live data
    // was supplied; callers treat nil as "assume usable, keep it in the picker
    // until /api/show is called."
    static func isEmbeddingOnly(liveCapabilities: [String]?) -> Bool? {
        guard let liveCapabilities, !liveCapabilities.isEmpty else { return nil }
        return !liveCapabilities.contains("completion")
    }

    // Soft name-family heuristic — no live data required. Used by UI hints
    // that want a "looks embedding-like" signal before /api/show has run.
    // A miss only suppresses the hint; the reader can still pick the model.
    static func looksLikeEmbeddingModel(id: String) -> Bool {
        let baseName = id.split(separator: ":", maxSplits: 1).first.map(String.init) ?? id
        let lower = baseName.lowercased()
        if lower.contains("embed") { return true }
        return embeddingNamePrefixes.contains(where: { lower.hasPrefix($0) })
    }

    private static let embeddingNamePrefixes = ["bge-", "e5-", "gte-", "all-minilm"]
}
