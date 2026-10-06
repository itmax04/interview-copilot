// Синтетический «скриншот» условия задачи для проверки S-06 (evals/fixtures/two-sum.png).
// Рисуется офскрин: у процесса исполнителя нет разрешения «Запись экрана», а реальные данные в фикстурах не нужны.
// Запуск: swift scripts/make-screenshot-fixture.swift
import AppKit

let size = NSSize(width: 2560, height: 1600)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(white: 0.97, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()
// «Окно браузера»
NSColor(white: 0.88, alpha: 1).setFill()
NSRect(x: 0, y: size.height - 110, width: size.width, height: 110).fill()
let addr = "https://example.com/interview/task/two-sum"
addr.draw(at: NSPoint(x: 60, y: size.height - 75), withAttributes: [.font: NSFont.systemFont(ofSize: 34), .foregroundColor: NSColor.darkGray])
let text = """
1. Two Sum

Given an array of integers nums and an integer target, return the indices of the two numbers
such that they add up to target. You may assume that each input has exactly one solution,
and you may not use the same element twice. Return the answer in any order.

Example 1:
  Input: nums = [2, 7, 11, 15], target = 9
  Output: [0, 1]

Example 2:
  Input: nums = [3, 2, 4], target = 6
  Output: [1, 2]

Constraints:
  2 <= nums.length <= 10^4
  -10^9 <= nums[i] <= 10^9
  Only one valid answer exists.

func twoSum(_ nums: [Int], _ target: Int) -> [Int] {
    // your code here
}
"""
let style = NSMutableParagraphStyle()
style.lineSpacing = 10
text.draw(in: NSRect(x: 120, y: 120, width: size.width - 240, height: size.height - 300),
          withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 40, weight: .regular), .foregroundColor: NSColor.black,
                           .paragraphStyle: style])
NSGraphicsContext.restoreGraphicsState()
let url = URL(fileURLWithPath: "evals/fixtures/two-sum.png")
try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
try rep.representation(using: .png, properties: [:])!.write(to: url)
print("evals/fixtures/two-sum.png")
