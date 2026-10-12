import AppKit
import Carbon

// Walks NSApp.mainMenu to collect the shortcut equivalents this app itself
// defines, so the recorder can warn when the user picks something that would
// steal a menu command (⌘Q, ⌘W, etc). Matches the character+modifier approach
// MASShortcut and sindresorhus/KeyboardShortcuts use — comparing by rendered
// character rather than by virtual keyCode makes non-QWERTY layouts work.
enum MainMenuHotKeyProbe {
    struct Entry: Equatable {
        let character: String                 // canonical lowercase, e.g. "q"
        let modifiers: NSEvent.ModifierFlags  // deviceIndependent, shift-normalized
        let menuPath: String                  // "File → Close Window"
    }

    @MainActor
    static func menuItems() -> [Entry] {
        guard let menu = NSApp.mainMenu else { return [] }
        var out: [Entry] = []
        collect(menu, path: [], into: &out)
        return out
    }

    static func match(_ shortcut: KeyboardShortcut, in entries: [Entry]) -> Entry? {
        guard let character = characterFromKeyCode(shortcut.keyCode)?.lowercased() else { return nil }
        let mods = appKitModifiers(from: shortcut.carbonModifiers)
        return entries.first { $0.character == character && $0.modifiers == mods }
    }

    @MainActor
    private static func collect(_ menu: NSMenu, path: [String], into out: inout [Entry]) {
        for item in menu.items {
            if let submenu = item.submenu {
                collect(submenu, path: path + [item.title], into: &out)
            }
            guard !item.keyEquivalent.isEmpty else { continue }
            let (char, mods) = canonicalize(item.keyEquivalent, mask: item.keyEquivalentModifierMask)
            out.append(Entry(
                character: char,
                modifiers: mods,
                menuPath: (path + [item.title]).joined(separator: " → ")
            ))
        }
    }

    // NSMenuItem represents shift as an uppercase equivalent, not as an explicit
    // shift bit. Fold that back into the modifier set so comparisons are uniform.
    private static func canonicalize(_ raw: String, mask: NSEvent.ModifierFlags) -> (String, NSEvent.ModifierFlags) {
        let mods = mask.intersection(.deviceIndependentFlagsMask)
        if raw.count == 1, let ch = raw.first, ch.isLetter, ch.isUppercase {
            return (String(ch).lowercased(), mods.union(.shift))
        }
        return (raw.lowercased(), mods)
    }

    private static func appKitModifiers(from carbon: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbon & UInt32(cmdKey)     != 0 { flags.insert(.command) }
        if carbon & UInt32(optionKey)  != 0 { flags.insert(.option) }
        if carbon & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbon & UInt32(shiftKey)   != 0 { flags.insert(.shift) }
        return flags
    }

    // Duplicated from KeyboardShortcut's private helper on purpose: keeps this
    // step's diff to a single new file instead of widening an existing type's API.
    private static func characterFromKeyCode(_ keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let dataRef = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue()
        guard let layoutBytes = CFDataGetBytePtr(dataRef) else { return nil }
        return layoutBytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { keyboardLayout in
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                keyboardLayout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }
}
