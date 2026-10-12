import CoreGraphics
import Carbon
import Foundation
import ApplicationServices
import AppKit
import SwiftUI
import Testing
@testable import SeeThis


struct OverlayControllerTests {

    @Test func presentationStateOnlyTransitionsOncePerVisibilityChange() {
        var state = OverlayPresentationState()

        let began = state.beginPresentation()
        #expect(began)
        #expect(state.isVisible)
        let beganAgain = state.beginPresentation()
        #expect(!beganAgain)
        let ended = state.endPresentation()
        #expect(ended)
        #expect(!state.isVisible)
        let endedAgain = state.endPresentation()
        #expect(!endedAgain)
    }

    @Test @MainActor func completedAnswerCanGrowTheVisibleStreamingPanel() throws {
        let panel = ReadingOverlayPanel()
        let controller = OverlayController(panel: panel)
        let streaming = OverlayContentState.streaming(
            "First line.\nSecond line.\nThird line.",
            usesPaperContext: false
        )
        let answer = OverlayContentState.answer(
            "First line.\nSecond line.\nThird line.",
            usesPaperContext: false
        )
        let screen = try #require(NSScreen.main)
        let initialSize = streaming.preferredPanelSize()
        panel.setFrame(
            CGRect(
                x: screen.visibleFrame.midX - initialSize.width / 2,
                y: screen.visibleFrame.midY - initialSize.height / 2,
                width: initialSize.width,
                height: initialSize.height
            ),
            display: false
        )

        controller.resizeVisiblePanel(for: answer)

        #expect(panel.frame.height > initialSize.height)
    }

}
