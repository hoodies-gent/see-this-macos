import AppKit
import SwiftUI

struct FirstRunGuideView: View {
    @ObservedObject var diagnostics: HostContextDiagnostics
    @ObservedObject var shortcutStore: ShortcutStore
    @ObservedObject var firstRunGuide: FirstRunGuideState
    let onOpenModels: () -> Void
    @State private var demoCursorPosition = FirstRunDemoContent.previewCursorPosition
    @State private var showsCommittedDemoCursor = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Step \(firstRunGuide.step.rawValue + 1) of \(FirstRunGuideStep.allCases.count)")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    ProgressView(
                        value: Double(firstRunGuide.step.rawValue + 1),
                        total: Double(FirstRunGuideStep.allCases.count)
                    )
                    .frame(width: 120)
                }

                cardContent
                    .frame(maxWidth: .infinity, minHeight: 240, maxHeight: 240, alignment: .topLeading)

                VStack(spacing: 8) {
                    HStack {
                        Spacer()
                        continuePrompt
                    }
                    .frame(height: 34)
                    .opacity(showsContinuePrompt ? 1 : 0)
                    .accessibilityHidden(!showsContinuePrompt)

                    Divider()

                    HStack {
                        if firstRunGuide.canGoBack {
                            Button("Back") {
                                firstRunGuide.goBack()
                            }
                            .hoverHighlight()
                        }
                        if firstRunGuide.canDismiss {
                            Button("Exit Tutorial") {
                                firstRunGuide.dismiss()
                            }
                            .hoverHighlight()
                        }
                        Spacer()
                        Button(primaryButtonTitle) {
                            if firstRunGuide.step == .demo {
                                firstRunGuide.finish()
                            } else {
                                firstRunGuide.advance()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .hoverHighlight()
                        .disabled(!canContinue)
                        .breathingAction(emphasisTarget == .continueButton)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        } label: {
            Text(guideTitle)
                .font(.title3.weight(.semibold))
        }
        .onAppear {
            diagnostics.setTutorialDemoActive(firstRunGuide.step == .demo)
            diagnostics.setTutorialLensHint(false)
            if case .notChecked = diagnostics.ollamaConnectionStatus {
                diagnostics.checkOllamaConnection()
            }
        }
        .onDisappear {
            diagnostics.setTutorialDemoActive(false)
            diagnostics.setTutorialLensHint(false)
        }
        .onChange(of: firstRunGuide.step) { _, step in
            diagnostics.setTutorialDemoActive(step == .demo)
        }
        .task(id: shouldRefreshAccessibilityPermission) {
            guard shouldRefreshAccessibilityPermission else { return }

            while !Task.isCancelled {
                diagnostics.refreshAccessibilityPermission()
                guard shouldRefreshAccessibilityPermission else { return }

                do {
                    try await Task.sleep(nanoseconds: 500_000_000)
                } catch {
                    return
                }
            }
        }
        .onChange(of: diagnostics.isAccessibilityTrusted) { wasTrusted, isTrusted in
            guard FirstRunGuideActionGuidance.shouldBringSettingsForward(
                step: firstRunGuide.step,
                wasAccessibilityTrusted: wasTrusted,
                isAccessibilityTrusted: isTrusted
            ) else { return }
            SettingsNavigation.requestSettingsWindow()
        }
        .onChange(of: diagnostics.captureRevision) { _, _ in
            guard firstRunGuide.step == .demo,
                  firstRunGuide.demoPhase == .pressShortcut,
                  diagnostics.lastCaptureHasSelection,
                  diagnostics.lastCaptureHostBundleIdentifier == Bundle.main.bundleIdentifier else {
                return
            }
            firstRunGuide.demoShortcutTriggered()
            diagnostics.setTutorialLensHint(true)
        }
        .onChange(of: diagnostics.lensSelectionRevision) { _, _ in
            guard firstRunGuide.step == .demo,
                  firstRunGuide.demoPhase == .chooseLens else {
                return
            }
            firstRunGuide.demoLensSelected()
            diagnostics.setTutorialLensHint(false)
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        switch firstRunGuide.step {
        case .welcome:
            welcomeCard
        case .accessibility:
            onboardingCard(
                icon: "hand.raised.fill",
                title: "Allow Accessibility"
            ) {
                Text("This permission lets \(AppIdentity.displayName) read only the text you select. It never captures your screen.")
                    .foregroundStyle(.secondary)
                if diagnostics.isAccessibilityTrusted {
                    Label("Permission granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    HStack(spacing: 10) {
                        Button("Open Accessibility Settings…") {
                            diagnostics.requestAccessibilityPermission()
                        }
                        .hoverHighlight()
                        .breathingAction(emphasisTarget == .accessibilitySettings)
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.left")
                            Text("Press to allow access")
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        case .ollama:
            onboardingCard(
                icon: "cpu",
                title: "Connect the local model"
            ) {
                ollamaStatus
            }
        case .demo:
            if firstRunGuide.isShowingCompletion {
                completionCard
            } else {
                onboardingCard(
                    icon: "sparkles",
                    title: "Try it now"
                ) {
                    DemoCoachCard(
                        phase: firstRunGuide.demoPhase,
                        shortcut: shortcutStore.currentShortcut,
                        lensName: ExplanationLens.tutorialDemo.displayName
                    )
                    demoTextCanvas
                    .frame(height: 50)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25))
                    )
                }
            }
        }
    }

    private var shouldRefreshAccessibilityPermission: Bool {
        FirstRunGuideActionGuidance.shouldRefreshAccessibilityPermission(
            step: firstRunGuide.step,
            accessibilityTrusted: diagnostics.isAccessibilityTrusted
        )
    }

    @ViewBuilder
    private var ollamaStatus: some View {
        switch diagnostics.ollamaConnectionStatus {
        case .notChecked, .checking:
            ProgressView("Checking local Ollama…")
        case .notInstalled:
            Text("Ollama isn't installed yet. Install it to keep explanations private and local.")
                .foregroundStyle(.secondary)
            Button("Download Ollama…") {
                diagnostics.openOllamaDownloadPage()
            }
            .hoverHighlight()
            .breathingAction(emphasisTarget == .ollamaAction)
        case .notRunning:
            Text("Ollama is installed but isn't running.")
                .foregroundStyle(.secondary)
            Button("Start Ollama") {
                diagnostics.startOllama()
            }
            .hoverHighlight()
            .breathingAction(emphasisTarget == .ollamaAction)
        case .starting:
            ProgressView("Starting Ollama…")
        case .noModels:
            Text("Ollama is running, but no model is installed.")
                .foregroundStyle(.secondary)
            Button("Choose a model") {
                onOpenModels()
            }
            .hoverHighlight()
            .breathingAction(emphasisTarget == .ollamaAction)
        case .available:
            Label("Ollama and a model are ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    private var canContinue: Bool {
        switch firstRunGuide.step {
        case .welcome:
            return true
        case .demo:
            return firstRunGuide.canFinishDemo
        case .accessibility:
            return diagnostics.isAccessibilityTrusted
        case .ollama:
            if case .available = diagnostics.ollamaConnectionStatus {
                return true
            }
            return false
        }
    }

    private var showsContinuePrompt: Bool {
        switch firstRunGuide.step {
        case .welcome:
            true
        case .accessibility, .ollama:
            canContinue
        case .demo:
            firstRunGuide.canFinishDemo
        }
    }

    private var emphasisTarget: FirstRunGuideEmphasisTarget {
        FirstRunGuideActionGuidance.emphasisTarget(
            step: firstRunGuide.step,
            canContinue: canContinue,
            accessibilityTrusted: diagnostics.isAccessibilityTrusted,
            reduceMotion: reduceMotion,
            ollamaStatus: diagnostics.ollamaConnectionStatus
        )
    }

    private var continuePrompt: some View {
        VStack(spacing: 1) {
            Text(firstRunGuide.isShowingCompletion ? "Press to finish" : "Press to continue")
            Image(systemName: "arrow.down")
                .font(.caption.weight(.semibold))
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            firstRunGuide.isShowingCompletion
                ? "Press Done to finish"
                : "Press \(primaryButtonTitle) to continue"
        )
    }

    @ViewBuilder
    private var demoTextCanvas: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 60.0,
                paused: !FirstRunDemoAnimation.repeats(reduceMotion: reduceMotion)
            )
        ) { context in
            demoTextCanvasContent(
                previewProgress: firstRunGuide.demoPhase == .selectText
                    ? FirstRunDemoAnimation.progress(
                        at: context.date,
                        reduceMotion: reduceMotion
                    )
                    : 0,
                showsCursor: firstRunGuide.demoPhase == .selectText || showsCommittedDemoCursor
            )
        }
    }

    private func demoTextCanvasContent(previewProgress: CGFloat, showsCursor: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            FirstRunDemoText(
                isPreviewing: firstRunGuide.demoPhase == .selectText,
                previewProgress: previewProgress,
                onSelectionChanged: { hasSelection, cursorPosition in
                    demoCursorPosition = cursorPosition
                    showsCommittedDemoCursor = hasSelection
                    firstRunGuide.demoTextSelectionChanged(hasSelection)
                }
            )
            if showsCursor {
                DemoCursor(
                    position: firstRunGuide.demoPhase == .selectText
                        ? CGPoint(
                            x: FirstRunDemoContent.textInset + FirstRunDemoContent.textWidth * previewProgress,
                            y: FirstRunDemoContent.previewCursorPosition.y
                        )
                        : demoCursorPosition
                )
            }
        }
    }

    private var primaryButtonTitle: String {
        if firstRunGuide.isShowingCompletion {
            return "Done"
        }
        guard firstRunGuide.step == .demo else { return "Continue" }
        return firstRunGuide.presentation == .gettingStarted
            ? "Finish setup"
            : "Finish Tutorial"
    }

    private var guideTitle: String {
        firstRunGuide.presentation == .gettingStarted ? "Getting Started" : "Tutorial"
    }

    private var completionCard: some View {
        onboardingCard(
            icon: "checkmark.circle.fill",
            title: "You're now all set!",
            iconColor: .green
        ) {
            HStack(spacing: 6) {
                Text("Select text anywhere, then press")
                ShortcutKeycaps(
                    shortcut: shortcutStore.currentShortcut,
                    isActive: false
                )
                Text("to open \(AppIdentity.displayName).")
            }
            .font(.body)

            Text("You can change your model and lenses anytime in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(AppIdentity.displayName)
                        .font(.title2.weight(.semibold))
                    Text("v\(AppIdentity.releaseVersion)")
                        .foregroundStyle(.secondary)
                }
            }
            Text("Let's get started")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 9) {
                Text("What's next")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                welcomeSetupRow(
                    icon: "hand.raised",
                    title: "Allow text selection",
                    detail: "Grant Accessibility permission"
                )
                welcomeSetupRow(
                    icon: "cpu",
                    title: "Connect a local model",
                    detail: "Use Ollama for explanations"
                )
                welcomeSetupRow(
                    icon: "sparkles",
                    title: "Try an explanation",
                    detail: "See SeeThis in action"
                )
            }
        }
    }

    private func welcomeSetupRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .frame(width: 16)
            Text(title)
                .font(.body.weight(.medium))
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func onboardingCard<Content: View>(
        icon: String,
        title: String,
        iconColor: Color = .accentColor,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(iconColor)
            Text(title)
                .font(.title2.weight(.semibold))
            content()
        }
    }
}

