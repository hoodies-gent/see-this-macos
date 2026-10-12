import AppKit
import SwiftUI

enum ContextTagLayout {
    static let maximumWidth: CGFloat = 190
    static let maximumTextWidth: CGFloat = maximumWidth - 32
    static let lineLimit = 1
    static let truncationMode: Text.TruncationMode = .middle
    static let horizontalPadding: CGFloat = 6
    static let verticalPadding: CGFloat = 2
}

enum ContextTagTypography: Equatable {
    case caption
    case callout

    static let label = Self.callout
    static let tag = Self.caption

    var font: Font {
        switch self {
        case .caption:
            .caption
        case .callout:
            .callout
        }
    }
}
enum ContextTagHoverBehavior {
    static let trackingOptions: NSTrackingArea.Options = [
        .mouseEnteredAndExited,
        .inVisibleRect,
        .activeAlways
    ]

    static var tracksWhileInactive: Bool {
        trackingOptions.contains(.activeAlways)
    }
}

enum ContextTagInteraction {
    static let opensDetailsOnClick = true
    static let opensDetailsOnHover = false
    static let offersCopyAction = true
    static let copyActionUsesIcon = true
    static let detailsRemainVisibleAfterCopy = true
}

enum ContextTagPopoverLayout {
    static let maximumWidth: CGFloat = 240
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 10
    static let copyControlReservedWidth: CGFloat = 18
}

enum ContextTagPopoverTypography: Equatable {
    case caption2

    static let current = Self.caption2

    var font: Font {
        switch self {
        case .caption2:
            .caption2
        }
    }
}

enum ContextTagCopyFeedback: Equatable {
    case ready
    case copied

    static let displayDurationNanoseconds: UInt64 = 1_000_000_000

    var iconName: String {
        self == .copied ? "checkmark" : "doc.on.doc"
    }

    mutating func markCopied() {
        self = .copied
    }

    mutating func reset() {
        self = .ready
    }
}

private struct ContextTagHoverTracker: NSViewRepresentable {
    @Binding var isHovering: Bool

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onHoverChanged = updateHoverState
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onHoverChanged = updateHoverState
    }

    private func updateHoverState(_ isHovering: Bool) {
        DispatchQueue.main.async {
            self.isHovering = isHovering
        }
    }

    final class TrackingView: NSView {
        var onHoverChanged: ((Bool) -> Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let trackingArea = NSTrackingArea(
                rect: .zero,
                options: ContextTagHoverBehavior.trackingOptions,
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
            self.trackingArea = trackingArea
        }

        override func mouseEntered(with event: NSEvent) {
            onHoverChanged?(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHoverChanged?(false)
        }
    }
}

struct ContextTag: View {
    let name: String
    @State private var isHovering = false
    @State private var showsDetails = false
    @State private var copyFeedback = ContextTagCopyFeedback.ready
    @State private var copyFeedbackToken: UUID?

    // Keep in sync with localSourceName scope suffixes in ContentView.swift.
    private static let scopeSuffixes = [
        " · full document",
        " · selection window",
        " · document start"
    ]

    private var copyableName: String {
        for suffix in Self.scopeSuffixes where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }

    var body: some View {
        Button {
            showsDetails = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc")
                Text(name)
                    .lineLimit(ContextTagLayout.lineLimit)
                    .truncationMode(ContextTagLayout.truncationMode)
            }
            .font(ContextTagTypography.tag.font)
            .padding(.horizontal, ContextTagLayout.horizontalPadding)
            .padding(.vertical, ContextTagLayout.verticalPadding)
            .background(.quaternary, in: Capsule())
            .overlay {
                Capsule()
                    .fill(.primary.opacity(isHovering ? 0.05 : 0))
            }
            .frame(maxWidth: ContextTagLayout.maximumWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(ContextTagHoverTracker(isHovering: $isHovering))
        .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
            ZStack(alignment: .bottomTrailing) {
                Text(copyableName)
                    .font(ContextTagPopoverTypography.current.font)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, ContextTagPopoverLayout.copyControlReservedWidth)
                    .frame(maxWidth: ContextTagPopoverLayout.maximumWidth, alignment: .leading)
                Button {
                    NSPasteboard.general.clearContents()
                    guard NSPasteboard.general.setString(copyableName, forType: .string) else { return }
                    copyFeedback.markCopied()
                    let feedbackToken = UUID()
                    copyFeedbackToken = feedbackToken
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: ContextTagCopyFeedback.displayDurationNanoseconds)
                        guard copyFeedbackToken == feedbackToken else { return }
                        copyFeedback.reset()
                    }
                } label: {
                    Image(systemName: copyFeedback.iconName)
                        .frame(
                            width: ContextTagPopoverLayout.copyControlReservedWidth,
                            height: ContextTagPopoverLayout.copyControlReservedWidth
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(copyFeedback == .copied ? "Copied filename" : "Copy filename")
            }
            .padding(.horizontal, ContextTagPopoverLayout.horizontalPadding)
            .padding(.vertical, ContextTagPopoverLayout.verticalPadding)
        }
    }
}
