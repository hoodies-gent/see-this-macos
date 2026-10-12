import Carbon

final class TemporaryEscapeHotKeyMonitor {
    static let hotKeyIdentifier = HotKeyIdentifier(signature: OSType(0x45534350), id: 1)

    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var onEscape: (() -> Void)?

    @discardableResult
    func start(onEscape: @escaping () -> Void) -> Bool {
        self.onEscape = onEscape
        guard hotKey == nil else { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            temporaryEscapeHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard handlerStatus == noErr else {
            self.onEscape = nil
            return false
        }

        let registrationStatus = RegisterEventHotKey(
            UInt32(kVK_Escape),
            0,
            Self.hotKeyIdentifier.carbonValue,
            GetEventDispatcherTarget(),
            0,
            &hotKey
        )
        guard registrationStatus == noErr else {
            stop()
            return false
        }

        return true
    }

    func stop() {
        onEscape = nil
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    deinit {
        stop()
    }

    fileprivate func handleEscape() {
        Task { @MainActor [weak self] in
            self?.onEscape?()
        }
    }
}

private func temporaryEscapeHotKeyHandler(
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
    let monitor = Unmanaged<TemporaryEscapeHotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
    guard TemporaryEscapeHotKeyMonitor.hotKeyIdentifier.eventHandlingStatus(for: hotKeyIdentifier) == noErr else {
        return OSStatus(eventNotHandledErr)
    }
    monitor.handleEscape()
    return noErr
}
