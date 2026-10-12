import Carbon

struct KeyboardShortcut: Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32

    static let commandD = KeyboardShortcut(
        keyCode: UInt32(kVK_ANSI_D),
        carbonModifiers: UInt32(cmdKey)
    )

    var isValid: Bool {
        (carbonModifiers & UInt32(cmdKey | controlKey | optionKey)) != 0
    }

    var display: String {
        displayParts.joined()
    }

    var displayParts: [String] {
        var parts: [String] = []
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if carbonModifiers & UInt32(optionKey)  != 0 { parts.append("⌥") }
        if carbonModifiers & UInt32(shiftKey)   != 0 { parts.append("⇧") }
        if carbonModifiers & UInt32(cmdKey)     != 0 { parts.append("⌘") }
        parts.append(Self.keyName(for: keyCode))
        return parts
    }
}

// MARK: - UserDefaults coding

extension KeyboardShortcut {
    private enum CodingKey {
        static let keyCode = "keyCode"
        static let modifiers = "modifiers"
    }

    var dictionaryRepresentation: [String: Any] {
        [CodingKey.keyCode: Int(keyCode), CodingKey.modifiers: Int(carbonModifiers)]
    }

    init?(dictionaryRepresentation dict: [String: Any]) {
        guard
            let key = dict[CodingKey.keyCode] as? Int,
            let mods = dict[CodingKey.modifiers] as? Int,
            key >= 0, mods >= 0
        else { return nil }
        self.init(keyCode: UInt32(key), carbonModifiers: UInt32(mods))
    }
}

// MARK: - Key names

private extension KeyboardShortcut {
    static func keyName(for keyCode: UInt32) -> String {
        if let named = namedKey(for: keyCode) { return named }
        return characterFromKeyCode(keyCode) ?? "Key \(keyCode)"
    }

    static func namedKey(for keyCode: UInt32) -> String? {
        switch Int(keyCode) {
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return nil
        }
    }

    // Ask the current keyboard layout what character this key produces without modifiers.
    static func characterFromKeyCode(_ keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let dataRef = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue()
        let layoutBytes = CFDataGetBytePtr(dataRef)
        return layoutBytes.flatMap { bytes in
            bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { keyboardLayout in
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
                return String(utf16CodeUnits: chars, count: length).uppercased()
            }
        }
    }
}
