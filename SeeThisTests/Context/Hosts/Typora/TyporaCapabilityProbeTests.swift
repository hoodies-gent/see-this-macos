#if DEBUG
import CoreGraphics
import Carbon
import Foundation
import ApplicationServices
import AppKit
import SwiftUI
import Testing
@testable import SeeThis


struct TyporaCapabilityProbeTests {

    @Test func typoraProbeCountsSuccessesWithoutSelectionContent() {
        var summary = TyporaCapabilityProbeSummary()
        summary.record(.success)
        summary.record(.selectionBoundsUnavailable)

        #expect(summary.sampleCount == 2)
        #expect(summary.successCount == 1)
        #expect(
            summary.summary
                == "Typora feasibility: 1/2 captures supplied selected text and an anchor frame."
        )
        #expect(!summary.summary.contains("Sensitive probe value"))
    }

    @Test func typoraProbeFailureStatusContainsOnlyFailureCategory() {
        let status = TyporaCapabilityProbeStatus.failed(.selectedTextUnavailable)

        #expect(status.summary == "Typora feasibility: selected text unavailable.")
        #expect(!status.summary.contains("Sensitive probe value"))
    }

    @Test @MainActor func typoraProbeAttemptsCharacterRangeBeforeTextMarkerRange() {
        #expect(
            TyporaSelectionCapturePlan().attempts
                == [.characterRange, .textMarkerRange]
        )
    }

    @Test @MainActor func typoraProviderBuildsASelectionOnlySnapshot() {
        let snapshot = TyporaHostContextProvider.selectionSnapshot(
            selectedText: "Synthetic selection.",
            selectedRange: NSRange(location: 4, length: 8)
        )

        #expect(snapshot.hostBundleIdentifier == "abnerworks.Typora")
        #expect(snapshot.selectedRange == NSRange(location: 4, length: 8))
        #expect(snapshot.documentTitle == nil)
        #expect(snapshot.textConsistency == .unavailable)
        #expect(snapshot.isUsable)
    }

    @Test @MainActor func typoraDocumentReferenceProbeKeepsTheGenericFallbackSelectionOnly() {
        #expect(TyporaDocumentReferenceCapability.unavailable == .unavailable)
    }

    @Test @MainActor func typoraProviderDeclaresDocumentReferenceUnavailableUntilProbed() {
        #expect(TyporaHostContextProvider().documentReferenceCapability == .unavailable)
        #expect(TyporaHostContextProvider().documentReferenceCapture == .unavailable)
    }

    @Test func typoraDocumentReferenceProbeSummaryRecordsOnlyAvailabilityCategories() {
        var summary = TyporaDocumentReferenceProbeSummary()
        summary.record(.available)
        summary.record(.unavailable)

        #expect(summary.sampleCount == 2)
        #expect(summary.availableCount == 1)
    }

    @Test func typoraDocumentReferenceProbeSummaryShowsOnlyCandidateCounts() {
        var summary = TyporaDocumentReferenceProbeSummary()
        summary.record(.available)
        summary.record(.unavailable)

        #expect(summary.summary == "Typora document-reference candidate: 1/2 URL-classified")
        #expect(!summary.summary.contains("file://"))
        #expect(!summary.summary.contains("Sensitive probe value"))
    }

    @Test @MainActor func probeCapabilitiesForUnsupportedHostReportsNoSupportedHost() {
        let diagnostics = HostContextDiagnostics()
        diagnostics.probeCapabilities(for: .unsupported)

        #expect(diagnostics.lastResult == "Capability probe: no supported host is frontmost.")
    }

}
#endif
