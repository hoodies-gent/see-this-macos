import Foundation
import PDFKit

typealias AuthorizedTextSource = DocumentSource

enum ReadingSession {
    case disabled
    case enabled(DocumentSource, rawText: String, hostBundleIdentifier: String? = nil)

    static let defaultFullContextCharacterLimit = 20_000
    static let minimumFullContextCharacterLimit = 5_000
    static let maximumFullContextCharacterLimit = 100_000
    static var fullContextCharacterLimit = defaultFullContextCharacterLimit

    var displayName: String? {
        guard case let .enabled(source, _, _) = self else { return nil }
        return source.displayName
    }

    var format: DocumentSource.Format? {
        guard case let .enabled(source, _, _) = self else { return nil }
        return source.format
    }

    var hostBundleIdentifier: String? {
        guard case let .enabled(_, _, bundle) = self else { return nil }
        return bundle
    }

    var fullText: String? {
        guard case let .enabled(_, rawText, _) = self else { return nil }
        return rawText
    }

    var isFullTextTruncated: Bool {
        guard let fullText else { return false }
        return fullText.count > Self.fullContextCharacterLimit
    }

    struct ContextWindow {
        enum Mode { case whole, selectionWindow, prefix }
        let text: String
        let mode: Mode
    }

    func fullTextWindow(around selectedText: String) -> ContextWindow? {
        guard let rawText = fullText else { return nil }
        let limit = Self.fullContextCharacterLimit
        if rawText.count <= limit {
            return ContextWindow(text: rawText, mode: .whole)
        }

        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ContextWindow(text: String(rawText.prefix(limit)), mode: .prefix)
        }

        if let matchRange = rawText.range(of: trimmed) {
            return Self.windowedContext(around: matchRange, in: rawText, limit: limit)
        }

        if trimmed.count >= 4 {
            let (normalizedSelection, _) = Self.normalizedWhitespace(trimmed)
            let (normalizedRaw, rawGraphemeOffsets) = Self.normalizedWhitespace(rawText)
            if let normRange = normalizedRaw.range(of: normalizedSelection) {
                let normStart = normalizedRaw.distance(from: normalizedRaw.startIndex, to: normRange.lowerBound)
                if normStart < rawGraphemeOffsets.count {
                    let rawStart = rawGraphemeOffsets[normStart]
                    let startIndex = rawText.index(rawText.startIndex, offsetBy: rawStart)
                    return Self.windowedContext(around: startIndex..<startIndex, in: rawText, limit: limit)
                }
            }
        }

        return ContextWindow(text: String(rawText.prefix(limit)), mode: .prefix)
    }

    private static func windowedContext(
        around matchRange: Range<String.Index>,
        in rawText: String,
        limit: Int
    ) -> ContextWindow {
        let charCount = rawText.count
        let matchStartOffset = rawText.distance(from: rawText.startIndex, to: matchRange.lowerBound)
        let halfBefore = limit / 2
        var windowStart = max(0, matchStartOffset - halfBefore)
        let windowEnd = min(charCount, windowStart + limit)
        if windowEnd - windowStart < limit {
            windowStart = max(0, windowEnd - limit)
        }
        let startIndex = rawText.index(rawText.startIndex, offsetBy: windowStart)
        let endIndex = rawText.index(rawText.startIndex, offsetBy: windowEnd)
        return ContextWindow(text: String(rawText[startIndex..<endIndex]), mode: .selectionWindow)
    }

    private static let markdownSyntaxStripCharacters: Set<Character> = [
        "*", "_", "`", "~", "\\", "[", "]", "(", ")"
    ]

    private static func normalizedWhitespace(_ text: String) -> (String, [Int]) {
        var normalizedChars: [Character] = []
        var rawOffsets: [Int] = []
        var inWhitespace = false
        var rawIndex = 0
        for char in text {
            if markdownSyntaxStripCharacters.contains(char) {
                // Skip common markdown inline syntax so a rendered-text selection
                // can still locate itself inside raw markdown source.
            } else if char.isWhitespace {
                if !inWhitespace {
                    normalizedChars.append(" ")
                    rawOffsets.append(rawIndex)
                    inWhitespace = true
                }
            } else {
                normalizedChars.append(char)
                rawOffsets.append(rawIndex)
                inWhitespace = false
            }
            rawIndex += 1
        }
        return (String(normalizedChars), rawOffsets)
    }

    var statusDescription: String {
        guard let displayName, let format else {
            return "No file attached."
        }
        let sent = isFullTextTruncated
            ? "Each request sends about \(Self.fullContextCharacterLimit.formatted()) characters around your selection."
            : "The whole file is sent with each request."
        return "Attached: \(displayName) (\(format.displayName)). \(sent)"
    }

    func matchesHost(_ bundleIdentifier: String?) -> Bool {
        guard case let .enabled(_, _, boundBundle) = self else { return false }
        guard let boundBundle else { return true }
        return boundBundle == bundleIdentifier
    }

    func context(for selectedText: String) -> String? {
        guard case let .enabled(source, _, _) = self else { return nil }
        return source.context(for: selectedText)
    }

    func matchStatus(for selectedText: String) -> DocumentSourceMatchStatus? {
        guard case let .enabled(source, _, _) = self else { return nil }
        return source.matchStatus(for: selectedText)
    }

    func matchKind(for selectedText: String) -> DocumentSourceMatchKind? {
        guard case let .enabled(source, _, _) = self else { return nil }
        return source.matchKind(for: selectedText)
    }

    static func load(url: URL, hostBundleIdentifier: String? = nil) throws -> ReadingSession {
        let source = try DocumentSource.load(url: url)
        let rawText = try loadRawText(from: url)
        return .enabled(source, rawText: rawText, hostBundleIdentifier: hostBundleIdentifier)
    }

    private static func loadRawText(from url: URL) throws -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":
            guard let document = PDFDocument(url: url), let text = document.string else {
                throw DocumentSourceLoadFailure.unreadableDocument
            }
            return text
        case "txt", "md", "markdown":
            do {
                return try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw DocumentSourceLoadFailure.unreadableDocument
            }
        default:
            throw DocumentSourceLoadFailure.unsupportedFormat
        }
    }
}
