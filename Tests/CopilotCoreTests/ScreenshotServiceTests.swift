import AppKit
import Foundation
import Testing
@testable import CopilotCore

@Suite("ScreenshotService — R-14")
struct ScreenshotServiceTests {
    static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../evals/fixtures/two-sum.png").standardized

    func load() throws -> CGImage {
        let data = try Data(contentsOf: Self.fixture)
        let src = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
    }

    @Test func downscalesTo1600LongSide() throws {
        let image = try load()
        #expect(image.width == 2560)
        let jpeg = try ScreenshotService.encode(image)
        let size = try #require(ScreenshotService.pixelSize(of: jpeg))
        #expect(size.0 == 1600 && size.1 == 1000)
        #expect(jpeg.count < 600_000)
        #expect(jpeg.starts(with: [0xFF, 0xD8])) // JPEG
    }

    @Test func smallImagesKeepSize() throws {
        let ctx = CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let jpeg = try ScreenshotService.encode(ctx.makeImage()!)
        #expect(ScreenshotService.pixelSize(of: jpeg)! == (800, 600))
    }
}
