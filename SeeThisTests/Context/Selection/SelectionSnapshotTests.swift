import CoreGraphics
import Carbon
import Foundation
import ApplicationServices
import AppKit
import SwiftUI
import Testing
@testable import SeeThis


struct SelectionSnapshotTests {

    @Test func snapshotWithTextMarkerSelectionIsUsable() {
        let snapshot = SelectionSnapshot(
            hostBundleIdentifier: "org.zotero.zotero",
            selectedText: "twelve chars",
            selectedRange: nil
        )

        #expect(snapshot.isUsable)
    }

    @Test func snapshotWithPositiveTextLengthIsUsable() {
        let snapshot = SelectionSnapshot(
            hostBundleIdentifier: "org.zotero.zotero",
            selectedText: "twelve chars",
            selectedRange: NSRange(location: 4, length: 12)
        )

        #expect(snapshot.isUsable)
    }

    @Test func snapshotWithoutSelectionIsNotUsable() {
        let emptySelection = SelectionSnapshot(
            hostBundleIdentifier: "org.zotero.zotero",
            selectedText: "",
            selectedRange: NSRange(location: 0, length: 0)
        )

        #expect(!emptySelection.isUsable)
    }

    @Test func failureDescriptionsDoNotContainSelectedText() {
        #expect(HostContextFailure.emptySelection.message == "No text is selected in Zotero.")
        #expect(HostContextFailure.selectionBoundsUnavailable.message == "Zotero did not expose a usable selection frame.")
    }

    @Test @MainActor func onlyThePasswordFieldSubroleIsTreatedAsSecure() {
        #expect(UniversalSelectionCapture.isSecureTextFieldSubrole("AXSecureTextField"))
        #expect(!UniversalSelectionCapture.isSecureTextFieldSubrole("AXSearchField"))
        #expect(!UniversalSelectionCapture.isSecureTextFieldSubrole(nil))
    }

    @Test @MainActor func secureFieldsStopBeforeAnySelectionReadOrCopyFallback() {
        var accessibilityWasRead = false
        var secureEventInputWasChecked = false
        let readAccessibility = {
            accessibilityWasRead = true
            return "must not be used"
        }
        let checkSecureEventInput = {
            secureEventInputWasChecked = true
            return false
        }

        let decision = UniversalSelectionCapture.preCopyDecision(
            focusedElementIsSecure: true,
            accessibilityText: readAccessibility(),
            secureEventInputEnabled: checkSecureEventInput()
        )

        #expect(decision == .secureField)
        #expect(!accessibilityWasRead)
        #expect(!secureEventInputWasChecked)
    }

    @Test @MainActor func secureEventInputStopsCopyFallbacksAfterAccessibility() {
        #expect(UniversalSelectionCapture.preCopyDecision(
            focusedElementIsSecure: false,
            accessibilityText: nil,
            secureEventInputEnabled: true
        ) == .secureField)

        #expect(UniversalSelectionCapture.preCopyDecision(
            focusedElementIsSecure: false,
            accessibilityText: "safe accessibility selection",
            secureEventInputEnabled: true
        ) == .accessibility("safe accessibility selection"))
    }

    @Test @MainActor func ordinaryEmptyAccessibilitySelectionAllowsCopyFallbacks() {
        #expect(UniversalSelectionCapture.preCopyDecision(
            focusedElementIsSecure: false,
            accessibilityText: "",
            secureEventInputEnabled: false
        ) == .copyFallbacks)
    }

}
