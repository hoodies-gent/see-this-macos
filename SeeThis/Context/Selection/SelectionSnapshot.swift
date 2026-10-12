import CoreGraphics
import Foundation

enum SelectionTextConsistency: Equatable {
    case matches
    case differs
    case unavailable

    init(directText: String, rangeText: String?) {
        guard let rangeText else {
            self = .unavailable
            return
        }
        self = directText == rangeText ? .matches : .differs
    }

    var diagnosticDescription: String {
        switch self {
        case .matches: "text range agrees with direct attribute"
        case .differs: "text range differs from direct attribute"
        case .unavailable: "text range unavailable"
        }
    }
}

struct SelectionSnapshot: Equatable {
    let hostBundleIdentifier: String
    let selectedText: String
    let selectedRange: NSRange?
    let documentTitle: String?
    let textConsistency: SelectionTextConsistency

    init(
        hostBundleIdentifier: String,
        selectedText: String,
        selectedRange: NSRange?,
        documentTitle: String? = nil,
        textConsistency: SelectionTextConsistency = .unavailable
    ) {
        self.hostBundleIdentifier = hostBundleIdentifier
        self.selectedText = selectedText
        self.selectedRange = selectedRange
        self.documentTitle = documentTitle
        self.textConsistency = textConsistency
    }

    var selectedTextLength: Int { selectedText.count }

    var isUsable: Bool { selectedTextLength > 0 }

    var diagnosticSummary: String {
        "Selection: \(selectedTextLength) characters; \(textConsistency.diagnosticDescription)"
    }

    func with(documentTitle: String?) -> SelectionSnapshot {
        SelectionSnapshot(
            hostBundleIdentifier: hostBundleIdentifier,
            selectedText: selectedText,
            selectedRange: selectedRange,
            documentTitle: documentTitle,
            textConsistency: textConsistency
        )
    }
}

enum HostContextFailure: Error, Equatable {
    case accessibilityPermissionRequired
    case zoteroNotFrontmost
    case focusedElementUnavailable
    case selectedTextUnavailable
    case emptySelection
    case selectedTextRangeUnavailable
    case selectionBoundsUnavailable
}
