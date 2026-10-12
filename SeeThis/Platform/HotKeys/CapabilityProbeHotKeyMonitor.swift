#if DEBUG
import Carbon

final class CapabilityProbeHotKeyMonitor {
    static let shortcutDisplay = "⌘⇧P"
    static let shortcutKeyCode = UInt32(kVK_ANSI_P)
    static let shortcutModifiers = UInt32(cmdKey | shiftKey)
    static let hotKeyIdentifier = HotKeyIdentifier(signature: OSType(0x5A505250), id: 1)

    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var onHotKey: (() -> Void)?

    func start(onHotKey: @escaping () -> Void) {
        self.onHotKey = onHotKey
        guard hotKey == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            capabilityProbeHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard handlerStatus == noErr else { return }

        let status = RegisterEventHotKey(
            Self.shortcutKeyCode,
            Self.shortcutModifiers,
            Self.hotKeyIdentifier.carbonValue,
            GetEventDispatcherTarget(),
            0,
            &hotKey
        )
        if status != noErr, let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
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

private func capabilityProbeHotKeyHandler(
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
    let monitor = Unmanaged<CapabilityProbeHotKeyMonitor>
        .fromOpaque(userData)
        .takeUnretainedValue()
    guard CapabilityProbeHotKeyMonitor.hotKeyIdentifier
        .eventHandlingStatus(for: hotKeyIdentifier) == noErr else {
        return OSStatus(eventNotHandledErr)
    }
    monitor.handleHotKey()
    return noErr
}
#endif
