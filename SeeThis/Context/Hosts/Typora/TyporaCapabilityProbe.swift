#if DEBUG
import AppKit
import ApplicationServices

enum TyporaSelectionCaptureAttempt: Equatable {
    case characterRange
    case textMarkerRange
}

struct TyporaSelectionCapturePlan {
    let attempts: [TyporaSelectionCaptureAttempt] = [.characterRange, .textMarkerRange]
}

enum TyporaCapabilityProbeOutcome: Error, Equatable {
    case success
    case accessibilityPermissionRequired
    case typoraNotFrontmost
    case focusedElementUnavailable
    case selectedTextUnavailable
    case emptySelection
    case selectedTextRangeUnavailable
    case selectionBoundsUnavailable
}

struct TyporaCapabilityProbeSummary: Equatable {
    private(set) var sampleCount = 0
    private(set) var successCount = 0

    mutating func record(_ outcome: TyporaCapabilityProbeOutcome) {
        sampleCount += 1
        if outcome == .success {
            successCount += 1
        }
    }

    var summary: String {
        "Typora feasibility: \(successCount)/\(sampleCount) captures supplied selected text and an anchor frame."
    }
}

/// Product-level runtime declaration of whether Typora exposes a stable
/// current-document reference. Kept `.unavailable` until a bounded manual
/// probe confirms Typora directly exposes a stable file URL or identity.
enum TyporaDocumentReferenceCapability: Equatable {
    case unavailable
}

/// Category recorded by one bounded Typora document-reference probe sample.
enum TyporaDocumentReferenceProbeAvailability: Equatable {
    case available
    case unavailable
}

struct TyporaDocumentReferenceProbeSummary: Equatable {
    private(set) var sampleCount = 0
    private(set) var availableCount = 0

    mutating func record(_ availability: TyporaDocumentReferenceProbeAvailability) {
        sampleCount += 1
        if availability == .available {
            availableCount += 1
        }
    }

    var summary: String {
        "Typora document-reference candidate: \(availableCount)/\(sampleCount) URL-classified"
    }
}

enum TyporaCapabilityProbeStatus: Equatable {
    case noSamples
    case recorded
    case failed(TyporaCapabilityProbeOutcome)

    var summary: String {
        switch self {
        case .noSamples:
            return "Typora feasibility: no samples."
        case .recorded:
            return "Typora feasibility: sample recorded."
        case .failed(.accessibilityPermissionRequired):
            return "Typora feasibility: Accessibility access required."
        case .failed(.typoraNotFrontmost):
            return "Typora feasibility: Typora is not frontmost."
        case .failed(.focusedElementUnavailable):
            return "Typora feasibility: focused element unavailable."
        case .failed(.selectedTextUnavailable):
            return "Typora feasibility: selected text unavailable."
        case .failed(.emptySelection):
            return "Typora feasibility: no text selected."
        case .failed(.selectedTextRangeUnavailable):
            return "Typora feasibility: selected text range unavailable."
        case .failed(.selectionBoundsUnavailable):
            return "Typora feasibility: selection frame unavailable."
        case .failed(.success):
            return "Typora feasibility: capability unavailable."
        }
    }
}

struct TyporaHostContextProvider {
    var documentReferenceCapability: TyporaDocumentReferenceCapability { .unavailable }
    var documentReferenceCapture: HostDocumentReferenceCapture { .unavailable }

