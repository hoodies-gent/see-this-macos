import Foundation
import Testing
@testable import SeeThis

struct DocumentContextTests {
    @Test func paperContextSessionUsesOnlyTheCurrentCapturedTitleWhenEnabled() {
        #expect(PaperContextSession.disabled.titleForRequest(documentTitle: "Current paper") == nil)
        #expect(PaperContextSession.enabled.titleForRequest(documentTitle: nil) == nil)
        #expect(PaperContextSession.enabled.titleForRequest(documentTitle: "") == nil)
        #expect(PaperContextSession.enabled.titleForRequest(documentTitle: "Current paper") == "Current paper")
    }

    @Test @MainActor func smallAttachedFileSendsTheWholeFileEvenWhenTheSelectionIsMissing() {
        let rawText = "Entire small file."
        let session = makeSession(displayName: "reading.txt", rawText: rawText)

        let window = session.fullTextWindow(around: "Missing selection")

        #expect(window?.text == rawText)
        guard let window else { return }
        if case .whole = window.mode {
            // Expected mode.
        } else {
            Issue.record("Expected the whole-file context mode")
        }
    }

    @Test @MainActor func largeAttachedFileSendsAWindowAroundTheSelection() {
        let limit = ReadingSession.fullContextCharacterLimit
        let selection = "unique selected passage"
        let rawText = "BEGIN-"
            + String(repeating: "a", count: limit)
            + selection
            + String(repeating: "z", count: limit)
        let session = makeSession(displayName: "reading.txt", rawText: rawText)

        let window = session.fullTextWindow(around: selection)

        #expect(window?.text.count == limit)
        #expect(window?.text.contains(selection) == true)
        #expect(window?.text.hasPrefix("BEGIN-") == false)
        guard let window else { return }
        if case .selectionWindow = window.mode {
            // Expected mode.
        } else {
            Issue.record("Expected the selection-window context mode")
        }
    }

    @Test @MainActor func largeMarkdownFileLocatesARenderedSelection() {
        let limit = ReadingSession.fullContextCharacterLimit
        let rawSelection = "**selected   passage**"
        let rawText = String(repeating: "a", count: limit)
            + rawSelection
            + String(repeating: "z", count: limit)
        let session = makeSession(displayName: "reading.md", format: .markdown, rawText: rawText)

        let window = session.fullTextWindow(around: "selected passage")

        #expect(window?.text.count == limit)
        #expect(window?.text.contains(rawSelection) == true)
        guard let window else { return }
        if case .selectionWindow = window.mode {
            // Expected mode.
        } else {
            Issue.record("Expected rendered Markdown to use the selection-window mode")
        }
    }

    @Test @MainActor func largeAttachedFileFallsBackToTheDocumentStartWhenSelectionIsMissing() {
        let limit = ReadingSession.fullContextCharacterLimit
        let rawText = "START-" + String(repeating: "x", count: limit + 50)
        let session = makeSession(displayName: "reading.txt", rawText: rawText)

        let window = session.fullTextWindow(around: "Missing selection")

        #expect(window?.text == String(rawText.prefix(limit)))
        guard let window else { return }
        if case .prefix = window.mode {
            // Expected mode.
        } else {
            Issue.record("Expected the document-prefix context mode")
        }
    }

    @Test @MainActor func attachedFileMatchesOnlyItsBoundHostUnlessUnbound() {
        let bound = makeSession(
            displayName: "reading.txt",
            rawText: "Short.",
            hostBundleIdentifier: "org.example.reader"
        )
        let unbound = makeSession(displayName: "reading.txt", rawText: "Short.")

        #expect(bound.matchesHost("org.example.reader"))
        #expect(!bound.matchesHost("org.example.other"))
        #expect(!bound.matchesHost(nil))
        #expect(unbound.matchesHost("org.example.other"))
        #expect(unbound.matchesHost(nil))
        #expect(!ReadingSession.disabled.matchesHost("org.example.reader"))
    }

    @Test @MainActor func documentSourceRecognizesExplicitPDFTXTAndMarkdownSelections() {
        #expect(DocumentSource.Format(url: URL(filePath: "/tmp/reading.pdf")) == .pdf)
        #expect(DocumentSource.Format(url: URL(filePath: "/tmp/reading.txt")) == .plainText)
        #expect(DocumentSource.Format(url: URL(filePath: "/tmp/reading.markdown")) == .markdown)
    }

    @Test @MainActor func readingSessionStatusContainsOnlyDocumentMetadata() {
        let session = makeSession(displayName: "reading.txt", rawText: "Private source content.")

        #expect(session.displayName == "reading.txt")
        #expect(session.format == .plainText)
        #expect(!session.statusDescription.contains("Private source content."))
    }

    @Test @MainActor func attachedFileStatusExplainsHowMuchContentIsSent() {
        let short = makeSession(displayName: "reading.txt", rawText: "Short.")
        let longText = String(repeating: "x", count: ReadingSession.fullContextCharacterLimit + 1)
        let long = makeSession(displayName: "long.txt", rawText: longText)

        #expect(short.statusDescription.contains("reading.txt"))
        #expect(short.statusDescription.contains("The whole file is sent"))
        #expect(long.statusDescription.contains("around your selection"))
        #expect(ReadingSession.disabled.statusDescription == "No file attached.")
    }

    @MainActor
    private func makeSession(
        displayName: String,
        format: DocumentSource.Format = .plainText,
        rawText: String,
        hostBundleIdentifier: String? = nil
    ) -> ReadingSession {
        ReadingSession.enabled(
            DocumentSource(displayName: displayName, format: format, extractedText: rawText),
            rawText: rawText,
            hostBundleIdentifier: hostBundleIdentifier
        )
    }
}
