import CoreGraphics
import Carbon
import Foundation
import ApplicationServices
import AppKit
import SwiftUI
import Testing
@testable import SeeThis


struct FirstRunGuideStateTests {

    @Test @MainActor func disabledContinueButtonIsNotEmphasized() {
        let target = FirstRunGuideActionGuidance.emphasisTarget(
            step: .demo,
            canContinue: false,
            accessibilityTrusted: true,
            reduceMotion: false
        )

        #expect(target == .none)
    }

    @Test @MainActor func accessibilitySettingsIsEmphasizedUntilPermissionIsGranted() {
        let pendingTarget = FirstRunGuideActionGuidance.emphasisTarget(
            step: .accessibility,
            canContinue: false,
            accessibilityTrusted: false,
            reduceMotion: false
        )
        let grantedTarget = FirstRunGuideActionGuidance.emphasisTarget(
            step: .accessibility,
            canContinue: true,
            accessibilityTrusted: true,
            reduceMotion: false
        )

        #expect(pendingTarget == .accessibilitySettings)
        #expect(grantedTarget == .continueButton)
    }

    @Test @MainActor func ollamaActionEmphasisMatchesTheConnectionState() {
        let installation = OllamaInstallation.cli(URL(fileURLWithPath: "/usr/local/bin/ollama"))
        let actionableStatuses: [OllamaConnectionStatus] = [
            .notInstalled,
            .notRunning(installation),
            .noModels
        ]
        let passiveStatuses: [OllamaConnectionStatus] = [
            .notChecked,
            .checking,
            .starting
        ]

        for status in actionableStatuses {
            let target = FirstRunGuideActionGuidance.emphasisTarget(
                step: .ollama,
                canContinue: false,
                accessibilityTrusted: true,
                reduceMotion: false,
                ollamaStatus: status
            )
            #expect(target == .ollamaAction)
        }

        for status in passiveStatuses {
            let target = FirstRunGuideActionGuidance.emphasisTarget(
                step: .ollama,
                canContinue: false,
                accessibilityTrusted: true,
                reduceMotion: false,
                ollamaStatus: status
            )
            #expect(target == .none)
        }

        let readyTarget = FirstRunGuideActionGuidance.emphasisTarget(
            step: .ollama,
            canContinue: true,
            accessibilityTrusted: true,
            reduceMotion: false,
            ollamaStatus: .available([])
        )

        #expect(readyTarget == .continueButton)
    }

