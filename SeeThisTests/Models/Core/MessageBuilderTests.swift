import Foundation
import Testing
@testable import SeeThis

struct MessageBuilderTests {

    @Test func passageModeWithBuiltInLensPutsPreferenceInUserSegment() {
        let messages = buildPassageMessages(
            passage: "Synthetic selection.",
            intent: .lens(.plain)
        )

        #expect(messages.count == 2)
        #expect(messages[0].role == .system)
        #expect(messages[1].role == .user)
        #expect(messages[1].content == ExplanationLens.plain.preference)
    }

    @Test func passageModeWrapsPassageInTag() {
        let messages = buildPassageMessages(
            passage: "Synthetic selection.",
            intent: .lens(.plain)
        )
        #expect(messages[0].content.contains("<passage>\nSynthetic selection.\n</passage>"))
    }

    @Test func passageModeIncludesLanguageRuleInSystemSegment() {
        let messages = buildPassageMessages(
            passage: "Synthetic selection.",
            intent: .lens(.plain)
        )
        #expect(messages[0].content.contains(MessageBuilderCopy.languageRule))
    }

    @Test func passageModeWithCustomLensAppendsSandboxRider() {
        let custom = ExplanationLens.custom(
            displayName: "Synthetic focus",
            preference: "Use a synthetic presentation preference."
        )
        let messages = buildPassageMessages(
            passage: "Synthetic selection.",
            intent: .lens(custom)
        )
        #expect(messages[0].content.contains(MessageBuilderCopy.customLensSandbox))
        #expect(messages[1].content == "Use a synthetic presentation preference.")
    }

    @Test func passageModeWithBuiltInLensOmitsSandboxRider() {
        let messages = buildPassageMessages(
            passage: "Synthetic selection.",
            intent: .lens(.plain)
        )
        #expect(!messages[0].content.contains(MessageBuilderCopy.customLensSandbox))
    }

    @Test func passageModeWithUserQuestionPutsQuestionInUserSegment() {
        let messages = buildPassageMessages(
            passage: "Synthetic selection.",
            intent: .userQuestion("What does this claim actually depend on?")
        )
        #expect(messages[1].content == "What does this claim actually depend on?")
        #expect(!messages[0].content.contains(MessageBuilderCopy.customLensSandbox))
    }

    @Test func passageModeWrapsPaperTitleInTagWhenSupplied() {
        let messages = buildPassageMessages(
            passage: "Synthetic selection.",
            paperTitle: "Synthetic Paper Title",
            intent: .lens(.plain)
        )
        #expect(messages[0].content.contains("<paper_title>\nSynthetic Paper Title\n</paper_title>"))
    }

    @Test func passageModeOmitsPaperTitleTagWhenAbsent() {
        let messages = buildPassageMessages(
            passage: "Synthetic selection.",
            intent: .lens(.plain)
        )
        // Injection defense clause names the tag; the wrapper block only
        // renders when a value is present, so pin the closing tag.
        #expect(!messages[0].content.contains("</paper_title>"))
    }

    @Test func passageModeWrapsLocalContextInTagWhenSupplied() {
        let messages = buildPassageMessages(
            passage: "Synthetic selection.",
            localContext: "Synthetic authorized context.",
            intent: .lens(.plain)
        )
        #expect(messages[0].content.contains("<local_context>\nSynthetic authorized context.\n</local_context>"))
    }

    @Test func passageModeIncludesInjectionDefenseClause() {
        let messages = buildPassageMessages(
            passage: "Synthetic selection.",
            intent: .lens(.plain)
        )
        #expect(messages[0].content.contains(MessageBuilderCopy.injectionDefenseClause))
    }

    @Test func passageModeIncludesNoFollowUpClause() {
        let messages = buildPassageMessages(
            passage: "Synthetic selection.",
            intent: .lens(.plain)
        )
        #expect(messages[0].content.contains(MessageBuilderCopy.noFollowUpClause))
    }

    @Test func freeformModeIncludesNoFollowUpClause() {
        let messages = buildFreeformMessages(userQuestion: "What is a martingale?")
        #expect(messages[0].content.contains(MessageBuilderCopy.noFollowUpClause))
    }

    @Test func freeformModePutsQuestionInUserSegmentWithNoPassage() {
        let messages = buildFreeformMessages(userQuestion: "What is a martingale?")

        #expect(messages.count == 2)
        #expect(messages[0].role == .system)
        #expect(messages[1].role == .user)
        #expect(messages[1].content == "What is a martingale?")
        #expect(!messages[0].content.contains("Passage:"))
    }

    @Test func freeformModeIncludesLanguageRuleAndCompanionFraming() {
        let messages = buildFreeformMessages(userQuestion: "What is a martingale?")
        #expect(messages[0].content.contains(MessageBuilderCopy.languageRule))
        #expect(messages[0].content.contains(MessageBuilderCopy.readingCompanionFraming))
    }
}
