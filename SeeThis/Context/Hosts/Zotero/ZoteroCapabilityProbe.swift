#if DEBUG
import ApplicationServices
import Foundation

enum ZoteroCapabilityCandidate: String, CaseIterable, Equatable {
    case documentAttribute = "document attribute"
    case windowTitle = "window title"
    case selectedTextRange = "selected text range"
    case selectedTextMarkerRange = "selected text marker range"
}

enum ZoteroCapabilityProbeOutcome: String, Equatable {
    case readable
    case noValue = "no value"
    case attributeUnsupported = "attribute unsupported"
    case cannotComplete = "cannot complete"
    case otherAccessibilityError = "other accessibility error"
    case unsupportedValueType = "unsupported value type"

    init(accessibilityError: AXError) {
        switch accessibilityError {
        case .noValue:
            self = .noValue
        case .attributeUnsupported:
            self = .attributeUnsupported
        case .cannotComplete:
            self = .cannotComplete
        default:
            self = .otherAccessibilityError
        }
    }
}

enum ZoteroCapabilityProbeValueCategory: String, Equatable {
    case string
    case number
    case url
    case range
    case textMarkerRange = "text marker range"
    case otherMetadataType = "other metadata type"
}

struct ZoteroCapabilityProbeObservation: Equatable {
    let candidate: ZoteroCapabilityCandidate
    let outcome: ZoteroCapabilityProbeOutcome
    let valueCategory: ZoteroCapabilityProbeValueCategory?
}

struct ZoteroCapabilityProbeSummary: Equatable {
    private(set) var sampleCount = 0
    private(set) var documentReferenceCandidateAvailability = ZoteroDocumentReferenceProbeSummary()
    private var observations: [ZoteroCapabilityProbeObservation] = []

    mutating func record(_ sample: [ZoteroCapabilityProbeObservation]) {
        sampleCount += 1
        observations.append(contentsOf: sample)
        let documentObservation = sample.first {
            $0.candidate == .documentAttribute
        }
        let documentReferenceAvailability: ZoteroDocumentReferenceProbeAvailability
        if documentObservation?.outcome == .readable,
           documentObservation?.valueCategory == .url {
            documentReferenceAvailability = .available
        } else {
            documentReferenceAvailability = .unavailable
        }
        documentReferenceCandidateAvailability.record(documentReferenceAvailability)
    }

    func readableCount(for candidate: ZoteroCapabilityCandidate) -> Int {
        observations.count {
            $0.candidate == candidate && $0.outcome == .readable
        }
    }

    var summary: String {
        guard !observations.isEmpty else {
            return "No Zotero capability probes have been run."
        }
        return ZoteroCapabilityCandidate.allCases.compactMap { candidate in
            let candidateObservations = observations.filter { $0.candidate == candidate }
            guard !candidateObservations.isEmpty else { return nil }
            return "\(candidate.rawValue): \(readableCount(for: candidate))/\(candidateObservations.count) readable"
        }
        .joined(separator: "; ")
    }
}

enum ZoteroDocumentReferenceProbeAvailability: Equatable {
    case available
    case unavailable
}

struct ZoteroDocumentReferenceProbeSummary: Equatable {
    private(set) var sampleCount = 0
    private(set) var availableCount = 0

    mutating func record(_ availability: ZoteroDocumentReferenceProbeAvailability) {
        sampleCount += 1
        if availability == .available {
            availableCount += 1
        }
    }

    var summary: String {
        "Document-reference candidate: \(availableCount)/\(sampleCount) URL-classified"
    }
}

enum ZoteroCapabilityProbeStatus: Equatable {
    case noSamples
    case recorded
    case failed(HostContextFailure)

    var summary: String {
        switch self {
        case .noSamples:
            return "Probe status: no samples."
        case .recorded:
            return "Probe status: sample recorded."
        case .failed(.accessibilityPermissionRequired):
            return "Probe status: Accessibility access required."
        case .failed(.zoteroNotFrontmost):
            return "Probe status: Zotero not frontmost."
        case .failed(.focusedElementUnavailable):
            return "Probe status: focused Zotero element unavailable."
        case .failed:
            return "Probe status: Zotero capability unavailable."
        }
    }
}
#endif