private struct BreathingActionModifier: ViewModifier {
    let isActive: Bool
    @State private var startDate = Date()

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { context in
            let elapsed = isActive ? context.date.timeIntervalSince(startDate) : 0
            let intensity = BreathingActionAnimation.intensity(elapsed: elapsed)
            content
                .scaleEffect(1 + 0.04 * intensity)
                .shadow(
                    color: Color.accentColor.opacity(0.38 * intensity),
                    radius: 10 * intensity
                )
        }
        .onAppear {
            startDate = Date()
        }
        .onChange(of: isActive) { _, active in
            if active {
                startDate = Date()
            }
        }
    }
}

private extension View {
    func breathingAction(_ isActive: Bool) -> some View {
        modifier(BreathingActionModifier(isActive: isActive))
    }
}

private struct FirstRunDemoText: NSViewRepresentable {
    let isPreviewing: Bool
    let previewProgress: CGFloat
    let onSelectionChanged: (Bool, CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectionChanged: onSelectionChanged)
    }

    func makeNSView(context: Context) -> FirstRunDemoTextView {
        let textView = FirstRunDemoTextView()
        textView.string = FirstRunDemoContent.sample
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: FirstRunDemoContent.textInset, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.isPreviewing = isPreviewing
        textView.previewProgress = previewProgress
        return textView
    }

    func updateNSView(_ textView: FirstRunDemoTextView, context: Context) {
        if textView.string != FirstRunDemoContent.sample {
            textView.string = FirstRunDemoContent.sample
        }
        textView.isPreviewing = isPreviewing
        textView.previewProgress = previewProgress
        if isPreviewing && textView.selectedRange().length == 0 {
            textView.resetSelectionInteraction()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let onSelectionChanged: (Bool, CGPoint) -> Void

        init(onSelectionChanged: @escaping (Bool, CGPoint) -> Void) {
            self.onSelectionChanged = onSelectionChanged
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let selection = textView.selectedRange()
            onSelectionChanged(selection.length > 0, cursorPosition(for: selection, in: textView))
        }

        private func cursorPosition(for selection: NSRange, in textView: NSTextView) -> CGPoint {
            let string = textView.string as NSString
            let end = min(max(selection.location + selection.length, 0), string.length)
            let prefix = string.substring(with: NSRange(location: 0, length: end)) as NSString
            let font = textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let x = FirstRunDemoContent.textInset + prefix.size(withAttributes: [.font: font]).width
            return CGPoint(x: x, y: FirstRunDemoContent.previewCursorPosition.y)
        }
    }
}

