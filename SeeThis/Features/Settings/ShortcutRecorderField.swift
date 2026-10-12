import AppKit
import Carbon
import Combine
import SwiftUI

struct ShortcutRecorderField: View {
    let current: KeyboardShortcut
    var onCommit: (KeyboardShortcut) -> Void
    var onInvalid: () -> Void

    @StateObject private var recorder = ShortcutRecorder()

    var body: some View {
        Button {
            if recorder.isRecording {
                recorder.endRecording()
            } else {
                recorder.beginRecording(onCommit: onCommit, onInvalid: onInvalid)
            }
        } label: {
            Text(recorder.isRecording ? "Type shortcut…" : current.display)
                .font(.body.monospaced())
                .frame(minWidth: 90, alignment: .center)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(recorder.isRecording
                              ? Color.accentColor.opacity(0.12)
                              : Color.secondary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(recorder.isRecording ? Color.accentColor : Color.secondary.opacity(0.35),
                                lineWidth: recorder.isRecording ? 1.5 : 1)
                )
        }
        .buttonStyle(.plain)
        .help(recorder.isRecording ? "Press Escape to cancel" : "Click to record a new shortcut")
        .onDisappear { recorder.endRecording() }
    }
}

@MainActor
private final class ShortcutRecorder: ObservableObject {
    @Published var isRecording = false
    private var monitor: Any?

    func beginRecording(
        onCommit: @escaping (KeyboardShortcut) -> Void,
        onInvalid: @escaping () -> Void
    ) {
        guard !isRecording else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleEvent(event, onCommit: onCommit, onInvalid: onInvalid)
        }
    }

    func endRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handleEvent(
        _ event: NSEvent,
        onCommit: (KeyboardShortcut) -> Void,
        onInvalid: () -> Void
    ) -> NSEvent? {
        // Standalone modifier taps don't finish a recording.
        guard event.type == .keyDown else { return nil }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Escape without modifiers cancels.
        if event.keyCode == UInt16(kVK_Escape),
           mods.intersection([.command, .control, .option]).isEmpty {
            endRecording()
            return nil
        }

        let shortcut = KeyboardShortcut(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: Self.carbonModifiers(from: mods)
        )
        if shortcut.isValid {
            endRecording()
            onCommit(shortcut)
        } else {
            onInvalid()
        }
        return nil
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option)  { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift)   { result |= UInt32(shiftKey) }
        return result
    }
}
