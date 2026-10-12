import Foundation

/// Metadata directly exposed by a host for its current document.
struct HostDocumentReference: Equatable {
    let url: URL
    let displayName: String
}

enum HostDocumentReferenceCapability: Equatable {
    case unavailable
    case available
}

/// A host's direct result for the current document reference.
enum HostDocumentReferenceCapture: Equatable {
    case unavailable
    case reference(HostDocumentReference)
}
