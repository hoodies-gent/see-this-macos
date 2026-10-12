import Foundation

enum PaperContextSession {
    case disabled
    case enabled

    var isEnabled: Bool {
        self == .enabled
    }

    var statusDescription: String {
        isEnabled
            ? "File context is enabled for this app session."
            : "File context is off. Explanations use only the selected passage."
    }

    func titleForRequest(documentTitle: String?) -> String? {
        guard isEnabled,
              let documentTitle = documentTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !documentTitle.isEmpty else {
            return nil
        }
        return documentTitle
    }

    func localContext(for selectedText: String, in readingSession: ReadingSession) -> String? {
        guard isEnabled else { return nil }
        return readingSession.context(for: selectedText)
    }

    func matchStatus(
        for selectedText: String,
        in readingSession: ReadingSession
    ) -> DocumentSourceMatchStatus? {
        guard isEnabled else { return nil }
        return readingSession.matchStatus(for: selectedText)
    }

    func matchKind(
        for selectedText: String,
        in readingSession: ReadingSession
    ) -> DocumentSourceMatchKind? {
        guard isEnabled else { return nil }
        return readingSession.matchKind(for: selectedText)
    }
}
