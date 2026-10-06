import AppKit
import CoreGraphics
import Foundation
import ImageIO
@preconcurrency import ScreenCaptureKit
import UniformTypeIdentifiers

public enum ScreenshotError: Error, CustomStringConvertible {
    case noPermission
    case noDisplay
    case encodeFailed
    case captureFailed(String)

    public var description: String {
        switch self {
        case .noPermission: "Нет разрешения «Запись экрана и системного звука»"
        case .noDisplay: "Не найден дисплей"
        case .encodeFailed: "Не удалось сжать снимок"
        case .captureFailed(let m): "Снимок не получен: \(m)"
        }
    }
}

/// Снимок экрана для задачи — R-14, S-06: дисплей под курсором, с курсором, без окон помощника,
/// сжатие до ≤ 1600 px по длинной стороне, JPEG только в памяти (на диск не пишется).
public enum ScreenshotService {
    public static let maxSide = 1600

    public static func captureDisplayUnderCursor() async throws -> Data {
        guard Permissions.screenCaptureGranted else { throw ScreenshotError.noPermission }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw ScreenshotError.captureFailed(error.localizedDescription)
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let displayID = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw ScreenshotError.noDisplay
        }
        // Окна и меню помощника не попадают в снимок (R-14).
        let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
        let config = SCStreamConfiguration()
        let scale = screen?.backingScaleFactor ?? 2
        config.width = Int(Double(display.width) * scale)
        config.height = Int(Double(display.height) * scale)
        config.showsCursor = true
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            throw ScreenshotError.captureFailed(error.localizedDescription)
        }
        return try encode(image)
    }

    /// Уменьшение до `maxSide` по длинной стороне и JPEG.
    public static func encode(_ image: CGImage, maxSide: Int = maxSide, quality: Double = 0.8) throws -> Data {
        let scaled = downscale(image, maxSide: maxSide) ?? image
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ScreenshotError.encodeFailed
        }
        CGImageDestinationAddImage(dest, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ScreenshotError.encodeFailed }
        return data as Data
    }

    public static func downscale(_ image: CGImage, maxSide: Int) -> CGImage? {
        let w = image.width, h = image.height
        let longest = max(w, h)
        guard longest > maxSide else { return image }
        let ratio = Double(maxSide) / Double(longest)
        let nw = max(1, Int((Double(w) * ratio).rounded())), nh = max(1, Int((Double(h) * ratio).rounded()))
        guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        return ctx.makeImage()
    }

    /// Размер JPEG (для проверок).
    public static func pixelSize(of jpeg: Data) -> (Int, Int)? {
        guard let src = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }
}