private final class FirstRunDemoTextView: NSTextView {
    var isPreviewing = false {
        didSet { needsDisplay = true }
    }
    private var isSelecting = false
    var previewProgress: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        isSelecting = true
        needsDisplay = true
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        isSelecting = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if isPreviewing && !isSelecting {
            drawPreviewHighlight()
        }
        super.draw(dirtyRect)
    }

    func resetSelectionInteraction() {
        isSelecting = false
        needsDisplay = true
    }

    private func drawPreviewHighlight() {
        guard let textContainer, let layoutManager else { return }
        let length = Int((CGFloat(string.utf16.count) * previewProgress).rounded())
        guard length > 0 else { return }
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: 0, length: length),
            actualCharacterRange: nil
        )
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        rect.origin.y = lineRect.origin.y + textContainerOrigin.y
        rect.size.height = lineRect.height
        NSColor.controlAccentColor.withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
    }

}

private enum FirstRunDemoContent {
    static let sample = "More context helps the model make better decisions."
    static let textInset: CGFloat = 10
    static let textWidth = (sample as NSString).size(
        withAttributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]
    ).width
    static let previewCursorPosition = CGPoint(x: textInset, y: 18)
}

private struct DemoCursor: View {
    let position: CGPoint

    var body: some View {
        Image(systemName: "cursorarrow")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .position(x: position.x + 8, y: position.y + 9)
            .allowsHitTesting(false)
    }
}

