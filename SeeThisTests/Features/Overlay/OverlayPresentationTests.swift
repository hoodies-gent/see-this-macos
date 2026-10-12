import CoreGraphics
import Carbon
import Foundation
import ApplicationServices
import AppKit
import SwiftUI
import Testing
@testable import SeeThis


struct OverlayPresentationTests {

    @Test func onlyAnswerOverlayContentIsScrollable() {
        #expect(!OverlayContentState.requesting(usesPaperContext: false).isScrollableAnswer)
        #expect(OverlayContentState.streaming("Partial.", usesPaperContext: false).isScrollableAnswer)
        #expect(OverlayContentState.answer("Explanation.", usesPaperContext: true).isScrollableAnswer)
        #expect(!OverlayContentState.failure("Failure.").isScrollableAnswer)
    }

    @Test func markdownRendererRemovesSyntaxWhileKeepingReaderVisibleText() {
        let rendered = OverlayMarkdownRenderer.attributedText(for: "## Result\n\n**Clear** and `local`.")
        #expect(String(rendered.characters).contains("Result"))
        #expect(String(rendered.characters).contains("Clear"))
        #expect(!String(rendered.characters).contains("**"))
        #expect(!String(rendered.characters).contains("`"))
    }

    @Test func markdownRendererFallsBackToTheRawAnswerWhenParsingFails() {
        let raw = "**Partial streamed answer"
        let rendered = OverlayMarkdownRenderer.attributedText(for: raw) { _ in
            throw NSError(domain: "OverlayMarkdownRendererTests", code: 1)
        }
        #expect(String(rendered.characters) == raw)
    }

    @Test func markdownRendererDisplaysLinkTextWithoutAnOpenableDestination() {
        let rendered = OverlayMarkdownRenderer.attributedText(for: "[Local paper](https://example.invalid/paper)")
        #expect(String(rendered.characters) == "Local paper")
        #expect(rendered.runs.allSatisfy { $0.link == nil })
    }

