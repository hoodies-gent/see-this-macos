import Combine
import CoreGraphics
import Foundation

enum FirstRunGuideStep: Int, CaseIterable {
    case welcome
    case accessibility
    case ollama
    case demo
}

enum FirstRunGuidePresentation {
    case gettingStarted
    case tutorial
}

enum FirstRunGuideDemoPhase: Equatable {
    case selectText
    case pressShortcut
    case chooseLens
    case complete
}

enum FirstRunGuideEmphasisTarget: Equatable {
    case none
    case continueButton
    case accessibilitySettings
    case ollamaAction
}

enum FirstRunGuideActionGuidance {
    static func shouldRefreshAccessibilityPermission(
        step: FirstRunGuideStep,
        accessibilityTrusted: Bool
    ) -> Bool {
        step == .accessibility && !accessibilityTrusted
    }

    static func shouldBringSettingsForward(
        step: FirstRunGuideStep,
        wasAccessibilityTrusted: Bool,
        isAccessibilityTrusted: Bool
    ) -> Bool {
        step == .accessibility && !wasAccessibilityTrusted && isAccessibilityTrusted
    }

    static func emphasisTarget(
        step: FirstRunGuideStep,
        canContinue: Bool,
        accessibilityTrusted: Bool,
        reduceMotion: Bool,
        ollamaStatus: OllamaConnectionStatus = .notChecked
    ) -> FirstRunGuideEmphasisTarget {
        guard !reduceMotion else { return .none }
        if canContinue {
            return .continueButton
        }
        if step == .accessibility, !accessibilityTrusted {
            return .accessibilitySettings
        }
        if step == .ollama {
            switch ollamaStatus {
            case .notInstalled, .notRunning, .noModels:
                return .ollamaAction
            case .notChecked, .checking, .starting, .available:
                return .none
            }
        }
        return .none
    }
}

enum BreathingActionAnimation {
    static let cycleDuration: TimeInterval = 2.8

    static func intensity(elapsed: TimeInterval) -> Double {
        guard elapsed > 0 else { return 0 }
        let cyclePosition = elapsed.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
        return (1 - cos(cyclePosition * 2 * .pi)) / 2
    }
}

enum FirstRunDemoAnimation {
    static func repeats(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    static func progress(at date: Date, reduceMotion: Bool) -> CGFloat {
        guard repeats(reduceMotion: reduceMotion) else { return 1 }
        let cycle = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4.5)
        return cycle < 2.8 ? CGFloat(cycle / 2.8) : (cycle < 3.8 ? 1 : 0)
    }
}

@MainActor
final class FirstRunGuideState: ObservableObject {
    @Published private(set) var presentation: FirstRunGuidePresentation?
    @Published private(set) var step: FirstRunGuideStep = .welcome
    @Published private(set) var demoPhase: FirstRunGuideDemoPhase = .selectText
    @Published private(set) var hasCompleted: Bool

    private static let completionKey = "firstRunGuideCompleted"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasCompleted = defaults.bool(forKey: Self.completionKey)
        presentation = nil
    }

    var isPresented: Bool {
        presentation != nil
    }

    func present(_ presentation: FirstRunGuidePresentation) {
        step = .welcome
        demoPhase = .selectText
        self.presentation = presentation
    }

    func finish() {
        markCompleted()
        presentation = nil
    }

    var canDismiss: Bool {
        presentation == .tutorial
    }

    func dismiss() {
        guard canDismiss else { return }
        presentation = nil
    }

    private func markCompleted() {
        defaults.set(true, forKey: Self.completionKey)
        hasCompleted = true
    }

    var canGoBack: Bool {
        step != .welcome
    }

    func advance() {
        guard let next = FirstRunGuideStep(rawValue: step.rawValue + 1) else { return }
        step = next
        if next == .demo {
            demoPhase = .selectText
        }
    }

    func goBack() {
        guard let previous = FirstRunGuideStep(rawValue: step.rawValue - 1) else { return }
        step = previous
        if step == .demo {
            demoPhase = .selectText
        }
    }

    var canFinishDemo: Bool {
        step == .demo && demoPhase == .complete
    }

    var isShowingCompletion: Bool {
        canFinishDemo
    }

    func demoTextSelectionChanged(_ hasSelection: Bool) {
        guard step == .demo else { return }
        if hasSelection, demoPhase == .selectText {
            demoPhase = .pressShortcut
        } else if !hasSelection, demoPhase == .pressShortcut {
            demoPhase = .selectText
        }
    }

    func demoShortcutTriggered() {
        guard step == .demo, demoPhase == .pressShortcut else { return }
        demoPhase = .chooseLens
    }

    func demoLensSelected() {
        guard step == .demo, demoPhase == .chooseLens else { return }
        demoPhase = .complete
    }

}
