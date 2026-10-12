import CoreGraphics
import Carbon
import Foundation
import ApplicationServices
import AppKit
import SwiftUI
import Testing
@testable import SeeThis


struct PasteboardTests {

    @Test func pasteboardBackupRoundTripsStringDataAndAddsTransientSentinel() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.projectcontext.tests.backup"))
        pasteboard.clearContents()
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("original", forType: .string)

        let backup = PasteboardBackup.snapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("clobbered", forType: .string)

        backup.restore(to: pasteboard)

        #expect(pasteboard.string(forType: .string) == "original")
        #expect(pasteboard.string(forType: NSPasteboardSentinel.transient) != nil)
    }

    @Test func pasteboardChangePollerReturnsTrueWhenChangeCountIncrements() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.projectcontext.tests.poller"))
        pasteboard.clearContents()
        let baseline = pasteboard.changeCount

        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString("changed", forType: .string)

        #expect(
            PasteboardChangePoller.waitForChange(
                from: baseline,
                pasteboard: pasteboard,
                timeout: 0.05
            )
        )
    }

    @Test func pasteboardChangePollerReturnsFalseWhenNothingWritesInTime() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.projectcontext.tests.poller.idle"))
        pasteboard.clearContents()
        let baseline = pasteboard.changeCount

        #expect(
            !PasteboardChangePoller.waitForChange(
                from: baseline,
                pasteboard: pasteboard,
                timeout: 0.02
            )
        )
    }

}
