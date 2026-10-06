import AppKit

/// Иконка-попугай (R-15): монохромный шаблон для строки меню и цветная версия для «О программе» и .app.
/// Рисуется кодом, чтобы не хранить бинарные ассеты; система координат 18×18, y вверх.
@MainActor
enum ParrotIcon {
    private static func headPath() -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: 4.6, y: 10.0, width: 6.0, height: 6.0))
    }

    private static func beakPath() -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 5.2, y: 14.6))
        p.curve(to: NSPoint(x: 2.0, y: 13.2), controlPoint1: NSPoint(x: 3.8, y: 15.6), controlPoint2: NSPoint(x: 2.4, y: 14.8))
        p.curve(to: NSPoint(x: 2.9, y: 10.4), controlPoint1: NSPoint(x: 1.6, y: 12.0), controlPoint2: NSPoint(x: 2.0, y: 10.8))
        p.curve(to: NSPoint(x: 5.0, y: 11.4), controlPoint1: NSPoint(x: 3.4, y: 11.2), controlPoint2: NSPoint(x: 4.2, y: 11.2))
        p.close()
        return p
    }

    private static func bodyPath() -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 6.2, y: 11.4))
        p.curve(to: NSPoint(x: 12.4, y: 5.4), controlPoint1: NSPoint(x: 10.6, y: 12.0), controlPoint2: NSPoint(x: 12.8, y: 8.6))
        p.curve(to: NSPoint(x: 8.0, y: 5.6), controlPoint1: NSPoint(x: 11.6, y: 4.2), controlPoint2: NSPoint(x: 9.0, y: 4.6))
        p.curve(to: NSPoint(x: 6.2, y: 11.4), controlPoint1: NSPoint(x: 6.6, y: 7.2), controlPoint2: NSPoint(x: 5.8, y: 9.4))
        p.close()
        return p
    }

    private static func tailPath() -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 10.2, y: 6.2))
        p.line(to: NSPoint(x: 14.6, y: 0.6))
        p.line(to: NSPoint(x: 16.2, y: 1.4))
        p.line(to: NSPoint(x: 12.4, y: 6.8))
        p.close()
        return p
    }

    private static func wingPath() -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 8.4, y: 10.0))
        p.curve(to: NSPoint(x: 11.8, y: 5.8), controlPoint1: NSPoint(x: 11.0, y: 10.0), controlPoint2: NSPoint(x: 12.2, y: 7.6))
        p.curve(to: NSPoint(x: 8.4, y: 10.0), controlPoint1: NSPoint(x: 10.0, y: 6.4), controlPoint2: NSPoint(x: 8.6, y: 8.0))
        p.close()
        return p
    }

    private static let eye = NSRect(x: 7.0, y: 12.9, width: 1.4, height: 1.4)

    private static func drawParrot(in rect: NSRect, colored: Bool) {
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: rect.minX, yBy: rect.minY)
        t.scale(by: min(rect.width, rect.height) / 18.0)
        t.concat()

        if colored {
            NSColor(srgbRed: 0.10, green: 0.45, blue: 0.95, alpha: 1).setFill(); tailPath().fill()
            NSColor(srgbRed: 0.18, green: 0.72, blue: 0.30, alpha: 1).setFill(); bodyPath().fill()
            NSColor(srgbRed: 0.05, green: 0.50, blue: 0.25, alpha: 1).setFill(); wingPath().fill()
            NSColor(srgbRed: 0.92, green: 0.20, blue: 0.18, alpha: 1).setFill(); headPath().fill()
            NSColor(srgbRed: 0.98, green: 0.78, blue: 0.15, alpha: 1).setFill(); beakPath().fill()
            NSColor.white.setFill(); NSBezierPath(ovalIn: eye.insetBy(dx: -0.25, dy: -0.25)).fill()
            NSColor.black.setFill(); NSBezierPath(ovalIn: eye.insetBy(dx: 0.2, dy: 0.2)).fill()
        } else {
            NSColor.black.setFill()
            for path in [tailPath(), bodyPath(), headPath(), beakPath()] { path.fill() }
            // Глаз — прозрачная точка.
            ctx.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: eye).fill()
        }
        ctx.restoreGraphicsState()
    }

    /// Шаблон для `NSStatusItem` (система сама красит его под светлую/тёмную строку меню).
    static func menuBarTemplate() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            drawParrot(in: rect, colored: false)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Interview Copilot"
        return image
    }

    /// Цветная иконка (окно «О программе»).
    static func colored(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            drawParrot(in: rect, colored: true)
            return true
        }
    }

    /// Иконка приложения: тёмная подложка со скруглением и цветной попугай.
    private static func appIconPNG(pixels: Int) throws -> Data {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { throw CocoaError(.fileWriteUnknown) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let s = CGFloat(pixels)
        let bg = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
        let gradient = NSGradient(starting: NSColor(srgbRed: 0.16, green: 0.20, blue: 0.30, alpha: 1),
                                  ending: NSColor(srgbRed: 0.06, green: 0.08, blue: 0.14, alpha: 1))
        gradient?.draw(in: NSBezierPath(roundedRect: bg, xRadius: s * 0.18, yRadius: s * 0.18), angle: -90)
        drawParrot(in: bg.insetBy(dx: s * 0.12, dy: s * 0.12), colored: true)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        return data
    }

    /// Пишет AppIcon.iconset для `iconutil` (используется `scripts/build-app.sh`).
    static func exportIconset(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            try appIconPNG(pixels: base).write(to: dir.appendingPathComponent("icon_\(base)x\(base).png"))
            try appIconPNG(pixels: base * 2).write(to: dir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
        }
    }
}
