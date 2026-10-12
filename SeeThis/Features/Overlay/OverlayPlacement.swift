import CoreGraphics
import Foundation

enum OverlayPlacement {
    static let panelSize = CGSize(width: 560, height: 200)
    static let cursorGap: CGFloat = 12

    /// Places the panel near the mouse cursor in AppKit screen coordinates
    /// (origin bottom-left, y increases upward). Prefers below-right, then
    /// below-left, above-right, above-left; clamps into `visibleFrame` when
    /// no quadrant fits without spilling.
    static func frame(
        atMouseLocation point: CGPoint,
        in visibleFrame: CGRect,
        panelSize size: CGSize = panelSize
    ) -> CGRect {
        let belowY = point.y - cursorGap - size.height
        let aboveY = point.y + cursorGap
        let rightX = point.x + cursorGap
        let leftX = point.x - cursorGap - size.width

        let candidates: [CGRect] = [
            CGRect(x: rightX, y: belowY, width: size.width, height: size.height),
            CGRect(x: leftX,  y: belowY, width: size.width, height: size.height),
            CGRect(x: rightX, y: aboveY, width: size.width, height: size.height),
            CGRect(x: leftX,  y: aboveY, width: size.width, height: size.height)
        ]
        if let fit = candidates.first(where: { visibleFrame.contains($0) }) {
            return fit
        }
        return clamp(candidates[0], into: visibleFrame)
    }

    private static func clamp(_ rect: CGRect, into bounds: CGRect) -> CGRect {
        var f = rect
        f.origin.x = max(bounds.minX, min(f.origin.x, bounds.maxX - f.width))
        f.origin.y = max(bounds.minY, min(f.origin.y, bounds.maxY - f.height))
        return f
    }
}
