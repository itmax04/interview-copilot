import CoreGraphics
import Foundation

/// Стороны, за которые тянут окно оверлея (COPILOT-11).
public struct ResizeEdges: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let left = ResizeEdges(rawValue: 1), right = ResizeEdges(rawValue: 2)
    public static let top = ResizeEdges(rawValue: 4), bottom = ResizeEdges(rawValue: 8)

    public var isCorner: Bool { (contains(.left) || contains(.right)) && (contains(.top) || contains(.bottom)) }
    public var isVertical: Bool { contains(.top) || contains(.bottom) }
}

public enum PanelResizing {
    /// Новая рамка при перетаскивании: противоположная сторона остается на месте, размер — в пределах `min`…`max`.
    /// Координаты экранные: начало внизу слева, `dy` вверх положительный.
    public static func resized(_ start: CGRect, edges: ResizeEdges, dx: CGFloat, dy: CGFloat, min lower: CGSize, max upper: CGSize) -> CGRect {
        func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.min(Swift.max(v, lo), hi) }
        var f = start
        if edges.contains(.right) { f.size.width = clamp(start.width + dx, lower.width, upper.width) }
        if edges.contains(.left) {
            f.size.width = clamp(start.width - dx, lower.width, upper.width)
            f.origin.x = start.maxX - f.width
        }
        if edges.contains(.top) { f.size.height = clamp(start.height + dy, lower.height, upper.height) }
        if edges.contains(.bottom) {
            f.size.height = clamp(start.height - dy, lower.height, upper.height)
            f.origin.y = start.maxY - f.height
        }
        return f
    }
}
