import CoreGraphics
import Carbon
import Foundation
import ApplicationServices
import AppKit
import SwiftUI
import Testing
@testable import SeeThis


struct OllamaFailurePresentationTests {

    @Test func ollamaFailureMessagesDoNotContainRequestContent() {
        #expect(
            ChatFailure.unavailable.message
                == "Ollama is not running. Start Ollama, then try again."
        )
        #expect(
            ChatFailure.modelUnavailable(model: OllamaProvider.defaultModelName).message
                == "Ollama model gemma3:4b is not available. Run ollama pull gemma3:4b."
        )
    }

    @Test func ollamaMissingModelGuidanceNamesOnlyTheSelectedModel() {
        #expect(
            ChatFailure.modelUnavailable(model: "qwen3:4b").message
                == "Ollama model qwen3:4b is not available. Run ollama pull qwen3:4b."
        )
    }

}
