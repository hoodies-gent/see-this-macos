import CoreGraphics
import Carbon
import Foundation
import ApplicationServices
import AppKit
import SwiftUI
import Testing
@testable import SeeThis


struct OllamaTypesTests {

    @Test @MainActor func ollamaTagsResponseListsInstalledModelNames() throws {
        let response = try JSONDecoder().decode(
            OllamaTagsResponse.self,
            from: Data(#"{"models":[{"name":"gemma3:4b"},{"name":"qwen3:4b"}]}"#.utf8)
        )

        #expect(response.installedModels.map(\.id) == ["gemma3:4b", "qwen3:4b"])
    }

    @Test @MainActor func installedModelMatchingTreatsAMissingTagAsLatest() {
        let installed = ["gemma3:4b", "llama3.2:latest"]

        #expect(OllamaProvider.isInstalled("gemma3:4b", among: installed))
        #expect(OllamaProvider.isInstalled("llama3.2", among: installed))
        #expect(OllamaProvider.isInstalled(" Llama3.2:Latest ", among: installed))
        #expect(!OllamaProvider.isInstalled("gemma3", among: installed))
        #expect(!OllamaProvider.isInstalled("qwen3:4b", among: installed))
    }

}
