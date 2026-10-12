import AppKit
import SwiftUI

enum OverlayAnswerInteraction {
    static let usesSingleSelectableDocument = true
    static let usesScrollPhaseTracking = true
    static let protectsAnswerSurfaceFromWindowDragging = true
    static let usesNativeTextView = true
    static let allowsSelectionFromAnswerPadding = true
}

enum OverlayNativeMarkdownAttribute {
    static let inlineCode = NSAttributedString.Key("projectContext.inlineCode")
    static let codeBlock = NSAttributedString.Key("projectContext.codeBlock")
    static let quote = NSAttributedString.Key("projectContext.quote")
}

private final class OverlayMarkdownLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let textStorage else {
            super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
            return
        }

        for characterRange in OverlayMarkdownRenderer.codeBlockRanges(in: textStorage) {
            guard let rect = enclosingCodeBlockRect(for: characterRange) else { continue }
            NSColor.labelColor.withAlphaComponent(0.06).setFill()
            NSBezierPath(
                roundedRect: rect.offsetBy(dx: origin.x, dy: origin.y).insetBy(
                    dx: OverlayMarkdownAppearance.codeBlockContainerInset,
                    dy: -OverlayMarkdownAppearance.codeBlockContentPadding
                ),
                xRadius: OverlayMarkdownAppearance.codeBlockCornerRadius,
                yRadius: OverlayMarkdownAppearance.codeBlockCornerRadius
            ).fill()
        }

        for characterRange in OverlayMarkdownRenderer.inlineCodeRanges(in: textStorage) {
            let glyphRange = glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
            guard glyphRange.location != NSNotFound else { continue }
            let rect = boundingRect(forGlyphRange: glyphRange, in: textContainers.first ?? NSTextContainer())
            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(
                roundedRect: rect.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -3, dy: -1),
                xRadius: OverlayMarkdownAppearance.inlineCodeCornerRadius,
                yRadius: OverlayMarkdownAppearance.inlineCodeCornerRadius
            ).fill()
        }

        enumerateLineFragments(forGlyphRange: glyphsToShow) { lineRect, usedRect, _, glyphRange, _ in
            let characterRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            guard characterRange.location != NSNotFound,
                  textStorage.attribute(OverlayNativeMarkdownAttribute.quote, at: characterRange.location, effectiveRange: nil) != nil
            else { return }
            NSColor.quaternaryLabelColor.setFill()
            NSBezierPath(
                rect: CGRect(
                    x: lineRect.minX + OverlayMarkdownAppearance.quoteBarOffset + origin.x,
                    y: usedRect.minY + origin.y,
                    width: OverlayMarkdownAppearance.quoteBarWidth,
                    height: usedRect.height
                )
            ).fill()
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    private func enclosingCodeBlockRect(for characterRange: NSRange) -> NSRect? {
        let glyphRange = glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        guard glyphRange.location != NSNotFound else { return nil }
        var lineRect: NSRect?
        var usedRect: NSRect?
        enumerateLineFragments(forGlyphRange: glyphRange) { fragmentRect, fragmentUsedRect, _, _, _ in
            lineRect = lineRect.map { $0.union(fragmentRect) } ?? fragmentRect
            usedRect = usedRect.map { $0.union(fragmentUsedRect) } ?? fragmentUsedRect
        }
        guard let lineRect, let usedRect else { return nil }
        return NSRect(x: lineRect.minX, y: usedRect.minY, width: lineRect.width, height: usedRect.height)
    }
}

final class AnswerTextScrollView: NSScrollView {
    override var mouseDownCanMoveWindow: Bool { false }
}

struct NativeMarkdownAnswer: NSViewRepresentable {
    let text: NSAttributedString
    let followsLatestContent: Bool
    let onUserScroll: () -> Void

    final class Coordinator {
        var onUserScroll: () -> Void
        var ignoresScrollObservation = false
        private var scrollObserver: NSObjectProtocol?

        init(onUserScroll: @escaping () -> Void) {
            self.onUserScroll = onUserScroll
        }

        func observe(_ scrollView: AnswerTextScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                guard let self, !self.ignoresScrollObservation else { return }
                self.onUserScroll()
            }
        }

        deinit {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onUserScroll: onUserScroll)
    }

    func makeNSView(context: Context) -> AnswerTextScrollView {
        let scrollView = AnswerTextScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textStorage = NSTextStorage()
        let layoutManager = OverlayMarkdownLayoutManager()
        let textContainer = NSTextContainer(size: .zero)
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.allowsUndo = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = [.width]
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        scrollView.documentView = textView
        context.coordinator.observe(scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: AnswerTextScrollView, context: Context) {
        context.coordinator.onUserScroll = onUserScroll
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if !textView.attributedString().isEqual(to: text) {
            textView.textStorage?.setAttributedString(text)
        }
        guard followsLatestContent else { return }
        context.coordinator.ignoresScrollObservation = true
        textView.scrollRangeToVisible(NSRange(location: text.length, length: 0))
        context.coordinator.ignoresScrollObservation = false
    }
}

