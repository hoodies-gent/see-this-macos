import Carbon

final class GlobalHotKeyMonitor {
    static let hotKeyIdentifier = HotKeyIdentifier(signature: OSType(0x5A484350), id: 1)

    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var onHotKey: (() -> Void)?
    private var currentShortcut: KeyboardShortcut?

    @discardableResult
    func start(shortcut: KeyboardShortcut, onHotKey: @escaping () -> Void) -> Bool {
        self.onHotKey = onHotKey
        guard eventHandler == nil else {
            return update(shortcut: shortcut)
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            globalHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard handlerStatus == noErr else { return false }

        return registerShortcut(shortcut)
    }

    @discardableResult
    func update(shortcut: KeyboardShortcut) -> Bool {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        currentShortcut = nil
        return registerShortcut(shortcut)
    }

    private func registerShortcut(_ shortcut: KeyboardShortcut) -> Bool {
        var newHotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            Self.hotKeyIdentifier.carbonValue,
            GetEventDispatcherTarget(),
            0,
            &newHotKey
        )
        guard status == noErr, let newHotKey else { return false }
        hotKey = newHotKey
        currentShortcut = shortcut
        return true
    }

    deinit {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    fileprivate func handleHotKey() {
        Task { @MainActor [weak self] in
            self?.onHotKey?()
        }
    }
}

private func globalHotKeyHandler(
    _: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard
        let event,
        let userData,
        let hotKeyIdentifier = eventHotKeyIdentifier(from: event)
    else {
        return OSStatus(eventNotHandledErr)
    }
    let monitor = Unmanaged<GlobalHotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
    guard GlobalHotKeyMonitor.hotKeyIdentifier.eventHandlingStatus(for: hotKeyIdentifier) == noErr else {
        return OSStatus(eventNotHandledErr)
    }
    monitor.handleHotKey()
    return noErr
}