    @Test func markdownRendererKeepsVisibleBlockAndListSeparators() {
        let rendered = OverlayMarkdownRenderer.attributedText(
            for: "## Meaning\n\nSelf-attention is **clear**.\n\n- first\n- second\n\n```swift\nfunc f() {}\n```\n\n[Link](https://example.invalid)"
        )

        #expect(
            String(rendered.characters)
                == "Meaning\n\nSelf-attention is clear.\n\n• first\n• second\n\nfunc f() {}\n\nLink"
        )
    }

    @Test @MainActor func nativeMarkdownRendererKeepsHeaderAndCodeBlockPresentation() {
        let rendered = OverlayMarkdownRenderer.nativeText(
            for: "## Heading\n\nUse `symbol`.\n\n```python\nprint('example')\n```"
        )
        let string = rendered.string as NSString
        let headingRange = string.range(of: "Heading")
        let codeRange = string.range(of: "print('example')")

        let headingFont = rendered.attribute(.font, at: headingRange.location, effectiveRange: nil) as? NSFont

        #expect(headingFont?.pointSize ?? 0 > NSFont.systemFontSize)
        #expect(rendered.attribute(OverlayNativeMarkdownAttribute.inlineCode, at: string.range(of: "symbol").location, effectiveRange: nil) != nil)
        #expect(rendered.attribute(OverlayNativeMarkdownAttribute.codeBlock, at: codeRange.location, effectiveRange: nil) != nil)
    }

    @Test @MainActor func nativeMarkdownRendererKeepsHeadingScaleCompactForAnOverlay() {
        let rendered = OverlayMarkdownRenderer.nativeText(for: "# Primary\n\n## Secondary\n\n### Tertiary")
        let string = rendered.string as NSString
        let primary = rendered.attribute(.font, at: string.range(of: "Primary").location, effectiveRange: nil) as? NSFont
        let secondary = rendered.attribute(.font, at: string.range(of: "Secondary").location, effectiveRange: nil) as? NSFont
        let tertiary = rendered.attribute(.font, at: string.range(of: "Tertiary").location, effectiveRange: nil) as? NSFont

        #expect((primary?.pointSize ?? .greatestFiniteMagnitude) <= 19)
        #expect((primary?.pointSize ?? 0) - (secondary?.pointSize ?? 0) <= 2)
        #expect((secondary?.pointSize ?? 0) - (tertiary?.pointSize ?? 0) <= 1)
    }

    @Test @MainActor func nativeMarkdownRendererTreatsAContinuousCodeBlockAsOneDecoration() {
        let rendered = OverlayMarkdownRenderer.nativeText(for: "```python\nfirst()\nsecond()\n```")
        let codeBlocks = OverlayMarkdownRenderer.codeBlockRanges(in: rendered)

        #expect(codeBlocks.count == 1)
        #expect(String((rendered.string as NSString).substring(with: codeBlocks[0])) == "first()\nsecond()\n")
    }

    @Test @MainActor func nativeMarkdownRendererUsesAnAdaptiveTextColor() {
        let rendered = OverlayMarkdownRenderer.nativeText(for: "Visible in every appearance.")

        #expect(rendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == NSColor.labelColor)
    }

    @Test @MainActor func markdownRendererSeparatesQuoteAndCodePresentationBlocks() {
        let blocks = OverlayMarkdownRenderer.blocks(
            for: "> Quoted context.\n\nUse `symbol`.\n\n```python\nprint('example')\n```"
        )

        #expect(blocks.map(\.style) == [.quote, .text, .code])
        #expect(String(blocks[0].text.characters) == "Quoted context.")
        #expect(blocks[1].text.runs.contains { $0.backgroundColor != nil })
        #expect(String(blocks[2].text.characters) == "print('example')\n")
    }

    #if DEBUG
    @Test @MainActor func markdownShowcaseExercisesTheOverlayMarkdownPresentationPath() {
        let blocks = OverlayMarkdownRenderer.blocks(for: MarkdownShowcase.answer)

        #expect(MarkdownShowcase.answer.contains("```python"))
        #expect(MarkdownShowcase.answer.contains("Second line of the same paragraph"))
        #expect(MarkdownShowcase.answer.contains("<u>"))
        #expect(MarkdownShowcase.answer.contains("<strong>"))
        #expect(MarkdownShowcase.answer.contains("![Remote image]"))
        #expect(blocks.contains { $0.style == .quote })
        #expect(blocks.contains { $0.style == .code })
        #expect(blocks.flatMap(\.text.runs).allSatisfy { $0.link == nil })
    }
    #endif

    @Test @MainActor func streamingOverlayKeepsItsLensWithoutOfferingCopy() {
        let content = OverlayContentState.streaming(
            "Partial.",
            lenses: ExplanationLens.allCases,
            selectedLens: .plain,
            usesPaperContext: false,
            model: "gemma3:4b"
        )

        #expect(content.answerText == "Partial.")
        #expect(content.selectedLens == .plain)
        #expect(content.selectedLensDisplayName == "Explain")
        #expect(!content.showsCopyAction)
    }

    @Test @MainActor func streamingOverlayGrowsBeforeReachingItsScrollableLimit() {
        let short = OverlayContentState.streaming("One line.", usesPaperContext: false)
        let long = OverlayContentState.streaming(
            String(repeating: "Long streamed text. ", count: 80),
            usesPaperContext: false
        )

        #expect(short.preferredPanelSize().height < long.preferredPanelSize().height)
    }

    @Test @MainActor func overlayActivityStatusOccupiesTheFooterDuringRequestsAndStreaming() {
        let requesting = OverlayContentState.requesting(usesPaperContext: false)
        let short = OverlayContentState.streaming("One line.", usesPaperContext: false)
        let long = OverlayContentState.streaming(
            String(repeating: "Long streamed text. ", count: 80),
            usesPaperContext: false
        )

        #expect(requesting.activityStatusLabel == "Preparing…")
        #expect(short.isStreaming)
        #expect(short.activityStatusLabel == "Generating…")
        #expect(long.activityStatusLabel == "Generating…")
        #expect(OverlayContentState.answer("Explanation.", usesPaperContext: false).activityStatusLabel == nil)
        #expect(!OverlayContentState.answer(long.answerText ?? "", usesPaperContext: false).isStreaming)
    }

    @Test @MainActor func overlayUsesActionSpecificStatusBeforeDeepLReturns() {
        let action = ReaderAction.package(
            ResolvedAction(
                id: TranslateActionCoordinator.actionID,
                source: .package(version: SemanticVersion(1, 0, 0)),
                display: ActionDisplayInfo(name: "Translate with DeepL", allowsFollowUp: false),
                input: ActionInputRequirement(selection: .required),
                execution: .singleCapability(capabilityID: DeepLTranslationCapability.capabilityID),
                resolvedPermissions: [],
                budget: ActionBudget(maxModelCalls: 0, maxCapabilityCalls: 1),
                output: ActionOutputContract(kind: .text, format: .markdown)
            )
        )
        let requesting = OverlayContentState.requesting(usesPaperContext: false)

        #expect(requesting.activityStatusLabel(for: action) == "Translating…")
        #expect(OverlayActivityStatusText.loadingModel == "Loading model…")
    }

    @Test func selectionPreviewUsesOneCompactLineOfPanelSpace() {
        let content = OverlayContentState.requesting(usesPaperContext: false)

        #expect(OverlaySelectionPreviewLayout.maximumLineCount == 1)
        #expect(!OverlaySelectionPreviewLayout.allowsTextSelection)
        #expect(
            content.preferredPanelSize(selectionPreviewIsVisible: true).height
                > content.preferredPanelSize(selectionPreviewIsVisible: false).height
        )
        #expect(!content.isScrollableAnswer)
    }

    @Test @MainActor func overlayPanelPreservesBackgroundDraggingOutsideTheAnswerSurface() {
        let panel = ReadingOverlayPanel()

        #expect(panel.isMovableByWindowBackground)
        #expect(panel.canBecomeKey)
        #expect(!OverlayContentState.requesting(usesPaperContext: false).showsDragHandle)
        #expect(!OverlayContentState.answer("Explanation.", usesPaperContext: true).showsDragHandle)
        #expect(!OverlayContentState.failure("Failure.").showsDragHandle)
    }

    @Test @MainActor func answerTextViewSurfacePreventsWindowDragging() {
        #expect(!AnswerTextScrollView().mouseDownCanMoveWindow)
    }

    @Test @MainActor func overlayPanelUpdatesContentAndFrameTogether() {
        let panel = ReadingOverlayPanel()
        let frame = CGRect(x: 120, y: 240, width: 360, height: 280)

        panel.update(
            .requesting(usesPaperContext: false),
            selectionPreviewText: "Synthetic selection.",
            frame: frame
        )

        #expect(panel.frame == frame)
        #expect(panel.contentView != nil)
    }

    @Test @MainActor func overlayPanelReusesItsHostingViewAcrossContentUpdates() {
        let panel = ReadingOverlayPanel()
        panel.setContent(.requesting(usesPaperContext: false))
        let initialContentView = panel.contentView

        panel.setContent(.answer("Synthetic answer.", usesPaperContext: false))

        #expect(panel.contentView === initialContentView)
    }

    @Test @MainActor func completedShortAnswerKeepsSeveralLinesVisibleAboveTheFooter() throws {
        let answer = "First line.\nSecond line.\nThird line.\nFourth line.\nFifth line."
        let content = OverlayContentState.answer(
            answer,
            lenses: [.plain, .translation(targetLanguage: "English")],
            selectedLens: .plain,
            usesPaperContext: false
        )
        let panel = ReadingOverlayPanel()
        let size = content.preferredPanelSize(selectionPreviewIsVisible: true)

        panel.update(
            content,
            selectionPreviewText: "Synthetic selection.",
            frame: CGRect(origin: .zero, size: size),
            onQuestionSubmitted: { _ in }
        )
        panel.contentView?.layoutSubtreeIfNeeded()

        let scrollView = try #require(firstAnswerScrollView(in: panel.contentView))
        #expect(scrollView.frame.height >= 108)
    }

    @Test @MainActor func lensCustomizationActionIsPinnedToThePanelBottomTrailingCorner() throws {
        let panel = ReadingOverlayPanel()
        let content = OverlayContentState.choosingLens(
            lenses: [.plain, .translation(targetLanguage: "English")],
            usesPaperContext: false
        )
        let size = content.preferredPanelSize(selectionPreviewIsVisible: true)
        let panelFrame = CGRect(origin: CGPoint(x: 100, y: 100), size: size)
        panel.update(
            content,
            selectionPreviewText: "Synthetic selection.",
            frame: panelFrame,
            onQuestionSubmitted: { _ in }
        )
        panel.contentView?.layoutSubtreeIfNeeded()

        let contentView = try #require(panel.contentView)
        let image = try #require(
            contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds)
        )
        contentView.cacheDisplay(in: contentView.bounds, to: image)
        let scaleX = CGFloat(image.pixelsWide) / contentView.bounds.width
        let scaleY = CGFloat(image.pixelsHigh) / contentView.bounds.height
        let background = try #require(
            image.colorAt(
                x: image.pixelsWide / 2,
                y: image.pixelsHigh - Int(30 * scaleY)
            )
        )
        let footerVerticalRange =
            (image.pixelsHigh - Int(48 * scaleY))..<(image.pixelsHigh - Int(18 * scaleY))
        var contrastingPixelCount = 0
        for x in Int((size.width - 220) * scaleX)..<Int((size.width - 20) * scaleX) {
            for y in footerVerticalRange {
                guard let color = image.colorAt(x: x, y: y) else { continue }
                let contrast = abs(color.redComponent - background.redComponent)
                    + abs(color.greenComponent - background.greenComponent)
                    + abs(color.blueComponent - background.blueComponent)
                if contrast > 0.3 {
                    contrastingPixelCount += 1
                }
            }
        }

        #expect(contrastingPixelCount > 40)
    }

    @Test func onlyAnswerOverlayContentAllowsTextSelection() {
        #expect(!OverlayContentState.requesting(usesPaperContext: false).allowsTextSelection)
        #expect(OverlayContentState.answer("Explanation.", usesPaperContext: true).allowsTextSelection)
        #expect(!OverlayContentState.failure("Failure.").allowsTextSelection)
    }

    @Test func onlyAnswerOverlayContentOffersAnswerCopying() {
        #expect(!OverlayContentState.requesting(usesPaperContext: false).showsCopyAction)
        #expect(OverlayContentState.answer("Explanation.", usesPaperContext: true).showsCopyAction)
        #expect(!OverlayContentState.failure("Failure.").showsCopyAction)
    }

    @Test func overlayLabelsAuthorizedLocalContextSeparatelyFromSelectionOnly() {
        #expect(
            OverlayContentState.requesting(usesPaperContext: false).contextLabel
                == "Based on the selected passage"
        )
        #expect(
            OverlayContentState.requesting(
                usesPaperContext: false,
                localSourceName: "reading.pdf"
            ).contextLabel == "Based on the selected passage and authorized local context (reading.pdf)"
        )
    }

    @Test func overlayShowsAContextTagOnlyForAnIncludedFileExcerpt() {
        let selectionOnly = OverlayContentState.requesting(usesPaperContext: false)
        let withFileContext = OverlayContentState.requesting(
            usesPaperContext: false,
            localSourceName: "reading.pdf"
        )

        #expect(selectionOnly.contextTagName == nil)
        #expect(withFileContext.contextTagName == "reading.pdf")
        #expect(withFileContext.preferredPanelSize().height > selectionOnly.preferredPanelSize().height)
    }

    @Test func contextTagCopyFeedbackConfirmsThenResets() {
        var feedback = ContextTagCopyFeedback.ready

        #expect(feedback.iconName == "doc.on.doc")
        feedback.markCopied()
        #expect(feedback.iconName == "checkmark")
        feedback.reset()
        #expect(feedback.iconName == "doc.on.doc")
    }

    @Test func overlayShowsTheCurrentModelNameAndLocalSource() {
        let content = OverlayContentState.requesting(
            usesPaperContext: false,
            model: "gemma3:4b"
        )

        #expect(content.modelLabel == "gemma3:4b (local)")
    }

    @Test func selectingAnotherLensKeepsTheCurrentModelNameAndLocalSource() {
        let secondLens = ExplanationLens.custom(displayName: "Synthetic focus", preference: "Synthetic.")
        let content = OverlayContentState.answer(
            "Synthetic answer.",
            lenses: [.plain, secondLens],
            selectedLens: .plain,
            usesPaperContext: false,
            model: "gemma3:4b"
        )

        #expect(
            content.requestingContent(for: secondLens)?.modelLabel
                == "gemma3:4b (local)"
        )
    }

    @Test @MainActor func refreshingOverlayLensesUsesTheCurrentCustomDefinition() {
        let original = ExplanationLens(
            id: "custom-focus",
            displayName: "Focus",
            preference: "Use the original preference.",
            kind: .custom
        )
        let updated = ExplanationLens(
            id: original.id,
            displayName: "Focus",
            preference: "Use the updated preference.",
            kind: .custom
        )
        let content = OverlayContentState.answer(
            "Synthetic answer.",
            lenses: [original],
            selectedLens: original,
            usesPaperContext: false
        )

        let refreshed = content.refreshingLenses([updated])

        #expect(refreshed.lensOptions == [updated])
        #expect(refreshed.selectedLens == updated)
    }

    @Test @MainActor func answerCopyFeedbackReturnsToReadyAfterReset() {
        var feedback = AnswerCopyFeedback.ready

        feedback.markCopied()
        #expect(feedback == .copied)
        #expect(feedback.label == "Copied")

        feedback.reset()
        #expect(feedback == .ready)
        #expect(feedback.label == "Copy")
    }


    @MainActor
    private func firstAnswerScrollView(in view: NSView?) -> AnswerTextScrollView? {
        guard let view else { return nil }
        if let answer = view as? AnswerTextScrollView { return answer }
        for subview in view.subviews {
            if let answer = firstAnswerScrollView(in: subview) { return answer }
        }
        return nil
    }
}
