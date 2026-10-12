import Carbon
import Combine
import Foundation

@MainActor
final class ShortcutStore: ObservableObject {
    static let defaultsKey = "triggerShortcut"

    enum UpdateFailure: Equatable {
        case invalidCombination
        case systemConflict
        // macOS 15.0 / 15.1 silently drop Option+Shift-only global hotkeys in
        // sandboxed apps; saving one would look accepted but never fire. Fixed
        // in 15.2. See Apple Developer Forums thread 763878.
        case sequoiaOptionShiftBug
    }

    struct ConflictWarning: Equatable {
        let owner: String
        let source: Source

        enum Source: Equatable {
            case system
            case mainMenu
        }
    }

    @Published private(set) var currentShortcut: KeyboardShortcut
    @Published private(set) var lastFailure: UpdateFailure?
    @Published private(set) var lastWarning: [ConflictWarning] = []

    private let defaults: UserDefaults
    private var apply: ((KeyboardShortcut) -> Bool)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let dict = defaults.dictionary(forKey: Self.defaultsKey),
           let saved = KeyboardShortcut(dictionaryRepresentation: dict),
           saved.isValid {
            currentShortcut = saved
        } else {
            currentShortcut = .commandD
        }
    }

    // Register the sink that owns the live monitor; called once at startup.
    // Returning false here means the persisted shortcut couldn't be registered —
    // we fall back to the default and re-apply so the app is always usable.
    func bind(apply: @escaping (KeyboardShortcut) -> Bool) {
        self.apply = apply
        let brokenOnThisOS = isBrokenOnCurrentSystem(currentShortcut)
        if (brokenOnThisOS || !apply(currentShortcut)) && currentShortcut != .commandD {
            currentShortcut = .commandD
            _ = apply(.commandD)
            defaults.removeObject(forKey: Self.defaultsKey)
        }
        lastWarning = warnings(for: currentShortcut)
    }

    @discardableResult
    func attemptUpdate(to shortcut: KeyboardShortcut) -> Bool {
        guard shortcut.isValid else {
            lastFailure = .invalidCombination
            return false
        }
        if isBrokenOnCurrentSystem(shortcut) {
            lastFailure = .sequoiaOptionShiftBug
            return false
        }
        guard let apply else {
            lastFailure = .systemConflict
            return false
        }
        guard apply(shortcut) else {
            lastFailure = .systemConflict
            _ = apply(currentShortcut)
            return false
        }
        currentShortcut = shortcut
        defaults.set(shortcut.dictionaryRepresentation, forKey: Self.defaultsKey)
        lastFailure = nil
        lastWarning = warnings(for: shortcut)
        return true
    }

    func resetToDefault() {
        _ = attemptUpdate(to: .commandD)
    }

    func reportInvalidAttempt() {
        lastFailure = .invalidCombination
    }

    func clearLastFailure() {
        lastFailure = nil
    }

    private func warnings(for shortcut: KeyboardShortcut) -> [ConflictWarning] {
        var out: [ConflictWarning] = []
        for entry in SystemHotKeyProbe.enabledSystemHotKeys()
        where entry.keyCode == shortcut.keyCode && entry.carbonModifiers == shortcut.carbonModifiers {
            out.append(ConflictWarning(
                owner: SystemHotKeyProbe.humanName(for: entry.symbolicID),
                source: .system
            ))
        }
        if let hit = MainMenuHotKeyProbe.match(shortcut, in: MainMenuHotKeyProbe.menuItems()) {
            out.append(ConflictWarning(owner: hit.menuPath, source: .mainMenu))
        }
        return out
    }

    private func isBrokenOnCurrentSystem(_ shortcut: KeyboardShortcut) -> Bool {
        let mods = shortcut.carbonModifiers
        let optionShiftOnly =
            (mods & UInt32(optionKey)) != 0 &&
            (mods & UInt32(shiftKey))  != 0 &&
            (mods & UInt32(cmdKey | controlKey)) == 0
        guard optionShiftOnly else { return false }
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.majorVersion == 15 && (v.minorVersion == 0 || v.minorVersion == 1)
    }
}
