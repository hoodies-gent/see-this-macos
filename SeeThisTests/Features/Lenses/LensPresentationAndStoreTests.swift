import CoreGraphics
import Carbon
import Foundation
import ApplicationServices
import AppKit
import SwiftUI
import Testing
@testable import SeeThis


private let syntheticSecondLens = ExplanationLens.custom(
    displayName: "Synthetic focus",
    preference: "Synthetic."
)

struct LensPresentationAndStoreTests {

    @Test @MainActor func explanationLensesHaveFixedNamesAndControlledInstructions() {
        #expect(ExplanationLens.allCases == [.plain])
        #expect(ExplanationLens.localTranslateID == "translate-local")
        #expect(ExplanationLens.localTranslateCatalogEntry.displayName == "Translate")
        #expect(
            ExplanationLens.localTranslateCatalogEntry.preference
                .contains(ExplanationLens.targetLanguageVariable)
        )
        #expect(ExplanationLens.plain.displayName == "Explain")
        #expect(!ExplanationLens.plain.preference.lowercased().contains("paper"))
    }

    @Test @MainActor func lensEditorAddsTheTargetLanguageVariableWithoutDuplicatingIt() {
        let variable = ExplanationLens.targetLanguageVariable

        #expect(LensEditorDraft.insertingTargetLanguageVariable(into: "") == variable)
        #expect(
            LensEditorDraft.insertingTargetLanguageVariable(into: "Translate carefully.")
                == "Translate carefully. \(variable)"
        )
        #expect(
            LensEditorDraft.insertingTargetLanguageVariable(into: "Use \(variable).")
                == "Use \(variable)."
        )
    }

    @Test @MainActor func freshStoreRegistersLocalAndDeepLLensesButKeepsDeepLHidden() {
        let suiteName = "LensStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LensStore(defaults: defaults)

        #expect(store.orderedLensIDs == ["plain", "translate-local", "translate"])
        #expect(store.inlineLensIDs == ["plain", "translate-local"])
        #expect(store.defaultLensID == nil)
        #expect(store.customLenses.isEmpty)
    }

    @Test @MainActor func everyLensProvidesAReaderVisibleInstruction() {
        let customLens = ExplanationLens.custom(
            displayName: "Synthetic focus",
            preference: "Use a synthetic presentation preference."
        )

        for lens in ExplanationLens.allCases + [customLens] {
            #expect(lens.readerVisibleInstruction == lens.preference)
        }
    }

    @Test @MainActor func lensEditorDraftStartsEmptyOrPreloadsTheLensBeingEdited() {
        let lens = ExplanationLens.custom(
            displayName: "Synthetic focus",
            preference: "Use a synthetic presentation preference."
        )

        #expect(LensEditorDraft().displayName.isEmpty)
        #expect(LensEditorDraft().preference.isEmpty)
        #expect(LensEditorDraft().lensID == nil)
        #expect(LensEditorDraft(lens: lens).lensID == lens.id)
        #expect(LensEditorDraft(lens: lens).displayName == lens.displayName)
        #expect(LensEditorDraft(lens: lens).preference == lens.preference)
    }

    @Test @MainActor func lensEditorClampsHalfWidthNamesAtTheWeightLimit() {
        #expect(LensEditorDraft.maximumDisplayNameWeight == 30)

        let overflow = String(repeating: "a", count: LensEditorDraft.maximumDisplayNameWeight + 5)
        #expect(LensEditorDraft.clampDisplayName(overflow).count == LensEditorDraft.maximumDisplayNameWeight)

        let boundary = String(repeating: "b", count: LensEditorDraft.maximumDisplayNameWeight)
        #expect(LensEditorDraft.clampDisplayName(boundary) == boundary)
    }

    @Test @MainActor func lensEditorCountsFullWidthCharactersAsTwoWeightUnits() {
        #expect(LensEditorDraft.displayNameWeight("你好") == 4)
        #expect(LensEditorDraft.displayNameWeight("abc") == 3)
        #expect(LensEditorDraft.displayNameWeight("A中B") == 4)

        // 30 CJK characters would exceed the 30-unit cap; only the first 15 survive.
        let overflowCJK = String(repeating: "字", count: 30)
        let clampedCJK = LensEditorDraft.clampDisplayName(overflowCJK)
        #expect(clampedCJK.count == 15)
        #expect(LensEditorDraft.displayNameWeight(clampedCJK) == 30)
    }

    @Test @MainActor func lensEditorClampAvoidsSplittingWideCharactersAcrossTheCap() {
        // 29 ASCII + 1 CJK = 31 weighted units; the CJK char must drop, leaving 29 ASCII.
        let asciiRun = String(repeating: "x", count: 29)
        let mixed = asciiRun + "字"
        let clamped = LensEditorDraft.clampDisplayName(mixed)
        #expect(clamped == asciiRun)
        #expect(LensEditorDraft.displayNameWeight(clamped) == 29)
    }

    @Test @MainActor func lensEditorReportsWhenTheDisplayNameExceedsTheLimit() {
        var draft = LensEditorDraft()
        draft.displayName = String(repeating: "a", count: LensEditorDraft.maximumDisplayNameWeight + 1)
        #expect(!draft.displayNameIsWithinLimit)
    }

    @Test @MainActor func lensNamesRejectTrimmedExactDuplicatesButAllowDifferentCasing() {
        let suiteName = "LensStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LensStore(defaults: defaults)
        let lens = store.addCustomLens(
            displayName: "Synthetic focus",
            preference: "Use a synthetic presentation preference."
        )

        #expect(!store.isLensNameAvailable(" Synthetic focus "))
        #expect(store.isLensNameAvailable("synthetic focus"))
        #expect(!store.isLensNameAvailable("Explain"))
        #expect(store.isLensNameAvailable("Synthetic focus", excludingID: lens.id))
    }

    @Test @MainActor func builtInLensInstructionsDoNotUseClassificationPrefixes() {
        for lens in ExplanationLens.allCases {
            #expect(!lens.preference.hasPrefix("Use the "))
            #expect(!lens.preference.contains(" explanation lens:"))
        }
    }

    @Test @MainActor func lensStorePersistsCustomLensesAndDefaultSelection() {
        let suiteName = "LensStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LensStore(defaults: defaults)
        let customLens = store.addCustomLens(
            displayName: "Synthetic focus",
            preference: "Use a synthetic presentation preference."
        )
        #expect(store.setInlineLens(id: customLens.id, isEnabled: true))
        store.setDefaultLens(id: customLens.id)

        let restored = LensStore(defaults: defaults)
        #expect(restored.customLenses == [customLens])
        #expect(restored.inlineLenses.contains(customLens))
        #expect(restored.defaultLens == customLens)
    }

    @Test @MainActor func lensStorePersistsTheSelectedOllamaModel() {
        let suiteName = "OllamaSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LensStore(defaults: defaults)
        store.setSelectedOllamaModel("qwen3:4b")

        #expect(LensStore(defaults: defaults).selectedOllamaModel == "qwen3:4b")
    }

    @Test @MainActor func lensStoreLetsTheUserChooseUpToSixInlineLensesAndNoDefault() {
        let suiteName = "LensStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LensStore(defaults: defaults)
        let customLenses = (1...5).map { index in
            store.addCustomLens(
                displayName: "Synthetic \(index)",
                preference: "Use synthetic preference \(index)."
            )
        }

        for lens in customLenses.prefix(4) {
            #expect(store.setInlineLens(id: lens.id, isEnabled: true))
        }
        #expect(!store.setInlineLens(id: customLenses[4].id, isEnabled: true))
        #expect(!store.setInlineLens(id: TranslateSettingsStore.actionID, isEnabled: true))
        store.setDefaultLens(id: nil)

        #expect(store.inlineLensIDs.count == 6)
        #expect(store.defaultLensID == nil)
    }

    @Test @MainActor func lensStoreKeepsAtLeastOneInlineLensAvailable() {
        let suiteName = "LensStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LensStore(defaults: defaults)
        let customLens = store.addCustomLens(
            displayName: "Synthetic focus",
            preference: "Use a synthetic presentation preference."
        )
        #expect(store.setInlineLens(id: customLens.id, isEnabled: true))
        #expect(store.setInlineLens(id: customLens.id, isEnabled: false))
        #expect(store.setInlineLens(id: ExplanationLens.localTranslateID, isEnabled: false))

        #expect(!store.setInlineLens(id: ExplanationLens.plain.id, isEnabled: false))
        #expect(store.inlineLenses == [.plain])
    }

    @Test @MainActor func lensStoreDeletesBuiltInLensesAndPersistsThatChoice() {
        let suiteName = "LensStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LensStore(defaults: defaults)
        store.addCustomLens(
            displayName: "Synthetic focus",
            preference: "Use a synthetic presentation preference."
        )
        #expect(store.removeLens(id: ExplanationLens.plain.id))

        #expect(!store.lenses.contains(ExplanationLens.plain))
        #expect(!store.inlineLenses.contains(ExplanationLens.plain))

        let restored = LensStore(defaults: defaults)
        #expect(!restored.lenses.contains(ExplanationLens.plain))
    }

    @Test @MainActor func lensStoreKeepsOneInlineLensWhenDeletingTheCurrentOne() {
        let suiteName = "LensStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LensStore(defaults: defaults)
        let customLens = store.addCustomLens(
            displayName: "Synthetic focus",
            preference: "Use a synthetic presentation preference."
        )

        #expect(store.removeLens(id: ExplanationLens.plain.id))
        #expect(store.inlineLensIDs == [ExplanationLens.localTranslateID])
        #expect(!store.removeLens(id: customLens.id))
    }

    @Test @MainActor func lensStoreLetsTheUserReorderLensesAndPersistsThatChoice() {
        let suiteName = "LensStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LensStore(defaults: defaults)
        let customLens = store.addCustomLens(
            displayName: "Synthetic focus",
            preference: "Use a synthetic presentation preference."
        )
        #expect(store.lenses.map(\.id) == ExplanationLens.allCases.map(\.id) + [customLens.id])

        #expect(store.setInlineLens(id: customLens.id, isEnabled: true))
        store.moveLens(id: customLens.id, toIndex: 0)
        #expect(store.lenses.first?.id == customLens.id)
        #expect(store.inlineLenses.first?.id == customLens.id)

        let restored = LensStore(defaults: defaults)
        #expect(restored.lenses.map(\.id).first == customLens.id)
    }

    @Test @MainActor func deepLPreviewOrderPersistsAcrossStoreReloads() {
        let suiteName = "LensStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LensStore(defaults: defaults)
        #expect(store.setInlineLens(id: TranslateSettingsStore.actionID, isEnabled: true))

        store.moveLens(id: TranslateSettingsStore.actionID, toIndex: 0)

        let restored = LensStore(defaults: defaults)
        #expect(restored.orderedLensIDs.first == TranslateSettingsStore.actionID)
        #expect(restored.inlineLensIDs.contains(TranslateSettingsStore.actionID))
    }

    @Test @MainActor func lensStoreOrderingSurvivesDeletionAndBuiltInRestore() {
        let suiteName = "LensStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LensStore(defaults: defaults)
        let customLens = store.addCustomLens(
            displayName: "Synthetic focus",
            preference: "Use a synthetic presentation preference."
        )
        store.moveLens(id: customLens.id, toIndex: 0)
        let orderAfterMove = store.lenses.map(\.id)
        #expect(orderAfterMove.first == customLens.id)

        _ = store.removeLens(id: ExplanationLens.plain.id)
        #expect(!store.lenses.contains(ExplanationLens.plain))
        #expect(store.lenses.first?.id == customLens.id)

        store.restoreBuiltInLenses()
        #expect(store.lenses.contains(ExplanationLens.plain))
        #expect(store.lenses.first?.id == customLens.id)

        _ = store.removeLens(id: customLens.id)
        #expect(!store.lenses.contains(customLens))
    }

    @Test @MainActor func lensStoreAppendsUnknownIdsFromLegacyStorageInDefaultOrder() throws {
        let suiteName = "LensStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyPayload: [String: Any] = [
            "customLenses": [],
            "removedBuiltInLensIDs": [],
            "inlineLensIDs": ExplanationLens.allCases.map(\.id),
            "selectedOllamaModel": OllamaProvider.defaultModelName
        ]
        let legacyData = try JSONSerialization.data(withJSONObject: legacyPayload)
        defaults.set(legacyData, forKey: "explanationLensSettings")

        let store = LensStore(defaults: defaults)
        #expect(store.orderedLensIDs == ["plain", "translate-local", "translate"])
        #expect(store.inlineLensIDs == ["plain", "translate-local"])
    }

    @Test @MainActor func migrationAddsLocalTranslateWithoutEvictingExplicitLegacyChoices() throws {
        let suiteName = "LensStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyPayload: [String: Any] = [
            "customLenses": [],
            "removedBuiltInLensIDs": [],
            "inlineLensIDs": ["plain"],
            "selectedOllamaModel": OllamaProvider.defaultModelName,
            "lensOrder": ["plain"]
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: legacyPayload),
            forKey: "explanationLensSettings"
        )

        let store = LensStore(defaults: defaults)

        #expect(store.orderedLensIDs == ["plain", "translate-local", "translate"])
        #expect(store.inlineLensIDs == ["plain", "translate-local"])
    }

    @Test @MainActor func migrationPreservesSixExplicitPromptLensesBeforeLocalTranslate() throws {
        let suiteName = "LensStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let customIDs = (1...5).map { "legacy-custom-\($0)" }
        let customLenses: [[String: Any]] = customIDs.enumerated().map { index, id in
            [
                "id": id,
                "displayName": "Legacy \(index + 1)",
                "preference": "Legacy prompt \(index + 1).",
                "kind": "custom"
            ]
        }
        let explicitIDs = ["plain"] + customIDs
        let legacyPayload: [String: Any] = [
            "customLenses": customLenses,
            "removedBuiltInLensIDs": [],
            "inlineLensIDs": explicitIDs,
            "selectedOllamaModel": OllamaProvider.defaultModelName,
            "lensOrder": explicitIDs
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: legacyPayload),
            forKey: "explanationLensSettings"
        )

        let store = LensStore(defaults: defaults)

        #expect(store.inlineLensIDs == explicitIDs)
        #expect(store.orderedLensIDs.contains(ExplanationLens.localTranslateID))
        #expect(!store.inlineLensIDs.contains(ExplanationLens.localTranslateID))
        #expect(store.orderedLensIDs.contains(TranslateSettingsStore.actionID))
        #expect(!store.inlineLensIDs.contains(TranslateSettingsStore.actionID))
    }

    @Test @MainActor func lensStoreDropsRetiredBuiltInIdsFromEveryStoredList() throws {
        let suiteName = "LensStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let retiredPayload: [String: Any] = [
            "customLenses": [],
            "removedBuiltInLensIDs": ["argument-role", "define-terms"],
            "inlineLensIDs": ["uncertainty-focus", "define-terms", "plain"],
            "defaultLensID": "argument-role",
            "selectedOllamaModel": OllamaProvider.defaultModelName,
            "lensOrder": ["uncertainty-focus", "argument-role", "define-terms", "plain"]
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: retiredPayload),
            forKey: "explanationLensSettings"
        )

        let store = LensStore(defaults: defaults)

        #expect(store.lenses.map(\.id) == ["plain"])
        #expect(store.inlineLenses.map(\.id) == ["plain"])
        #expect(store.defaultLens == nil)
        #expect(store.removedBuiltInLensIDs.isEmpty)
    }

    @Test @MainActor func lensStoreFallsBackWhenEveryStoredInlineLensWasRetired() throws {
        let suiteName = "LensStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let retiredPayload: [String: Any] = [
            "customLenses": [],
            "removedBuiltInLensIDs": [],
            "inlineLensIDs": ["argument-role", "uncertainty-focus"],
            "selectedOllamaModel": OllamaProvider.defaultModelName,
            "lensOrder": ["argument-role", "uncertainty-focus", "plain", "define-terms"]
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: retiredPayload),
            forKey: "explanationLensSettings"
        )

        let store = LensStore(defaults: defaults)

        #expect(store.inlineLenses.map(\.id) == ["plain"])
    }

    @Test @MainActor func lensStoreRestoresRemovedBuiltInPresetsWithoutChangingInlineChoices() {
        let suiteName = "LensStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LensStore(defaults: defaults)
        store.addCustomLens(
            displayName: "Synthetic focus",
            preference: "Use a synthetic presentation preference."
        )
        #expect(store.removeLens(id: ExplanationLens.plain.id))
        let inlineBeforeRestore = store.inlineLenses

        store.restoreBuiltInLenses()

        #expect(store.lenses.contains(ExplanationLens.plain))
        #expect(store.inlineLenses == inlineBeforeRestore)
    }

    @Test @MainActor func requestAndAnswerKeepAllLensesVisible() {
        let customLens = ExplanationLens.custom(
            displayName: "Synthetic focus",
            preference: "Use a synthetic presentation preference."
        )
        let requesting = OverlayContentState.requesting(
            lenses: ExplanationLens.allCases + [customLens],
            selectedLens: customLens,
            usesPaperContext: false
        )
        let answer = OverlayContentState.answer(
            "Synthetic answer.",
            lenses: ExplanationLens.allCases + [customLens],
            selectedLens: customLens,
            usesPaperContext: false
        )

        #expect(requesting.lensOptions == ExplanationLens.allCases + [customLens])
        #expect(answer.lensOptions == ExplanationLens.allCases + [customLens])
        #expect(requesting.selectedLens == customLens)
        #expect(answer.selectedLens == customLens)
    }

    @Test @MainActor func selectingAnotherLensRestartsTheSameOverlayRequest() {
        let requesting = OverlayContentState.answer(
            "Synthetic answer.",
            lenses: [.plain, syntheticSecondLens],
            selectedLens: .plain,
            usesPaperContext: false,
            localSourceName: "Synthetic source"
        )

        let restarted = requesting.requestingContent(for: syntheticSecondLens)

        #expect(restarted?.isRequesting == true)
        #expect(restarted?.selectedLens == syntheticSecondLens)
        #expect(restarted?.contextLabel == requesting.contextLabel)
    }

    @Test func lensSelectionReusesAnActiveSelectionCapturedFromThisApp() {
        #expect(
            LensSelectionCapturePolicy.shouldReuseActiveSnapshot(
                activeHostBundleIdentifier: AppIdentity.bundleIdentifier,
                frontmostBundleIdentifier: AppIdentity.bundleIdentifier,
                appBundleIdentifier: AppIdentity.bundleIdentifier
            )
        )
    }

    @Test func lensSelectionStillRecapturesFromTheSameExternalApp() {
        #expect(
            !LensSelectionCapturePolicy.shouldReuseActiveSnapshot(
                activeHostBundleIdentifier: "com.example.reader",
                frontmostBundleIdentifier: "com.example.reader",
                appBundleIdentifier: AppIdentity.bundleIdentifier
            )
        )
    }

    @Test @MainActor func defaultInlineLensesArrangeAsASingleHorizontalRow() {
        let requesting = OverlayContentState.requesting(
            lenses: ExplanationLens.allCases,
            selectedLens: .plain,
            usesPaperContext: false
        )

        #expect(requesting.lensActionLayout == .horizontalSingleRow)
    }

    @Test @MainActor func tutorialLensHintTargetsTheFirstUnselectedLens() {
        let content = OverlayContentState.answer(
            "Synthetic answer.",
            lenses: [.plain, syntheticSecondLens],
            selectedLens: .plain,
            usesPaperContext: false
        )

        #expect(content.tutorialLensHintTarget == syntheticSecondLens)
    }

    @Test @MainActor func extraInlineLensesWrapAcrossMultipleRows() {
        let manyLenses = ExplanationLens.allCases + [
            .custom(displayName: "Synthetic focus one", preference: "Synthetic."),
            .custom(displayName: "Synthetic focus two", preference: "Synthetic."),
            .custom(displayName: "Synthetic focus three", preference: "Synthetic."),
            .custom(displayName: "Synthetic focus four", preference: "Synthetic."),
            .custom(displayName: "Synthetic focus five", preference: "Synthetic.")
        ]
        let requesting = OverlayContentState.requesting(
            lenses: manyLenses,
            selectedLens: .plain,
            usesPaperContext: false
        )

        #expect(requesting.lensActionLayout == .horizontalWrapped)
    }

    @Test @MainActor func lensLayoutPlannerFallsBackToVerticalWhenNoButtonFits() {
        let plan = OverlayLensListLayout.plan(
            buttonLabels: [String(repeating: "long lens label", count: 4)],
            availableWidth: 40
        )
        #expect(plan.layout == .verticalFullWidth)
    }

    @Test @MainActor func lensLayoutPlannerCapsVerticalHeightAtScrollLimit() {
        let manyLabels = (0..<20).map { "Synthetic label \($0)" }
        let plan = OverlayLensListLayout.plan(
            buttonLabels: manyLabels,
            availableWidth: 10
        )
        #expect(plan.layout == .verticalFullWidth)
        #expect(plan.sectionHeight == OverlayLensListLayout.maximumStackHeight)
    }

    @Test @MainActor func lensLayoutWrappedRowCountGrowsAsWidthShrinks() {
        let widths: [CGFloat] = [100, 100, 100, 100, 100, 100]
        // 6 buttons of width 100 with 5 gaps of 6pt = 630pt for one row.
        let wide = OverlayLensListLayout.wrappedRowCount(widths: widths, availableWidth: 640)
        let narrow = OverlayLensListLayout.wrappedRowCount(widths: widths, availableWidth: 260)
        #expect(wide == 1)
        #expect(narrow == 3)
    }

    @Test @MainActor func lensStatusNamesTheSelectedLensDuringAndAfterARequest() {
        let requesting = OverlayContentState.requesting(
            lenses: [.plain, syntheticSecondLens],
            selectedLens: syntheticSecondLens,
            usesPaperContext: false
        )
        let answer = OverlayContentState.answer(
            "Synthetic answer.",
            lenses: [.plain, syntheticSecondLens],
            selectedLens: syntheticSecondLens,
            usesPaperContext: false
        )

        #expect(requesting.lensStatusText == "Explaining with: Synthetic focus")
        #expect(answer.lensStatusText == "Explained with: Synthetic focus")
    }

    @Test @MainActor func overlayHeightGrowsToFitEveryInlineLens() {
        let fourLenses = OverlayContentState.requesting(
            lenses: ExplanationLens.allCases + [
                .custom(displayName: "Synthetic 1", preference: "Synthetic."),
                .custom(displayName: "Synthetic 2", preference: "Synthetic."),
                .custom(displayName: "Synthetic 3", preference: "Synthetic.")
            ],
            selectedLens: .plain,
            usesPaperContext: false
        )
        let sixLenses = OverlayContentState.requesting(
            lenses: ExplanationLens.allCases + [
                .custom(displayName: "Synthetic 1", preference: "Synthetic."),
                .custom(displayName: "Synthetic 2", preference: "Synthetic."),
                .custom(displayName: "Synthetic 3", preference: "Synthetic."),
                .custom(displayName: "Synthetic 4", preference: "Synthetic."),
                .custom(displayName: "Synthetic 5", preference: "Synthetic.")
            ],
            selectedLens: .plain,
            usesPaperContext: false
        )

        #expect(sixLenses.preferredPanelSize().height > fourLenses.preferredPanelSize().height)
    }

}