    @Test @MainActor func settingsReturnToFrontOnlyWhenAccessibilityBecomesTrusted() {
        #expect(FirstRunGuideActionGuidance.shouldBringSettingsForward(
            step: .accessibility,
            wasAccessibilityTrusted: false,
            isAccessibilityTrusted: true
        ))
        #expect(!FirstRunGuideActionGuidance.shouldBringSettingsForward(
            step: .accessibility,
            wasAccessibilityTrusted: true,
            isAccessibilityTrusted: true
        ))
        #expect(!FirstRunGuideActionGuidance.shouldBringSettingsForward(
            step: .ollama,
            wasAccessibilityTrusted: false,
            isAccessibilityTrusted: true
        ))
    }

    @Test @MainActor func accessibilityPermissionRefreshRunsOnlyWhileAwaitingPermission() {
        #expect(FirstRunGuideActionGuidance.shouldRefreshAccessibilityPermission(
            step: .accessibility,
            accessibilityTrusted: false
        ))
        #expect(!FirstRunGuideActionGuidance.shouldRefreshAccessibilityPermission(
            step: .accessibility,
            accessibilityTrusted: true
        ))
        #expect(!FirstRunGuideActionGuidance.shouldRefreshAccessibilityPermission(
            step: .ollama,
            accessibilityTrusted: false
        ))
    }

    @Test @MainActor func reducedMotionDisablesActionEmphasis() {
        let target = FirstRunGuideActionGuidance.emphasisTarget(
            step: .welcome,
            canContinue: true,
            accessibilityTrusted: false,
            reduceMotion: true
        )

        #expect(target == .none)
    }

    @Test @MainActor func breathingActionCyclesFromRestToPeakAndBack() {
        let rest = BreathingActionAnimation.intensity(elapsed: 0)
        let peak = BreathingActionAnimation.intensity(elapsed: 1.4)
        let returnedToRest = BreathingActionAnimation.intensity(elapsed: 2.8)

        #expect(abs(rest - 0) < 0.0001)
        #expect(abs(peak - 1) < 0.0001)
        #expect(abs(returnedToRest - 0) < 0.0001)
    }

    @Test @MainActor func reducedMotionUsesAStableCompletedDemoPreview() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let midway = Date(timeIntervalSinceReferenceDate: 1.4)

        #expect(!FirstRunDemoAnimation.repeats(reduceMotion: true))
        #expect(FirstRunDemoAnimation.progress(at: start, reduceMotion: true) == 1)
        #expect(FirstRunDemoAnimation.progress(at: midway, reduceMotion: true) == 1)
    }

    @Test @MainActor func standardMotionKeepsTheDemoPreviewAnimated() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let midway = Date(timeIntervalSinceReferenceDate: 1.4)

        #expect(FirstRunDemoAnimation.repeats(reduceMotion: false))
        #expect(FirstRunDemoAnimation.progress(at: start, reduceMotion: false) == 0)
        #expect(FirstRunDemoAnimation.progress(at: midway, reduceMotion: false) == 0.5)
    }

    @Test @MainActor func firstRunGuideStartsHiddenUntilPresented() {
        let suiteName = "FirstRunGuideStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let guide = FirstRunGuideState(defaults: defaults)
        #expect(!guide.isPresented)
        #expect(!guide.hasCompleted)

        guide.present(.tutorial)

        #expect(guide.isPresented)
        #expect(guide.presentation == .tutorial)
        #expect(guide.step == .welcome)
    }

    @Test @MainActor func completingGettingStartedPersistsCompletion() {
        let suiteName = "FirstRunGuideStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let guide = FirstRunGuideState(defaults: defaults)

        guide.present(.gettingStarted)
        guide.finish()

        #expect(!guide.isPresented)
        #expect(guide.hasCompleted)
        #expect(FirstRunGuideState(defaults: defaults).hasCompleted)
    }

    @Test @MainActor func firstRunGuideMovesOneCardAtATime() {
        let suiteName = "FirstRunGuideStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let guide = FirstRunGuideState(defaults: defaults)

        guide.present(.tutorial)
        #expect(guide.step == .welcome)
        #expect(!guide.canGoBack)

        guide.advance()
        #expect(guide.step == .accessibility)
        #expect(guide.canGoBack)

        guide.goBack()
        #expect(guide.step == .welcome)
    }

    @Test @MainActor func exitingTutorialDoesNotCompleteGettingStarted() {
        let suiteName = "FirstRunGuideStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let guide = FirstRunGuideState(defaults: defaults)

        guide.present(.tutorial)
        #expect(guide.canDismiss)
        guide.dismiss()

        #expect(!guide.isPresented)
        #expect(!guide.hasCompleted)
        #expect(!FirstRunGuideState(defaults: defaults).hasCompleted)
    }

    @Test @MainActor func gettingStartedCannotBeDismissedBeforeCompletion() {
        let suiteName = "FirstRunGuideStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let guide = FirstRunGuideState(defaults: defaults)

        guide.present(.gettingStarted)
        #expect(!guide.canDismiss)
        guide.dismiss()

        #expect(guide.isPresented)
        #expect(!guide.hasCompleted)
        #expect(!FirstRunGuideState(defaults: defaults).hasCompleted)
    }

    @Test @MainActor func demoProgressRequiresEachRealInteractionInOrder() {
        let suiteName = "FirstRunGuideStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let guide = FirstRunGuideState(defaults: defaults)

        guide.present(.tutorial)
        guide.advance()
        guide.advance()
        guide.advance()

        #expect(guide.step == .demo)
        #expect(guide.demoPhase == .selectText)
        #expect(!guide.canFinishDemo)
        #expect(!guide.isShowingCompletion)

        guide.demoShortcutTriggered()
        #expect(guide.demoPhase == .selectText)

        guide.demoTextSelectionChanged(true)
        #expect(guide.demoPhase == .pressShortcut)
        #expect(!guide.canFinishDemo)

        guide.demoLensSelected()
        #expect(guide.demoPhase == .pressShortcut)

        guide.demoShortcutTriggered()
        #expect(guide.demoPhase == .chooseLens)
        #expect(!guide.canFinishDemo)

        guide.demoLensSelected()
        #expect(guide.demoPhase == .complete)
        #expect(guide.canFinishDemo)
        #expect(guide.isShowingCompletion)
    }

    @Test @MainActor func deselectingDemoTextReturnsToSelectionPrompt() {
        let suiteName = "FirstRunGuideStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let guide = FirstRunGuideState(defaults: defaults)
        guide.present(.tutorial)
        guide.advance()
        guide.advance()
        guide.advance()

        guide.demoTextSelectionChanged(true)
        #expect(guide.demoPhase == .pressShortcut)

        guide.demoTextSelectionChanged(false)
        #expect(guide.demoPhase == .selectText)
    }

}
