#if DEBUG
import CoreGraphics
import Carbon
import Foundation
import ApplicationServices
import AppKit
import SwiftUI
import Testing
@testable import SeeThis


struct CapabilityProbeHotKeyTests {

    @Test func probeHotKeyDoesNotConflictWithCaptureOrEscape() {
        let probe = CapabilityProbeHotKeyMonitor.hotKeyIdentifier

        #expect(!probe.matches(GlobalHotKeyMonitor.hotKeyIdentifier.carbonValue))
        #expect(!probe.matches(TemporaryEscapeHotKeyMonitor.hotKeyIdentifier.carbonValue))
    }

}
#endif
