import Foundation
import PDFKit

struct DocumentSource {
    enum Format: Equatable {
        case pdf
        case plainText
        case markdown

        init?(url: URL) {
            switch url.pathExtension.lowercased() {
            case "pdf": self = .pdf
            case "txt": self = .plainText
            case "md", "markdown": self = .markdown
            default: return nil
            }
        }

        var displayName: String {
            switch self {
            case .pdf: "PDF"
            case .plainText: "TXT"
            case .markdown: "Markdown"
            }
        }
    }

    let displayName: String
    let format: Format
    private let normalizedParagraphs: [String]
    private let hyphenationFoldedParagraphs: [String]

    init(displayName: String, format: Format, extractedText: String) {
        self.displayName = displayName
        self.format = format
        let paragraphs = extractedText.components(separatedBy: "\n\n")
        normalizedParagraphs = paragraphs
            .map(Self.normalize)
            .filter { !$0.isEmpty }
        hyphenationFoldedParagraphs = paragraphs
            .map(Self.normalizeFoldingLineBreakHyphenation)
            .filter { !$0.isEmpty }
    }

    init(displayName: String, content: String) {
        self.init(displayName: displayName, format: .plainText, extractedText: content)
    }

    static func load(url: URL) throws -> DocumentSource {
        guard let format = Format(url: url) else {
            throw DocumentSourceLoadFailure.unsupportedFormat
        }

        let extractedText: String
        switch format {
        case .pdf:
            guard let document = PDFDocument(url: url), let text = document.string else {
                throw DocumentSourceLoadFailure.unreadableDocument
            }
            extractedText = text
        case .plainText, .markdown:
            do {
                extractedText = try String(contentsOf: url, encoding: .utf8)
            } catch {
                throw DocumentSourceLoadFailure.unreadableDocument
            }
        }

        guard !Self.normalize(extractedText).isEmpty else {
            throw DocumentSourceLoadFailure.unreadableDocument
        }
        return DocumentSource(
            displayName: url.lastPathComponent,
            format: format,
            extractedText: extractedText
        )
    }

    func context(for selectedText: String) -> String? {
        guard case let .matched(context, _) = bestMatch(for: selectedText) else { return nil }
        return context
    }

    func matchKind(for selectedText: String) -> DocumentSourceMatchKind? {
        guard case let .matched(_, kind) = bestMatch(for: selectedText) else { return nil }
        return kind
    }

    func matchStatus(for selectedText: String) -> DocumentSourceMatchStatus {
        switch bestMatch(for: selectedText) {
        case .matched: .matched
        case .ambiguous: .ambiguous
        case .notFound: .notFound
        }
    }

    private func bestMatch(for selectedText: String) -> Match {
        let strict = strictMatch(for: selectedText, in: normalizedParagraphs)
        guard case .notFound = strict else { return strict }

        let tokenSequence = tokenSequenceMatch(for: selectedText, in: normalizedParagraphs)
        guard case .notFound = tokenSequence else { return tokenSequence }

        let hyphenationFolded = tokenSequenceMatch(
            for: selectedText,
            in: hyphenationFoldedParagraphs
        )
        guard case .notFound = hyphenationFolded else { return hyphenationFolded }

        return textAnchorMatch(for: selectedText, in: normalizedParagraphs)
    }

    private func strictMatch(for selectedText: String, in paragraphs: [String]) -> Match {
        let normalizedSelection = Self.normalize(selectedText)
        guard !normalizedSelection.isEmpty else { return .notFound }

        let matches = paragraphs.flatMap { paragraph in
            ranges(of: normalizedSelection, in: paragraph).map { (paragraph, $0) }
        }
        guard matches.count == 1, let (paragraph, match) = matches.first else {
            return matches.isEmpty ? .notFound : .ambiguous
        }

        return .matched(
            boundedContext(in: paragraph, around: match),
            kind: .exactSelection
        )
    }

    private func tokenSequenceMatch(for selectedText: String, in paragraphs: [String]) -> Match {
        let selectionTokens = tokens(in: selectedText).map(\.value)
        guard !selectionTokens.isEmpty else { return .notFound }

        let matches = paragraphs.flatMap { paragraph in
            let paragraphTokens = tokens(in: paragraph)
            guard paragraphTokens.count >= selectionTokens.count else { return [String]() }

            return paragraphTokens.indices.compactMap { start in
                let end = start + selectionTokens.count
                guard end <= paragraphTokens.count,
                      paragraphTokens[start..<end].map(\.value) == selectionTokens else {
                    return nil
                }
                return boundedContext(
                    in: paragraph,
                    around: paragraphTokens[start].range.lowerBound..<paragraphTokens[end - 1].range.upperBound
                )
            }
        }

        guard matches.count == 1 else {
            return matches.isEmpty ? .notFound : .ambiguous
        }
        return .matched(matches[0], kind: .exactSelection)
    }

