import Carbon
import Foundation

// Enumerates the macOS system-registered ("symbolic") hotkeys currently enabled
// in System Settings, so the shortcut recorder can warn when the user picks one.
//
// Reads live state via CopySymbolicHotKeys — the same API MASShortcut and
// sindresorhus/KeyboardShortcuts use. Not a hardcoded table: if the user has
// disabled Spotlight's ⌘Space, we won't flag it.
enum SystemHotKeyProbe {
    struct Entry: Equatable {
        let keyCode: UInt32
        let carbonModifiers: UInt32
        let symbolicID: Int
    }

    static func enabledSystemHotKeys() -> [Entry] {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr,
              let list = unmanaged?.takeRetainedValue() as? [[String: Any]]
        else { return [] }

        return list.compactMap { dict in
            guard
                let enabled = dict[kHISymbolicHotKeyEnabled as String] as? Bool, enabled,
                let code = dict[kHISymbolicHotKeyCode as String] as? Int,
                let mods = dict[kHISymbolicHotKeyModifiers as String] as? Int,
                code >= 0, mods >= 0
            else { return nil }
            let id = (dict["symbolicHotKey"] as? Int) ?? -1
            return Entry(
                keyCode: UInt32(code),
                carbonModifiers: UInt32(mods),
                symbolicID: id
            )
        }
    }

    // Symbolic-ID → human name. The IDs are stable but undocumented; values here
    // come from long-standing community consensus (MASShortcut, HotkeyClash).
    // Unknown IDs fall back to a generic label rather than a wrong one.
    static func humanName(for symbolicID: Int) -> String {
        switch symbolicID {
        case 7:   return "Move focus to menu bar"
        case 8:   return "Move focus to Dock"
        case 9:   return "Move focus to active window"
        case 10:  return "Move focus to window toolbar"
        case 11:  return "Move focus to floating window"
        case 13:  return "Cycle through windows"
        case 27:  return "Save picture of screen as file"
        case 28:  return "Copy picture of screen to clipboard"
        case 29:  return "Save picture of selection as file"
        case 30:  return "Copy picture of selection to clipboard"
        case 32, 79: return "Mission Control"
        case 33, 80: return "Application windows"
        case 36:  return "Show Desktop"
        case 51:  return "Look up in Dictionary"
        case 60, 64: return "Spotlight"
        case 61, 65: return "Finder search"
        case 118: return "Switch to Desktop 1"
        case 119: return "Switch to Desktop 2"
        case 120: return "Switch to Desktop 3"
        case 121: return "Switch to Desktop 4"
        case 122: return "Switch to Desktop 5"
        case 159: return "Launchpad"
        case 163: return "Screenshot toolbar"
        case 175: return "Notification Center"
        default:  return "a macOS system shortcut"
        }
    }
}
