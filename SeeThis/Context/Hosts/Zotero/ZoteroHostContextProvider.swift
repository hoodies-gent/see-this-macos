#if DEBUG
import AppKit
import ApplicationServices

struct ZoteroHostContextProvider {
    var documentReferenceCapability: HostDocumentReferenceCapability { .unavailable }
    var documentReferenceCapture: HostDocumentReferenceCapture { .unavailable }

    func probeCapabilities() -> Result<[ZoteroCapabilityProbeObservation], HostContextFailure> {
        guard AXIsProcessTrusted() else { return .failure(.accessibilityPermissionRequired) }
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier == "org.zotero.zotero" else { return .failure(.zoteroNotFrontmost) }
        let zotero = AXUIElementCreateApplication(application.processIdentifier)
        guard let focusedElementValue = attributeValue(kAXFocusedUIElementAttribute, from: zotero),
              CFGetTypeID(focusedElementValue) == AXUIElementGetTypeID(),
              let focusedWindowValue = attributeValue(kAXFocusedWindowAttribute, from: zotero),
              CFGetTypeID(focusedWindowValue) == AXUIElementGetTypeID() else { return .failure(.focusedElementUnavailable) }
        let focusedElement = focusedElementValue as! AXUIElement
        let focusedWindow = focusedWindowValue as! AXUIElement
        return .success([
            probe(kAXDocumentAttribute, candidate: .documentAttribute, from: focusedWindow),
            probe(kAXTitleAttribute, candidate: .windowTitle, from: focusedWindow),
            probe(kAXSelectedTextRangeAttribute, candidate: .selectedTextRange, from: focusedElement),
            probe(kAXSelectedTextMarkerRangeAttribute, candidate: .selectedTextMarkerRange, from: focusedElement)
        ])
    }

    private func probe(_ attribute: String, candidate: ZoteroCapabilityCandidate, from element: AXUIElement) -> ZoteroCapabilityProbeObservation {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success, let value else {
            return .init(candidate: candidate, outcome: .init(accessibilityError: error), valueCategory: nil)
        }
        let category: ZoteroCapabilityProbeValueCategory? = CFGetTypeID(value) == AXValueGetTypeID()
            ? (AXValueGetType(value as! AXValue) == .cfRange ? .range : .otherMetadataType)
            : (CFGetTypeID(value) == AXTextMarkerRangeGetTypeID() ? .textMarkerRange : (value is URL ? .url : (value is String ? .string : nil)))
        return .init(candidate: candidate, outcome: category == nil ? .unsupportedValueType : .readable, valueCategory: category)
    }

    private func attributeValue(
        _ attribute: String,
        from element: AXUIElement
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }
}

extension HostContextFailure {
    var message: String {
        switch self {
        case .accessibilityPermissionRequired:
            return "Accessibility access is required."
        case .zoteroNotFrontmost:
            return "Bring Zotero to the front, select text, then try again."
        case .focusedElementUnavailable:
            return "Zotero did not expose a focused text element."
        case .selectedTextUnavailable:
            return "Zotero did not expose selected text."
        case .emptySelection:
            return "No text is selected in Zotero."
        case .selectedTextRangeUnavailable:
            return "Zotero did not expose the selected text range."
        case .selectionBoundsUnavailable:
            return "Zotero did not expose a usable selection frame."
        }
    }
}
#endif