enum OverlayMarkdownBlockStyle: Equatable {
    case text
    case code
    case quote
}

struct OverlayMarkdownBlock: Identifiable {
    let id: Int
    let text: AttributedString
    let style: OverlayMarkdownBlockStyle
}

enum OverlayMarkdownAppearance {
    static let inlineCodeCornerRadius: CGFloat = 4
    static let codeBlockOuterSpacing: CGFloat = 8
    static let codeBlockContentPadding: CGFloat = 12
    static let codeBlockContainerInset: CGFloat = 4
    static let codeBlockLineSpacing: CGFloat = 0
    static let codeBlockTextInset: CGFloat = 16
    static let codeBlockCornerRadius: CGFloat = 8
    static let quoteBarOffset: CGFloat = 6
    static let quoteTextInset: CGFloat = 9
    static let quoteBarWidth: CGFloat = 2
    static let answerCornerRadius: CGFloat = 10
    static let answerBackgroundOpacity = 0.04
    static let answerBorderOpacity = 0.1
}

enum OverlayMarkdownRenderer {
    static func nativeText(for answer: String) -> NSAttributedString {
        let rendered = NSMutableAttributedString()

        for block in blocks(for: answer) {
            if rendered.length > 0 {
                rendered.append(NSAttributedString(string: "\n"))
            }
            for run in block.text.runs {
                let fragment = String(block.text[run.range].characters)
                rendered.append(
                    NSAttributedString(
                        string: fragment,
                        attributes: nativeAttributes(for: run, blockStyle: block.style)
                    )
                )
            }
        }

        return rendered
    }

    static func codeBlockRanges(in text: NSAttributedString) -> [NSRange] {
        attributeRanges(OverlayNativeMarkdownAttribute.codeBlock, in: text)
    }

    static func inlineCodeRanges(in text: NSAttributedString) -> [NSRange] {
        attributeRanges(OverlayNativeMarkdownAttribute.inlineCode, in: text)
    }

    private static func attributeRanges(
        _ attribute: NSAttributedString.Key,
        in text: NSAttributedString
    ) -> [NSRange] {
        let fullRange = NSRange(location: 0, length: text.length)
        var ranges: [NSRange] = []
        text.enumerateAttribute(attribute, in: fullRange) { value, range, _ in
            if value != nil {
                ranges.append(range)
            }
        }
        return ranges
    }

    static func attributedText(
        for answer: String,
        parser: (String) throws -> AttributedString = { answer in
            try AttributedString(markdown: answer, options: .init(interpretedSyntax: .full))
        }
    ) -> AttributedString {
        let blocks = blocks(for: answer, parser: parser)
        var displayed = AttributedString()

        for block in blocks {
            if !displayed.characters.isEmpty {
                appendBlockSeparator(to: &displayed)
            }
            displayed += block.text
        }

        return displayed
    }

    static func blocks(
        for answer: String,
        parser: (String) throws -> AttributedString = { answer in
            try AttributedString(markdown: answer, options: .init(interpretedSyntax: .full))
        }
    ) -> [OverlayMarkdownBlock] {
        do {
            return readerVisibleBlocks(from: try parser(answer))
        } catch {
            return [OverlayMarkdownBlock(id: 0, text: AttributedString(answer), style: .text)]
        }
    }

    private static func readerVisibleBlocks(from parsed: AttributedString) -> [OverlayMarkdownBlock] {
        var blocks: [OverlayMarkdownBlock] = []
        var currentText = AttributedString()
        var currentBlockID: Int?
        var currentListID: Int?
        var currentStyle = OverlayMarkdownBlockStyle.text
        var nextBlockID = 0

        func appendCurrentBlock() {
            guard !currentText.characters.isEmpty else { return }
            blocks.append(
                OverlayMarkdownBlock(
                    id: nextBlockID,
                    text: currentText,
                    style: currentStyle
                )
            )
            nextBlockID += 1
        }

        for run in parsed.runs {
            let intent = run.presentationIntent
            let blockID = intent?.components.first?.identity
            let listID = listID(in: intent)
            let continuesList = listID != nil && listID == currentListID && blockID != currentBlockID

            if blockID != currentBlockID && !continuesList {
                appendCurrentBlock()
                currentText = AttributedString(listPrefix(in: intent))
                currentBlockID = blockID
                currentListID = listID
                currentStyle = blockStyle(in: intent)
            } else if continuesList {
                currentText += AttributedString("\n" + listPrefix(in: intent))
                currentBlockID = blockID
                currentListID = listID
            }

            var fragment = AttributedString(parsed[run.range])
            fragment[fragment.startIndex..<fragment.endIndex].link = nil
            if let font = blockFont(in: intent) {
                fragment[fragment.startIndex..<fragment.endIndex].font = font
            }
            if run.inlinePresentationIntent?.contains(.code) == true {
                fragment[fragment.startIndex..<fragment.endIndex].font = .system(.body, design: .monospaced)
                fragment[fragment.startIndex..<fragment.endIndex].backgroundColor = Color.primary.opacity(0.08)
            }
            currentText += fragment
        }

        appendCurrentBlock()
        return blocks
    }

