#if DEBUG
import CoreGraphics
import Carbon
import Foundation
import ApplicationServices
import AppKit
import SwiftUI
import Testing
@testable import SeeThis


struct ZoteroCapabilityProbeTests {

    @Test @MainActor func capabilityProbeCategorizesAccessibilityErrorsWithoutValues() {
        #expect(ZoteroCapabilityProbeOutcome(accessibilityError: .noValue) == .noValue)
        #expect(
            ZoteroCapabilityProbeOutcome(accessibilityError: .attributeUnsupported)
                == .attributeUnsupported
        )
        #expect(ZoteroCapabilityProbeOutcome(accessibilityError: .cannotComplete) == .cannotComplete)
    }

    @Test @MainActor func capabilityProbeSummarizesRepeatedMetadataWithoutContent() {
        var summary = ZoteroCapabilityProbeSummary()
        summary.record([
            ZoteroCapabilityProbeObservation(
                candidate: .documentAttribute,
                outcome: .readable,
                valueCategory: .url
            ),
            ZoteroCapabilityProbeObservation(
                candidate: .documentAttribute,
                outcome: .noValue,
                valueCategory: nil
            ),
            ZoteroCapabilityProbeObservation(
                candidate: .selectedTextMarkerRange,
                outcome: .readable,
                valueCategory: .textMarkerRange
            )
        ])

        #expect(summary.sampleCount == 1)
        #expect(summary.readableCount(for: .documentAttribute) == 1)
        #expect(summary.readableCount(for: .selectedTextMarkerRange) == 1)
        #expect(summary.summary.contains("document attribute: 1/2 readable"))
        #expect(!summary.summary.contains("Sensitive probe value"))
    }

    @Test func zoteroDocumentReferenceProbeRecordsOnlyAvailabilityCategories() {
        var summary = ZoteroDocumentReferenceProbeSummary()
        summary.record(.available)
        summary.record(.unavailable)

        #expect(summary.sampleCount == 2)
        #expect(summary.availableCount == 1)
    }

    @Test func documentReferenceProbeSummaryShowsOnlyCandidateCounts() {
        var summary = ZoteroDocumentReferenceProbeSummary()
        summary.record(.available)
        summary.record(.unavailable)

        #expect(summary.summary == "Document-reference candidate: 1/2 URL-classified")
    }

    @Test func capabilityProbeRecordsOnlyDocumentReferenceCandidateAvailabilityCategories() {
        var summary = ZoteroCapabilityProbeSummary()
        summary.record([
            ZoteroCapabilityProbeObservation(
                candidate: .documentAttribute,
                outcome: .readable,
                valueCategory: .url
            )
        ])
        summary.record([
            ZoteroCapabilityProbeObservation(
                candidate: .documentAttribute,
                outcome: .readable,
                valueCategory: .string
            )
        ])
        summary.record([
            ZoteroCapabilityProbeObservation(
                candidate: .windowTitle,
                outcome: .readable,
                valueCategory: .url
            )
        ])

        #expect(summary.documentReferenceCandidateAvailability.sampleCount == 3)
        #expect(summary.documentReferenceCandidateAvailability.availableCount == 1)
        #expect(!summary.summary.contains("file:///private/secret.pdf"))
        #expect(!summary.summary.contains("Secret document title"))
    }

    @Test func failedProbeStatusContainsOnlyFailureCategory() {
        let status = ZoteroCapabilityProbeStatus.failed(.zoteroNotFrontmost)

        #expect(status.summary == "Probe status: Zotero not frontmost.")
        #expect(!status.summary.contains("Sensitive probe value"))
    }

    @Test func successfulProbeSummaryContainsOnlyMetadata() {
        let snapshot = SelectionSnapshot(
            hostBundleIdentifier: "org.zotero.zotero",
            selectedText: "twelve chars",
            selectedRange: NSRange(location: 4, length: 12)
        )

        #expect(
            snapshot.diagnosticSummary
                == "Selection: 12 characters; text range unavailable"
        )
    }

    @Test @MainActor func selectionTextConsistencyReportsOnlyWhetherHostQueriesAgree() {
        #expect(
            SelectionTextConsistency(
                directText: "Synthetic selection.",
                rangeText: "Synthetic selection."
            ) == .matches
        )
        #expect(
            SelectionTextConsistency(
                directText: "Synthetic selection.",
                rangeText: "Synthetic selectio."
            ) == .differs
        )
        #expect(
            SelectionTextConsistency(
                directText: "Synthetic selection.",
                rangeText: nil
            ) == .unavailable
        )
        #expect(
            !SelectionTextConsistency.differs.diagnosticDescription.contains("Synthetic")
        )
    }

}
#endif
