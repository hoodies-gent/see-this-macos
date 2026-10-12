import AppKit
import SwiftUI

enum LensChooserLayout: Equatable {
    case horizontalSingleRow
    case horizontalWrapped
    case verticalFullWidth
}

enum OverlayLensListLayout {
    static let horizontalSpacing: CGFloat = 6
    static let verticalSpacing: CGFloat = 6
    static let rowHeight: CGFloat = 28
    static let maximumStackHeight: CGFloat = 180
    static let buttonChromeWidth: CGFloat = 22

    static func estimatedButtonWidth(for label: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
        ]
        let textWidth = (label as NSString).size(withAttributes: attributes).width
        return ceil(textWidth) + buttonChromeWidth
    }

    static func plan(
        buttonLabels: [String],
        availableWidth: CGFloat
    ) -> (layout: LensChooserLayout, sectionHeight: CGFloat) {
        guard !buttonLabels.isEmpty else { return (.verticalFullWidth, 0) }

        let widths = buttonLabels.map(estimatedButtonWidth(for:))
        let count = widths.count
        let singleRowWidth = widths.reduce(0, +)
            + CGFloat(max(count - 1, 0)) * horizontalSpacing
        if singleRowWidth <= availableWidth {
            return (.horizontalSingleRow, rowHeight)
        }

        let widestButton = widths.max() ?? 0
        if widestButton <= availableWidth {
            let rows = wrappedRowCount(widths: widths, availableWidth: availableWidth)
            let height = CGFloat(rows) * rowHeight
                + CGFloat(max(rows - 1, 0)) * verticalSpacing
            return (.horizontalWrapped, height)
        }

        let stackHeight = CGFloat(count) * rowHeight
            + CGFloat(max(count - 1, 0)) * verticalSpacing
        return (.verticalFullWidth, min(stackHeight, maximumStackHeight))
    }

    static func wrappedRowCount(widths: [CGFloat], availableWidth: CGFloat) -> Int {
        var rows = 1
        var used: CGFloat = 0
        for (index, width) in widths.enumerated() {
            let spacing: CGFloat = index == 0 ? 0 : horizontalSpacing
            if used + spacing + width <= availableWidth {
                used += spacing + width
            } else {
                rows += 1
                used = width
            }
        }
        return rows
    }
}

struct LensButtonFlow: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let availableWidth = proposal.width ?? .infinity
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var rowWidth: CGFloat = 0
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            let spacing: CGFloat = index == 0 || rowWidth == 0 ? 0 : horizontalSpacing
            if rowWidth + spacing + size.width > availableWidth && rowWidth > 0 {
                totalHeight += rowHeight + verticalSpacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += spacing + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let availableWidth = bounds.width
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            let atRowStart = x == bounds.minX
            let spacing: CGFloat = atRowStart ? 0 : horizontalSpacing
            if x - bounds.minX + spacing + size.width > availableWidth && !atRowStart {
                y += rowHeight + verticalSpacing
                x = bounds.minX
                rowHeight = 0
            } else {
                x += spacing
            }
            subviews[index].place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }
    }
}
enum LensHoverAppearance {
    static let backgroundOpacity = 0.08
    static let isLimitedToControlBounds = true
    static let hitTestingPrecedesLayoutExpansion = true
    static let cornerRadius: CGFloat = 6
}

enum LensStatusTypography: Equatable {
    case body

    static let current = Self.body

    var font: Font {
        switch self {
        case .body:
            .body
        }
    }
}
