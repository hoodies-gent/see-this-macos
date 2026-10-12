import CoreGraphics
import Carbon
import Foundation
import ApplicationServices
import AppKit
import SwiftUI
import Testing
@testable import SeeThis


struct OverlayPlacementTests {

    @Test func placementPrefersBelowRightOfCursor() {
        let mouse = CGPoint(x: 400, y: 600)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_000, height: 800)

        let frame = OverlayPlacement.frame(atMouseLocation: mouse, in: visibleFrame)

        #expect(frame == CGRect(x: 412, y: 388, width: 560, height: 200))
    }

    @Test func placementFlipsHorizontallyWhenRightWouldSpill() {
        let mouse = CGPoint(x: 900, y: 600)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_000, height: 800)

        let frame = OverlayPlacement.frame(atMouseLocation: mouse, in: visibleFrame)

        #expect(frame == CGRect(x: 328, y: 388, width: 560, height: 200))
    }

    @Test func placementFlipsVerticallyWhenBelowWouldSpill() {
        let mouse = CGPoint(x: 400, y: 100)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_000, height: 800)

        let frame = OverlayPlacement.frame(atMouseLocation: mouse, in: visibleFrame)

        #expect(frame == CGRect(x: 412, y: 112, width: 560, height: 200))
    }

    @Test func placementClampsIntoVisibleFrameWhenNoQuadrantFits() {
        let mouse = CGPoint(x: 50, y: 50)
        let visibleFrame = CGRect(x: 0, y: 0, width: 600, height: 300)

        let frame = OverlayPlacement.frame(atMouseLocation: mouse, in: visibleFrame)

        #expect(frame.origin.x >= visibleFrame.minX)
        #expect(frame.origin.y >= visibleFrame.minY)
        #expect(frame.maxX <= visibleFrame.maxX)
        #expect(frame.maxY <= visibleFrame.maxY)
    }

}
