import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum UniversalSelectionCaptureStage: Equatable {
    case accessibility
    case menuBarCopy
    case syntheticCopy
    case noSelection
    case secureField
}

struct UniversalSelectionCaptureResult: Equatable {
    let text: String
    let stage: UniversalSelectionCaptureStage
    let hostBundleIdentifier: String?
}

enum UniversalSelectionPreCopyDecision: Equatable {
    case secureField
    case accessibility(String)
    case copyFallbacks
}

enum UniversalSelectionCapture {
    /// Captures the current selection from the frontmost app. Empty text is
    /// a legal result (the user pressed the hotkey with no selection). Only
    /// returns `nil` when Accessibility permission is missing.
    @MainActor
    static func capture() -> UniversalSelectionCaptureResult? {
        guard AXIsProcessTrusted() else { return nil }
        let application = NSWorkspace.shared.frontmostApplication
        let bundleIdentifier = application?.bundleIdentifier

        switch preCopyDecision(
            focusedElementIsSecure: focusedElementIsSecureField(),
            accessibilityText: captureViaAccessibility(),
            secureEventInputEnabled: IsSecureEventInputEnabled()
        ) {
        case .secureField:
            return UniversalSelectionCaptureResult(
                text: "",
                stage: .secureField,
                hostBundleIdentifier: bundleIdentifier
            )
        case .accessibility(let text):
            return UniversalSelectionCaptureResult(
                text: text,
                stage: .accessibility,
                hostBundleIdentifier: bundleIdentifier
            )
        case .copyFallbacks:
            break
        }
        if let application, let text = captureViaMenuBarCopy(application: application), !text.isEmpty {
            return UniversalSelectionCaptureResult(
                text: text,
                stage: .menuBarCopy,
                hostBundleIdentifier: bundleIdentifier
            )
        }
        if let text = captureViaSyntheticCopy(), !text.isEmpty {
            return UniversalSelectionCaptureResult(
                text: text,
                stage: .syntheticCopy,
                hostBundleIdentifier: bundleIdentifier
            )
        }
        return UniversalSelectionCaptureResult(
            text: "",
            stage: .noSelection,
            hostBundleIdentifier: bundleIdentifier
        )
    }

    // MARK: - Stage 1: Accessibility

    // Password fields must never be read, including through the Copy fallbacks.
    static func isSecureTextFieldSubrole(_ subrole: String?) -> Bool {
        subrole == "AXSecureTextField"
    }

    static func preCopyDecision(
        focusedElementIsSecure: Bool,
        accessibilityText: @autoclosure () -> String?,
        secureEventInputEnabled: @autoclosure () -> Bool
    ) -> UniversalSelectionPreCopyDecision {
        guard !focusedElementIsSecure else { return .secureField }
        if let text = accessibilityText(), !text.isEmpty {
            return .accessibility(text)
        }
        // Web password fields may not expose the secure subrole, but they turn on secure event input.
        // Only the Copy fallbacks are blocked, so Accessibility reads keep working.
        guard !secureEventInputEnabled() else { return .secureField }
        return .copyFallbacks
    }

    static func focusedElementIsSecureField() -> Bool {
        guard let element = focusedElement() else { return false }
        var subrole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSubroleAttribute as CFString,
            &subrole
        ) == .success else {
            return false
        }
        return isSecureTextFieldSubrole(subrole as? String)
    }

    private static func focusedElement() -> AXUIElement? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(application.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return nil
        }
        return (focused as! AXUIElement)
    }

    static func captureViaAccessibility() -> String? {
        guard let element = focusedElement() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as? String
    }

    // MARK: - Stage 2: Menu bar Copy

    static func captureViaMenuBarCopy(application: NSRunningApplication) -> String? {
        let axApp = AXUIElementCreateApplication(application.processIdentifier)
        var menuBar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp,
            kAXMenuBarAttribute as CFString,
            &menuBar
        ) == .success, let menuBar, CFGetTypeID(menuBar) == AXUIElementGetTypeID() else {
            return nil
        }
        guard let copyItem = findCopyMenuItem(under: menuBar as! AXUIElement) else {
            return nil
        }
        return performCopyAndReadPasteboard {
            AXUIElementPerformAction(copyItem, kAXPressAction as CFString) == .success
        }
    }

    /// Recursively walks the menu tree looking for the item whose command
    /// character is "c" with only the command modifier (no shift/option/etc.)
    /// and which is currently enabled. Locale-agnostic — the display title
    /// doesn't need to be "Copy".
    static func findCopyMenuItem(under element: AXUIElement) -> AXUIElement? {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenRef
        ) == .success, let childrenRef, CFGetTypeID(childrenRef) == CFArrayGetTypeID() else {
            return nil
        }
        let children = childrenRef as! [AXUIElement]
        for child in children {
            if isCopyMenuItem(child) {
                return child
            }
            if let nested = findCopyMenuItem(under: child) {
                return nested
            }
        }
        return nil
    }

    private static func isCopyMenuItem(_ element: AXUIElement) -> Bool {
        var charRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXMenuItemCmdCharAttribute as CFString,
            &charRef
        ) == .success, let char = charRef as? String,
              char.lowercased() == "c" else {
            return false
        }
        var modifiersRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXMenuItemCmdModifiersAttribute as CFString,
            &modifiersRef
        ) == .success, let modifiers = modifiersRef as? Int,
              // 0 = command-only (kAXMenuItemModifierNone). Anything else
              // (shift/option/control/no-command) is a different shortcut.
              modifiers == 0 else {
            return false
        }
        var enabledRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXEnabledAttribute as CFString,
            &enabledRef
        ) == .success, let enabled = enabledRef as? Bool, !enabled {
            return false
        }
        return true
    }

    // MARK: - Stage 3: Synthetic ⌘C

    static func captureViaSyntheticCopy() -> String? {
        performCopyAndReadPasteboard {
            postSyntheticCommandC()
        }
    }

    private static func postSyntheticCommandC() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return false
        }
        let keyC = CGKeyCode(kVK_ANSI_C)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyC, keyDown: false) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    // MARK: - Document title

    /// Reads the frontmost window title of an application via AX. Cheap
    /// enough to run after every capture for hosts whose window title is a
    /// meaningful document identifier (e.g. Zotero's PDF reader).
    static func focusedWindowTitle(of application: NSRunningApplication) -> String? {
        let axApp = AXUIElementCreateApplication(application.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            axApp,
            kAXFocusedWindowAttribute as CFString,
            &windowRef
        ) == .success, let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() else {
            return nil
        }
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            windowRef as! AXUIElement,
            kAXTitleAttribute as CFString,
            &titleRef
        ) == .success, let title = titleRef as? String else {
            return nil
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Shared clipboard dance

    private static func performCopyAndReadPasteboard(
        trigger: () -> Bool
    ) -> String? {
        let pasteboard = NSPasteboard.general
        let backup = PasteboardBackup.snapshot(pasteboard)
        defer { backup.restore(to: pasteboard) }

        guard trigger() else { return nil }
        guard PasteboardChangePoller.waitForChange(
            from: backup.changeCount,
            pasteboard: pasteboard
        ) else {
            return nil
        }
        return pasteboard.string(forType: .string)
    }
}
