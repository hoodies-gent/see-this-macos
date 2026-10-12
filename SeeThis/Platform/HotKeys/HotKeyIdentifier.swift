import Carbon

struct HotKeyIdentifier: Equatable {
    let signature: OSType
    let id: UInt32

    var carbonValue: EventHotKeyID {
        EventHotKeyID(signature: signature, id: id)
    }

    func matches(_ eventIdentifier: EventHotKeyID) -> Bool {
        signature == eventIdentifier.signature && id == eventIdentifier.id
    }

    func eventHandlingStatus(for eventIdentifier: EventHotKeyID) -> OSStatus {
        matches(eventIdentifier) ? noErr : OSStatus(eventNotHandledErr)
    }
}

func eventHotKeyIdentifier(from event: EventRef) -> EventHotKeyID? {
    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    return status == noErr ? identifier : nil
}
