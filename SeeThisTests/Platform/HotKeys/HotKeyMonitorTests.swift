import CoreGraphics
import Carbon
import Foundation
import ApplicationServices
import AppKit
import SwiftUI
import Testing
@testable import SeeThis


struct HotKeyMonitorTests {

    @Test func hotKeyMonitorsIgnoreEachOthersEvents() {
        let commandD = GlobalHotKeyMonitor.hotKeyIdentifier
        let escape = TemporaryEscapeHotKeyMonitor.hotKeyIdentifier

        #expect(commandD.matches(commandD.carbonValue))
        #expect(!commandD.matches(escape.carbonValue))
        #expect(escape.matches(escape.carbonValue))
        #expect(!escape.matches(commandD.carbonValue))
    }

    @Test func unmatchedHotKeyEventContinuesToTheNextHandler() {
        let commandD = GlobalHotKeyMonitor.hotKeyIdentifier
        let escape = TemporaryEscapeHotKeyMonitor.hotKeyIdentifier

        #expect(commandD.eventHandlingStatus(for: commandD.carbonValue) == noErr)
        #expect(commandD.eventHandlingStatus(for: escape.carbonValue) == OSStatus(eventNotHandledErr))
    }

    @Test @MainActor func dogfoodShortcutIsCommandD() {
        let shortcut = KeyboardShortcut.commandD
        #expect(shortcut.display == "⌘D")
        #expect(shortcut.keyCode == UInt32(kVK_ANSI_D))
        #expect(shortcut.carbonModifiers == UInt32(cmdKey))
    }

}
