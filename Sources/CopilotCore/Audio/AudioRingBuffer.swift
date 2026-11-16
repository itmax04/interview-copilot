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
            // Два блочных копирования (до конца кольца и с начала) вместо деления по модулю на каждый сэмпл:
            // запись идёт из потока захвата под замком, который ждёт и распознавание.
            let count = input.count
            let offset = Int(written % Int64(capacity))
            let head = min(count, capacity - offset)
            input.withUnsafeBufferPointer { src in
                storage.withUnsafeMutableBufferPointer { dst in
                    guard let from = src.baseAddress, let to = dst.baseAddress else { return }
                    (to + offset).update(from: from, count: head)
                    if head < count { to.update(from: from + head, count: count - head) }
                }
            }
            written += Int64(count)
        }
    }

    /// Сэмплы в диапазоне [from, to). Часть, вытесненная из буфера, отбрасывается.
    public func read(from: Int64, to: Int64? = nil) -> [Float] {
        lock.withLock {
            let end = min(to ?? written, written)
            let start = max(from, written - Int64(capacity), 0)
            guard end > start else { return [] }
            // Реплика до 25 с (400 тыс. сэмплов) читается на каждый частичный прогон — блочно, а не по сэмплу.
            let count = Int(end - start)
            let offset = Int(start % Int64(capacity))
            let head = min(count, capacity - offset)
            return [Float](unsafeUninitializedCapacity: count) { out, initialized in
                storage.withUnsafeBufferPointer { src in
                    guard let from = src.baseAddress, let to = out.baseAddress else { return }
                    to.initialize(from: from + offset, count: head)
                    if head < count { (to + head).initialize(from: from, count: count - head) }
                    initialized = count
                }
            }
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
