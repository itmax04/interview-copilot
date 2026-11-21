import Foundation

/// Звук вопроса для повторного распознавания целиком (COPILOT-15 R-02, R-03).
public struct QuestionAudio: Sendable, Equatable {
    public enum Source: String, Sendable { case ring, joined }
    public var samples: [Float]
    public var source: Source
    public var utterances: [Int]
    public var seconds: Double { Double(samples.count) / 16_000 }
}

/// Границы и звук фраз текущего потока собеседника: по ним строится звук хода (вопроса).
/// Звук только в памяти (R-04): хранится не больше `maxStoredSeconds`, после использования освобождается.
///
/// Правила R-02: диапазон от начала первой фразы хода (с pre-roll) до конца последней. Если фразы идут подряд
/// (номера без пропусков), диапазон ≤ 30 с и ещё в кольцевом буфере — он читается из буфера целиком, со всеми
/// паузами. Иначе (ход длиннее буфера, пропущенная или отброшенная фраза, репетиция, где часть фраз — ответы владельца)
/// фразы склеиваются с паузами по 150 мс.
public final class QuestionAudioRange: @unchecked Sendable {
    struct Span {
        var utterance: Int
        var start: Int64
        var end: Int64
        var audio: [Float]
        /// Репетиция с собеседником: `true` — фраза владельца, она в вопрос не входит (R-03).
        var owner: Bool?
    }

    public static let gapSeconds = 0.15
    public static let maxRingSeconds = 30.0

    private let sampleRate: Int
    private let maxStoredSeconds: Double
    private let lock = NSLock()
    private var spans: [Int: Span] = [:]

    public init(sampleRate: Int = 16_000, maxStoredSeconds: Double = 120) {
        self.sampleRate = sampleRate
        self.maxStoredSeconds = maxStoredSeconds
    }

    /// Закрытая фраза: позиции в кольцевом буфере (с pre-roll) и её звук.
    public func record(utterance: Int, start: Int64, end: Int64, audio: [Float]) {
        lock.withLock {
            spans[utterance] = Span(utterance: utterance, start: start, end: end, audio: audio, owner: nil)
            evict()
        }
    }

    /// Кто сказал фразу (`.speaker`, режим репетиции).
    public func setRoute(utterance: Int, owner: Bool) {
        lock.withLock { spans[utterance]?.owner = owner }
    }

    /// Фраза не стала текстом (шум, чужой голос): звук ей больше не нужен.
    public func drop(utterance: Int) {
        lock.withLock { _ = spans.removeValue(forKey: utterance) }
    }

    /// Звук использован — освободить.
    public func release(utterances: [Int]) {
        lock.withLock { for u in utterances { spans.removeValue(forKey: u) } }
    }

    public var storedCount: Int { lock.withLock { spans.count } }

    /// Звук вопроса из фраз `utterances` (по порядку). nil — звука нет (фразы вытеснены или не записаны).
    public func audio(for utterances: [Int], ring: AudioRingBuffer) -> QuestionAudio? {
        let (picked, filtered) = lock.withLock { () -> ([Span], Bool) in
            let all = utterances.compactMap { spans[$0] }
            let own = all.filter { $0.owner != true }
            return (own, own.count != all.count)
        }
        guard let first = picked.first, let last = picked.last else { return nil }
        let ids = picked.map(\.utterance)
        let consecutive = zip(ids, ids.dropFirst()).allSatisfy { $1 == $0 + 1 }
        let seconds = Double(last.end - first.start) / Double(sampleRate)
        let continuous = consecutive && !filtered && picked.count == utterances.count
        if continuous, seconds <= Self.maxRingSeconds, first.start >= ring.startPosition {
            let samples = ring.read(from: first.start, to: last.end)
            if !samples.isEmpty { return QuestionAudio(samples: samples, source: .ring, utterances: ids) }
        }
        let gap = [Float](repeating: 0, count: Int(Self.gapSeconds * Double(sampleRate)))
        var joined: [Float] = []
        for (i, span) in picked.enumerated() {
            if i > 0 { joined += gap }
            joined += span.audio
        }
        return QuestionAudio(samples: joined, source: .joined, utterances: ids)
    }

    private func evict() {
        var total = spans.values.reduce(0) { $0 + $1.audio.count }
        let limit = Int(maxStoredSeconds * Double(sampleRate))
        guard total > limit else { return }
        for key in spans.keys.sorted() {
            guard total > limit else { break }
            total -= spans[key]?.audio.count ?? 0
            spans.removeValue(forKey: key)
        }
    }
}
