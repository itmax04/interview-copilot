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
        case .noPermission: L10n.t("Нет разрешения «Запись экрана и системного звука»")
        case .noDisplay: L10n.t("Не найден дисплей")
        case .encodeFailed: L10n.t("Не удалось сжать снимок")
        case .captureFailed(let m): L10n.f("Снимок не получен: %@", m)
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

    /// Снимок экрана вместе с окнами помощника — для проверки видимости оверлея (COPILOT-09 R-17): окно, исключённое
    /// из захвата (`sharingType = .none`), в таком снимке не должно появиться.
    public static func captureDisplayIncludingOwnWindows(_ displayID: CGDirectDisplayID) async throws -> CGImage {
        guard Permissions.screenCaptureGranted else { throw ScreenshotError.noPermission }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw ScreenshotError.captureFailed(error.localizedDescription)
        }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw ScreenshotError.noDisplay }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        let scale = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID }?
            .backingScaleFactor ?? 2
        config.width = Int(Double(display.width) * scale)
        config.height = Int(Double(display.height) * scale)
        config.showsCursor = false
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            throw ScreenshotError.captureFailed(error.localizedDescription)
        }
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


/// Доля пикселей контрольного цвета (пурпурный) в прямоугольнике снимка — проверка видимости, COPILOT-09 R-17.
public enum VisibilityProbe {
    public enum Verdict: Equatable, Sendable {
        case visible, hidden, unclear
    }

    /// Пурпурный по оттенку, а не по точным значениям: снимок приходит в цветовом пространстве дисплея
    /// (sRGB #FF00FF на P3-экране — около 234/51/247, при переводе из generic RGB — 255/64/255).
    public static func isProbe(r: Int, g: Int, b: Int) -> Bool {
        r > 160 && b > 160 && g < min(r, b) - 90
    }

    /// Больше 30% — метка в захвате; меньше 5% — нет; между — однозначно сказать нельзя (окно частично перекрыто, снимок смазан).
    public static func verdict(share: Double) -> Verdict {
        share > 0.3 ? .visible : share < 0.05 ? .hidden : .unclear
    }

    /// `rect` — в пикселях снимка, начало — левый верхний угол.
    public static func fraction(in image: CGImage, rect: CGRect, step: Int = 4) -> Double {
        let bounds = rect.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height)).integral
        guard bounds.width > 0, bounds.height > 0,
              let ctx = CGContext(data: nil, width: Int(bounds.width), height: Int(bounds.height), bitsPerComponent: 8,
                                  bytesPerRow: Int(bounds.width) * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cropped = image.cropping(to: bounds) else { return 0 }
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height))
        guard let data = ctx.data else { return 0 }
        let px = data.bindMemory(to: UInt8.self, capacity: Int(bounds.width * bounds.height) * 4)
        var hit = 0, total = 0
        for y in stride(from: 0, to: Int(bounds.height), by: step) {
            for x in stride(from: 0, to: Int(bounds.width), by: step) {
                let i = (y * Int(bounds.width) + x) * 4
                total += 1
                if isProbe(r: Int(px[i]), g: Int(px[i + 1]), b: Int(px[i + 2])) { hit += 1 }
            }
        }
        return total == 0 ? 0 : Double(hit) / Double(total)
    }
}
