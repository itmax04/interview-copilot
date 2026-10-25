import AppKit
import CopilotCore
import SwiftUI

/// Свободное изменение размера оверлея мышью (COPILOT-11): рамки и углы окна — полосы с курсором изменения размера.
/// Системная кромка `.resizable` у прозрачной панели с закруглением почти не ловится (4–5 пикселей); эти полосы шире,
/// а курсор подсказывает, за что тянуть. Панель не активируется: события берутся по `NSEvent.mouseLocation`.
@MainActor
final class PanelResizeHandle: NSView {
    let edges: ResizeEdges
    /// Выключает полосу (свернутая панель не растягивается по высоте).
    var isEnabled: () -> Bool = { true }
    /// Размер закончили менять — запомнить ширину.
    var onFinish: (() -> Void)?

    private var startMouse = NSPoint.zero
    private var startFrame = NSRect.zero

    init(edges: ResizeEdges) {
        self.edges = edges
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
        setAccessibilityElement(false)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { isEnabled() ? super.hitTest(point) : nil }

    /// Курсор для полосы: стрелки по сторонам, диагональные — в углах.
    var cursor: NSCursor {
        if edges.isCorner {
            let position: NSCursor.FrameResizePosition = switch (edges.contains(.left), edges.contains(.top)) {
            case (true, true): .topLeft
            case (false, true): .topRight
            case (true, false): .bottomLeft
            case (false, false): .bottomRight
            }
            return NSCursor.frameResize(position: position, directions: .all)
        }
        return edges.isVertical ? .resizeUpDown : .resizeLeftRight
    }

    override func cursorUpdate(with event: NSEvent) {
        if isEnabled() { cursor.set() } else { NSCursor.arrow.set() }
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        startMouse = NSEvent.mouseLocation
        startFrame = window.frame
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - startMouse.x, dy = now.y - startMouse.y
        let frame = PanelResizing.resized(startFrame, edges: edges, dx: dx, dy: dy,
                                 min: window.frameRect(forContentRect: NSRect(origin: .zero, size: window.minSize)).size,
                                 max: window.frameRect(forContentRect: NSRect(origin: .zero, size: window.maxSize)).size)
        if frame != window.frame { window.setFrame(frame, display: true) }
    }

    override func mouseUp(with event: NSEvent) { onFinish?() }

    /// Восемь полос по периметру `container`: стороны — 6 pt, углы — 18 pt (углы лежат поверх сторон).
    static func install(in container: NSView, enabledVertical: @escaping () -> Bool, onFinish: @escaping () -> Void) {
        let side: CGFloat = 6, corner: CGFloat = 18
        func add(_ edges: ResizeEdges, _ constrain: (NSView) -> [NSLayoutConstraint]) {
            let h = PanelResizeHandle(edges: edges)
            if edges.isVertical { h.isEnabled = enabledVertical }
            h.onFinish = onFinish
            container.addSubview(h)
            NSLayoutConstraint.activate(constrain(h))
        }
        add([.left]) { [$0.leadingAnchor.constraint(equalTo: container.leadingAnchor), $0.widthAnchor.constraint(equalToConstant: side),
                        $0.topAnchor.constraint(equalTo: container.topAnchor, constant: corner),
                        $0.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -corner)] }
        add([.right]) { [$0.trailingAnchor.constraint(equalTo: container.trailingAnchor), $0.widthAnchor.constraint(equalToConstant: side),
                         $0.topAnchor.constraint(equalTo: container.topAnchor, constant: corner),
                         $0.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -corner)] }
        add([.top]) { [$0.topAnchor.constraint(equalTo: container.topAnchor), $0.heightAnchor.constraint(equalToConstant: side),
                       $0.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: corner),
                       $0.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -corner)] }
        add([.bottom]) { [$0.bottomAnchor.constraint(equalTo: container.bottomAnchor), $0.heightAnchor.constraint(equalToConstant: side),
                          $0.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: corner),
                          $0.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -corner)] }
        for (edges, x, y) in [(ResizeEdges([.left, .top]), true, true), (ResizeEdges([.right, .top]), false, true),
                              (ResizeEdges([.left, .bottom]), true, false), (ResizeEdges([.right, .bottom]), false, false)] {
            add(edges) { [$0.widthAnchor.constraint(equalToConstant: corner), $0.heightAnchor.constraint(equalToConstant: corner),
                          x ? $0.leadingAnchor.constraint(equalTo: container.leadingAnchor) : $0.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                          y ? $0.topAnchor.constraint(equalTo: container.topAnchor) : $0.bottomAnchor.constraint(equalTo: container.bottomAnchor)] }
        }
    }
}

/// Значок «тяните за угол» в правом нижнем углу панели: три диагональные черточки. Только рисунок — тянет полоса поверх.
struct ResizeGripMark: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            for offset in [CGFloat(4), 8, 12] {
                path.move(to: CGPoint(x: size.width - 1, y: size.height - offset))
                path.addLine(to: CGPoint(x: size.width - offset, y: size.height - 1))
            }
            context.stroke(path, with: .color(.white.opacity(0.38)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
        .frame(width: 14, height: 14)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