    /// Bounded observational probe: reads only the standard AX document
    /// attribute on the focused Typora window and returns a category. Records
    /// no URL value, file name, selected text, or document content.
    func probeDocumentReference() -> Result<TyporaDocumentReferenceProbeAvailability, TyporaCapabilityProbeOutcome> {
        guard AXIsProcessTrusted() else {
            return .failure(.accessibilityPermissionRequired)
        }
        guard let application = NSWorkspace.shared.frontmostApplication,
              HostProviderRouter.host(for: application.bundleIdentifier) == .typora else {
            return .failure(.typoraNotFrontmost)
        }
        let typora = AXUIElementCreateApplication(application.processIdentifier)
        guard let focusedWindowValue = attributeValue(
            kAXFocusedWindowAttribute,
            from: typora
        ), CFGetTypeID(focusedWindowValue) == AXUIElementGetTypeID() else {
            return .failure(.focusedElementUnavailable)
        }
        let focusedWindow = focusedWindowValue as! AXUIElement

        var documentValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            focusedWindow,
            kAXDocumentAttribute as CFString,
            &documentValue
        )
        guard error == .success, let documentValue else {
            return .success(.unavailable)
        }
        return .success(documentValue is URL ? .available : .unavailable)
    }

    func capture() -> Result<SelectionSnapshot, TyporaCapabilityProbeOutcome> {
        guard AXIsProcessTrusted() else {
            return .failure(.accessibilityPermissionRequired)
        }

        guard let application = NSWorkspace.shared.frontmostApplication,
              HostProviderRouter.host(for: application.bundleIdentifier) == .typora else {
            return .failure(.typoraNotFrontmost)
        }

        let typora = AXUIElementCreateApplication(application.processIdentifier)
        guard let focusedElementValue = attributeValue(
            kAXFocusedUIElementAttribute,
            from: typora
        ), CFGetTypeID(focusedElementValue) == AXUIElementGetTypeID() else {
            return .failure(.focusedElementUnavailable)
        }
        let focusedElement = focusedElementValue as! AXUIElement

        guard let selectedText = attributeValue(
            kAXSelectedTextAttribute,
            from: focusedElement
        ) as? String else {
            return .failure(.selectedTextUnavailable)
        }
        guard !selectedText.isEmpty else {
            return .failure(.emptySelection)
        }

        var foundSelectionRange = false
        for attempt in TyporaSelectionCapturePlan().attempts {
            let range: CFTypeRef?
            let boundsAttribute: String
            let selectedRange: NSRange?
            switch attempt {
            case .characterRange:
                guard let selectedTextRange = attributeValue(
                    kAXSelectedTextRangeAttribute,
                    from: focusedElement
                ), CFGetTypeID(selectedTextRange) == AXValueGetTypeID(),
                AXValueGetType(selectedTextRange as! AXValue) == .cfRange else {
                    continue
                }
                var rangeValue = CFRange()
                guard AXValueGetValue(
                    selectedTextRange as! AXValue,
                    .cfRange,
                    &rangeValue
                ), rangeValue.length > 0 else {
                    continue
                }
                range = selectedTextRange
                boundsAttribute = kAXBoundsForRangeParameterizedAttribute
                selectedRange = NSRange(location: rangeValue.location, length: rangeValue.length)
            case .textMarkerRange:
                guard let textMarkerRange = attributeValue(
                    kAXSelectedTextMarkerRangeAttribute,
                    from: focusedElement
                ), CFGetTypeID(textMarkerRange) == AXTextMarkerRangeGetTypeID() else {
                    continue
                }
                range = textMarkerRange
                boundsAttribute = kAXBoundsForTextMarkerRangeParameterizedAttribute
                selectedRange = nil
            }

            guard let range else { continue }
            foundSelectionRange = true
            if let selectionFrame = selectionFrame(
                for: range,
                boundsAttribute: boundsAttribute,
                from: focusedElement
            ), isUsable(selectionFrame) {
                return .success(
                    Self.selectionSnapshot(
                        selectedText: selectedText,
                        selectedRange: selectedRange
                    )
                )
            }
        }

        return .failure(
            foundSelectionRange ? .selectionBoundsUnavailable : .selectedTextRangeUnavailable
        )
    }

    static func selectionSnapshot(
        selectedText: String,
        selectedRange: NSRange?
    ) -> SelectionSnapshot {
        SelectionSnapshot(
            hostBundleIdentifier: "abnerworks.Typora",
            selectedText: selectedText,
            selectedRange: selectedRange
        )
    }

    private func attributeValue(_ attribute: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private func parameterizedAttributeValue(
        _ attribute: String,
        parameter: CFTypeRef,
        from element: AXUIElement
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            attribute as CFString,
            parameter,
            &value
        ) == .success else {
            return nil
        }
        return value
    }

    private func selectionFrame(
        for range: CFTypeRef,
        boundsAttribute: String,
        from element: AXUIElement
    ) -> CGRect? {
        guard let selectionBoundsValue = parameterizedAttributeValue(
            boundsAttribute,
            parameter: range,
            from: element
        ), CFGetTypeID(selectionBoundsValue) == AXValueGetTypeID() else {
            return nil
        }
        let selectionBounds = selectionBoundsValue as! AXValue
        guard AXValueGetType(selectionBounds) == .cgRect else {
            return nil
        }

        var selectionFrame = CGRect.zero
        guard AXValueGetValue(selectionBounds, .cgRect, &selectionFrame) else {
            return nil
        }
        return selectionFrame
    }

    private func isUsable(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
            && frame.width > 0
            && frame.height > 0
    }
}
#endif