private struct DemoCoachCard: View {
    let phase: FirstRunGuideDemoPhase
    let shortcut: KeyboardShortcut
    let lensName: String
    @State private var isPulsing = false
    @State private var handOffset: CGFloat = -4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: iconName)
                        .foregroundStyle(Color.accentColor)
                        .scaleEffect(isPulsing ? 1.08 : 1)
                        .offset(x: phase == .selectText ? handOffset : 0)
                    Text(title)
                        .font(.body.weight(.semibold))
                }
                cardContent
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
            }
            Image(systemName: "arrowtriangle.down.fill")
                .font(.caption2)
                .foregroundStyle(Color(nsColor: .controlBackgroundColor))
                .offset(y: -1)
        }
        .frame(maxWidth: 360, alignment: .leading)
        .id(phase)
        .onAppear {
            updateAnimation()
        }
        .onChange(of: reduceMotion) { _, _ in
            updateAnimation()
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        switch phase {
        case .selectText:
            Text("Drag across the sentence below to select it.")
                .font(.body)
                .foregroundStyle(.secondary)
        case .pressShortcut:
            HStack(spacing: 6) {
                Text("Press")
                ShortcutKeycaps(
                    shortcut: shortcut,
                    isActive: phase == .pressShortcut
                )
                Text("to open the overlay.")
            }
            .font(.body)
            .foregroundStyle(.secondary)
        case .chooseLens:
            Text("The overlay is open. Click a lens such as “\(lensName)”.")
                .font(.body)
                .foregroundStyle(.secondary)
        case .complete:
            VStack(alignment: .leading, spacing: 6) {
                Label("Lens selected. You can finish now.", systemImage: "checkmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.green)
                Text("Customize lenses anytime in Settings → Lenses.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var title: String {
        switch phase {
        case .selectText: "Select text"
        case .pressShortcut: "Open the overlay"
        case .chooseLens: "Try a lens"
        case .complete: "Demo complete"
        }
    }

    private var iconName: String {
        switch phase {
        case .selectText: "hand.draw.fill"
        case .pressShortcut: "keyboard"
        case .chooseLens: "cursorarrow.click"
        case .complete: "checkmark.circle.fill"
        }
    }

    private func updateAnimation() {
        guard FirstRunDemoAnimation.repeats(reduceMotion: reduceMotion) else {
            withAnimation(nil) {
                isPulsing = false
                handOffset = 0
            }
            return
        }

        withAnimation(nil) {
            isPulsing = false
            handOffset = -4
        }
        withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
            isPulsing = true
            handOffset = 4
        }
    }

}

private struct ShortcutKeycaps: View {
    let shortcut: KeyboardShortcut
    let isActive: Bool
    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(shortcut.displayParts.enumerated()), id: \.offset) { _, part in
                Keycap(part, isHighlighted: isPulsing)
            }
        }
        .onAppear { updatePulse() }
        .onChange(of: isActive) { _, _ in
            updatePulse()
        }
        .onChange(of: reduceMotion) { _, _ in
            updatePulse()
        }
    }

    private func updatePulse() {
        guard isActive, FirstRunDemoAnimation.repeats(reduceMotion: reduceMotion) else {
            withAnimation(nil) {
                isPulsing = false
            }
            return
        }
        withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }
}
