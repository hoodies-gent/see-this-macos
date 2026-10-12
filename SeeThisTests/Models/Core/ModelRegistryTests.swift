import Foundation
import Testing
@testable import SeeThis

struct ModelRegistryTests {

    @Test func isEmbeddingOnlyReturnsNilWithoutLiveData() {
        #expect(ModelRegistry.isEmbeddingOnly(liveCapabilities: nil) == nil)
        #expect(ModelRegistry.isEmbeddingOnly(liveCapabilities: []) == nil)
    }

    @Test func isEmbeddingOnlyFalseWhenCompletionListed() {
        #expect(ModelRegistry.isEmbeddingOnly(liveCapabilities: ["completion"]) == false)
        #expect(ModelRegistry.isEmbeddingOnly(liveCapabilities: ["completion", "tools"]) == false)
    }

    @Test func isEmbeddingOnlyTrueWhenCompletionMissing() {
        #expect(ModelRegistry.isEmbeddingOnly(liveCapabilities: ["embedding"]) == true)
    }

    @Test func looksLikeEmbeddingCatchesEmbedSubstring() {
        #expect(ModelRegistry.looksLikeEmbeddingModel(id: "nomic-embed-text:latest"))
        #expect(ModelRegistry.looksLikeEmbeddingModel(id: "mxbai-embed-large"))
    }

    @Test func looksLikeEmbeddingCatchesKnownPrefixes() {
        #expect(ModelRegistry.looksLikeEmbeddingModel(id: "bge-large"))
        #expect(ModelRegistry.looksLikeEmbeddingModel(id: "e5-mistral"))
        #expect(ModelRegistry.looksLikeEmbeddingModel(id: "gte-small"))
        #expect(ModelRegistry.looksLikeEmbeddingModel(id: "all-minilm"))
    }

    @Test func looksLikeEmbeddingRejectsChatFamilies() {
        #expect(!ModelRegistry.looksLikeEmbeddingModel(id: "gemma3:4b"))
        #expect(!ModelRegistry.looksLikeEmbeddingModel(id: "llama3.2:3b"))
        #expect(!ModelRegistry.looksLikeEmbeddingModel(id: "qwen2.5:3b"))
    }

    @Test func looksLikeEmbeddingCaseInsensitive() {
        #expect(ModelRegistry.looksLikeEmbeddingModel(id: "BGE-Large"))
        #expect(ModelRegistry.looksLikeEmbeddingModel(id: "Nomic-Embed-Text"))
    }
}