    private func textAnchorMatch(for selectedText: String, in paragraphs: [String]) -> Match {
        let anchorTokens = textualTokens(in: selectedText).map(\.value)
        guard anchorTokens.count >= 4 else { return .notFound }

        for length in stride(from: anchorTokens.count, through: 4, by: -1) {
            var occurrences: [AnchorOccurrence] = []

            for selectionStart in 0...(anchorTokens.count - length) {
                let candidate = Array(anchorTokens[selectionStart..<(selectionStart + length)])

                for (paragraphIndex, paragraph) in paragraphs.enumerated() {
                    let paragraphTokens = textualTokens(in: paragraph)
                    guard paragraphTokens.count >= length else { continue }

                    for paragraphStart in 0...(paragraphTokens.count - length) {
                        let paragraphEnd = paragraphStart + length
                        guard paragraphTokens[paragraphStart..<paragraphEnd].map(\.value) == candidate else {
                            continue
                        }
                        occurrences.append(
                            AnchorOccurrence(
                                paragraphIndex: paragraphIndex,
                                tokenRange: paragraphStart..<paragraphEnd
                            )
                        )
                    }
                }
            }

            guard !occurrences.isEmpty else { continue }
            let clusters = clusteredOccurrences(occurrences)
            guard clusters.count == 1, let cluster = clusters.first else {
                return .ambiguous
            }

            let paragraph = paragraphs[cluster.paragraphIndex]
            let paragraphTokens = textualTokens(in: paragraph)
            return .matched(
                boundedContext(
                    in: paragraph,
                    around: paragraphTokens[cluster.tokenRange.lowerBound].range.lowerBound..<paragraphTokens[cluster.tokenRange.upperBound - 1].range.upperBound
                ),
                kind: .textAnchor
            )
        }

        return .notFound
    }

    private func clusteredOccurrences(_ occurrences: [AnchorOccurrence]) -> [AnchorOccurrence] {
        let sorted = occurrences.sorted {
            $0.paragraphIndex == $1.paragraphIndex
                ? $0.tokenRange.lowerBound < $1.tokenRange.lowerBound
                : $0.paragraphIndex < $1.paragraphIndex
        }
        var clusters: [AnchorOccurrence] = []

        for occurrence in sorted {
            guard let previous = clusters.last,
                  previous.paragraphIndex == occurrence.paragraphIndex,
                  occurrence.tokenRange.lowerBound < previous.tokenRange.upperBound else {
                clusters.append(occurrence)
                continue
            }
            clusters[clusters.count - 1] = AnchorOccurrence(
                paragraphIndex: previous.paragraphIndex,
                tokenRange: previous.tokenRange.lowerBound..<max(previous.tokenRange.upperBound, occurrence.tokenRange.upperBound)
            )
        }
        return clusters
    }

    private func ranges(of selection: String, in text: String) -> [Range<String.Index>] {
        var matches: [Range<String.Index>] = []
        var searchStart = text.startIndex

        while let range = text.range(of: selection, range: searchStart..<text.endIndex) {
            matches.append(range)
            searchStart = range.upperBound
        }
        return matches
    }

    private func tokens(in text: String) -> [(value: String, range: Range<String.Index>)] {
        var results: [(value: String, range: Range<String.Index>)] = []
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: .byWords
        ) { substring, range, _, _ in
            guard let substring else { return }
            results.append((
                value: substring.precomposedStringWithCompatibilityMapping.lowercased(),
                range: range
            ))
        }
        return results
    }

    private func textualTokens(in text: String) -> [(value: String, range: Range<String.Index>)] {
        tokens(in: text).filter { token in
            token.value.count >= 2 && token.value.unicodeScalars.contains {
                CharacterSet.letters.contains($0)
            }
        }
    }

    private func boundedContext(in paragraph: String, around range: Range<String.Index>) -> String {
        let start = paragraph.index(
            range.lowerBound,
            offsetBy: -600,
            limitedBy: paragraph.startIndex
        ) ?? paragraph.startIndex
        let end = paragraph.index(
            range.upperBound,
            offsetBy: 600,
            limitedBy: paragraph.endIndex
        ) ?? paragraph.endIndex
        return String(paragraph[start..<end])
    }

    nonisolated private static func normalize(_ text: String) -> String {
        text
            .precomposedStringWithCompatibilityMapping
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    nonisolated private static func normalizeFoldingLineBreakHyphenation(_ text: String) -> String {
        normalize(
            text
                .replacingOccurrences(of: "-\r\n", with: "")
                .replacingOccurrences(of: "-\n", with: "")
                .replacingOccurrences(of: "\u{00AD}", with: "")
        )
    }

    private enum Match {
        case matched(String, kind: DocumentSourceMatchKind)
        case notFound
        case ambiguous
    }

    private struct AnchorOccurrence {
        let paragraphIndex: Int
        let tokenRange: Range<Int>
    }
}

enum DocumentSourceMatchKind: Equatable {
    case exactSelection
    case textAnchor
}

enum DocumentSourceMatchStatus: Equatable {
    case matched
    case notFound
    case ambiguous

    var diagnosticDescription: String {
        switch self {
        case .matched: "Local context: unique match found."
        case .notFound: "Local context: no match found."
        case .ambiguous: "Local context: multiple matches found."
        }
    }
}

enum DocumentSourceLoadFailure: Error, Equatable {
    case unsupportedFormat
    case unreadableDocument
}