    private static func appendBlockSeparator(to displayed: inout AttributedString) {
        let requiredNewlines = 2
        let trailingNewlines = String(displayed.characters)
            .reversed()
            .prefix(while: { $0 == "\n" })
            .count
        guard trailingNewlines < requiredNewlines else { return }
        displayed += AttributedString(String(repeating: "\n", count: requiredNewlines - trailingNewlines))
    }

    private static func listID(in intent: PresentationIntent?) -> Int? {
        intent?.components.first { component in
            switch component.kind {
            case .orderedList, .unorderedList:
                true
            default:
                false
            }
        }?.identity
    }

    private static func listPrefix(in intent: PresentationIntent?) -> String {
        guard
            let components = intent?.components,
            let listItem = components.first(where: { component in
                if case .listItem = component.kind { return true }
                return false
            }),
            let list = components.first(where: { component in
                switch component.kind {
                case .orderedList, .unorderedList:
                    true
                default:
                    false
                }
            })
        else {
            return ""
        }

        switch list.kind {
        case .unorderedList:
            return "• "
        case .orderedList:
            if case let .listItem(ordinal) = listItem.kind {
                return "\(ordinal). "
            }
            return ""
        default:
            return ""
        }
    }

    private static func blockFont(in intent: PresentationIntent?) -> Font? {
        guard let components = intent?.components else { return nil }
        for component in components {
            switch component.kind {
            case .header(level: 1):
                return .title2.weight(.bold)
            case .header(level: 2):
                return .title3.weight(.semibold)
            case .header:
                return .headline
            case .codeBlock:
                return .system(.body, design: .monospaced)
            default:
                continue
            }
        }
        return nil
    }

    private static func nativeAttributes(
        for run: AttributedString.Runs.Run,
        blockStyle: OverlayMarkdownBlockStyle
    ) -> [NSAttributedString.Key: Any] {
        let inlineIntent = run.inlinePresentationIntent
        var font = nativeFont(in: run.presentationIntent)
        if inlineIntent?.contains(.code) == true {
            font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        } else {
            if inlineIntent?.contains(.stronglyEmphasized) == true {
                font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
            if inlineIntent?.contains(.emphasized) == true {
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = blockStyle == .code
            ? OverlayMarkdownAppearance.codeBlockLineSpacing
            : OverlayMarkdownAppearance.codeBlockOuterSpacing
        if blockStyle == .code {
            paragraphStyle.paragraphSpacingBefore = OverlayMarkdownAppearance.codeBlockOuterSpacing
            paragraphStyle.firstLineHeadIndent = OverlayMarkdownAppearance.codeBlockTextInset
            paragraphStyle.headIndent = OverlayMarkdownAppearance.codeBlockTextInset
        }
        if blockStyle == .quote {
            paragraphStyle.firstLineHeadIndent = OverlayMarkdownAppearance.quoteTextInset
            paragraphStyle.headIndent = OverlayMarkdownAppearance.quoteTextInset
        }

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.labelColor
        ]
        if inlineIntent?.contains(.strikethrough) == true {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if inlineIntent?.contains(.code) == true {
            attributes[OverlayNativeMarkdownAttribute.inlineCode] = true
        }
        switch blockStyle {
        case .code:
            attributes[OverlayNativeMarkdownAttribute.codeBlock] = true
        case .quote:
            attributes[OverlayNativeMarkdownAttribute.quote] = true
            attributes[.foregroundColor] = NSColor.secondaryLabelColor
        case .text:
            break
        }
        return attributes
    }

    private static func nativeFont(in intent: PresentationIntent?) -> NSFont {
        guard let components = intent?.components else {
            return NSFont.systemFont(ofSize: NSFont.systemFontSize)
        }
        for component in components {
            switch component.kind {
            case .header(level: 1):
                return NSFont.systemFont(ofSize: 19, weight: .bold)
            case .header(level: 2):
                return NSFont.systemFont(ofSize: 18, weight: .semibold)
            case .header:
                return NSFont.systemFont(ofSize: 17, weight: .semibold)
            case .codeBlock:
                return NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            default:
                continue
            }
        }
        return NSFont.systemFont(ofSize: NSFont.systemFontSize)
    }

    private static func isHeader(in intent: PresentationIntent?) -> Bool {
        intent?.components.contains { component in
            if case .header = component.kind { return true }
            return false
        } == true
    }

    private static func blockStyle(in intent: PresentationIntent?) -> OverlayMarkdownBlockStyle {
        guard let components = intent?.components else { return .text }
        for component in components {
            switch component.kind {
            case .codeBlock:
                return .code
            case .blockQuote:
                return .quote
            default:
                continue
            }
        }
        return .text
    }
}
