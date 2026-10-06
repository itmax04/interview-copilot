import Foundation

/// Кольцевой буфер звука в памяти — R-04: не больше 30 с, на диск ничего не пишется.
/// Позиции — абсолютные номера сэмплов с начала сессии, чтобы потребители могли читать «с места, где остановились».
public final class AudioRingBuffer: @unchecked Sendable {
    public let sampleRate: Int
    public let capacity: Int
    private var storage: [Float]
    private var written: Int64 = 0
    private let lock = NSLock()

    public init(seconds: Double = 30, sampleRate: Int = 16_000) {
        precondition(seconds > 0 && seconds <= 30, "R-04: буфер не больше 30 с")
        self.sampleRate = sampleRate
        self.capacity = Int(seconds * Double(sampleRate))
        self.storage = [Float](repeating: 0, count: capacity)
    }

    /// Номер следующего сэмпла (сколько всего записано).
    public var endPosition: Int64 {
        lock.withLock { written }
    }

    /// Самая старая позиция, которая ещё в буфере.
    public var startPosition: Int64 {
        lock.withLock { max(0, written - Int64(capacity)) }
    }

    public func append(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        lock.withLock {
            var input = samples[...]
            if input.count > capacity { input = input.suffix(capacity) ; written += Int64(samples.count - capacity) }
            for s in input {
                storage[Int(written % Int64(capacity))] = s
                written += 1
            }
        }
    }

    /// Сэмплы в диапазоне [from, to). Часть, вытесненная из буфера, отбрасывается.
    public func read(from: Int64, to: Int64? = nil) -> [Float] {
        lock.withLock {
            let end = min(to ?? written, written)
            let start = max(from, written - Int64(capacity), 0)
            guard end > start else { return [] }
            var out = [Float]()
            out.reserveCapacity(Int(end - start))
            var p = start
            while p < end {
                out.append(storage[Int(p % Int64(capacity))])
                p += 1
            }
            return out
        }
    }

    /// Последние `seconds` секунд.
    public func latest(seconds: Double) -> [Float] {
        let n = Int64((seconds * Double(sampleRate)).rounded())
        return read(from: endPosition - n)
    }

    public func clear() {
        lock.withLock {
            written = 0
            for i in storage.indices { storage[i] = 0 }
        }
    }
}
