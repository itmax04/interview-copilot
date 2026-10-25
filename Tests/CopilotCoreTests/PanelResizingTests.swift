import CoreGraphics
import Testing
@testable import CopilotCore

@Suite("Размер оверлея мышью — COPILOT-11")
struct PanelResizingTests {
    private let start = CGRect(x: 100, y: 200, width: 420, height: 540)
    private let lower = CGSize(width: 280, height: 220), upper = CGSize(width: 1000, height: 1400)

    private func resize(_ edges: ResizeEdges, _ dx: CGFloat, _ dy: CGFloat) -> CGRect {
        PanelResizing.resized(start, edges: edges, dx: dx, dy: dy, min: lower, max: upper)
    }

    @Test func rightAndBottomRightGrowFromTheOppositeSide() {
        #expect(resize(.right, 80, 999) == CGRect(x: 100, y: 200, width: 500, height: 540))
        // Нижний правый угол: вниз на экране — это отрицательный dy, высота растет, верхний край на месте.
        let corner = resize([.right, .bottom], 60, -100)
        #expect(corner == CGRect(x: 100, y: 100, width: 480, height: 640))
        #expect(corner.maxY == start.maxY)
    }

    @Test func leftAndTopKeepTheFarEdgeInPlace() {
        let left = resize(.left, -120, 0)
        #expect(left.width == 540 && left.maxX == start.maxX)
        let top = resize(.top, 0, 150)
        #expect(top.height == 690 && top.minY == start.minY)
        let topLeft = resize([.left, .top], 30, 50)
        #expect(topLeft.width == 390 && topLeft.height == 590 && topLeft.maxX == start.maxX && topLeft.minY == start.minY)
    }

    @Test func sizeStaysInsideTheLimitsAndTheFarEdgeStillHolds() {
        let tiny = resize([.left, .bottom], 900, 900)
        #expect(tiny.width == 280 && tiny.height == 220)
        #expect(tiny.maxX == start.maxX && tiny.maxY == start.maxY)
        let huge = resize([.right, .top], 5000, 5000)
        #expect(huge.width == 1000 && huge.height == 1400 && huge.minX == start.minX && huge.minY == start.minY)
    }

    @Test func edgeKinds() {
        #expect(ResizeEdges([.left, .top]).isCorner && !ResizeEdges.right.isCorner)
        #expect(ResizeEdges.top.isVertical && !ResizeEdges.left.isVertical && ResizeEdges([.right, .bottom]).isVertical)
    }

    @Test func widthRangeAllowsFreeResizing() {
        #expect(AppSettings.panelWidthRange.upperBound >= 900 && AppSettings.panelWidthRange.lowerBound <= 300)
    }
}
