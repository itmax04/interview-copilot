import Foundation
import Testing
@testable import CopilotCore

@Suite("COPILOT-15 P-03 — QuestionAudioRange (AC-06)")
struct QuestionAudioRangeTests {
    private let sr = 16_000

    /// Кольцо, где сэмпл на позиции p равен p / 1_000_000 (по значению видно, откуда прочитано).
    private func ring(seconds: Double = 30, filledSeconds: Double) -> AudioRingBuffer {
        let ring = AudioRingBuffer(seconds: seconds, sampleRate: sr)
        let n = Int(filledSeconds * Double(sr))
        ring.append((0..<n).map { Float($0) / 1_000_000 })
        return ring
    }

    private func phrase(_ range: QuestionAudioRange, _ u: Int, _ startSec: Double, _ endSec: Double, ring: AudioRingBuffer) {
        let s = Int64(startSec * Double(sr)), e = Int64(endSec * Double(sr))
        range.record(utterance: u, start: s, end: e, audio: ring.read(from: s, to: e))
    }

    @Test("Continuous range up to 30 s is read from the ring with the pauses between phrases")
    func continuousReadsRing() {
        let ring = ring(filledSeconds: 20)
        let range = QuestionAudioRange()
        phrase(range, 1, 1, 4, ring: ring)
        phrase(range, 2, 5, 9, ring: ring)
        let audio = range.audio(for: [1, 2], ring: ring)
        #expect(audio?.source == .ring)
        #expect(audio?.samples.count == 8 * sr)
        #expect(audio?.samples.first == ring.read(from: Int64(sr), to: Int64(sr) + 1).first)
    }

    @Test("A range longer than 30 s joins the saved phrases with 150 ms gaps")
    func longRangeJoins() {
        let ring = ring(filledSeconds: 70)
        let range = QuestionAudioRange()
        // Звук фраз сохранён в момент закрытия, когда он ещё был в кольце.
        range.record(utterance: 1, start: Int64(2 * sr), end: Int64(22 * sr), audio: [Float](repeating: 0.1, count: 20 * sr))
        range.record(utterance: 2, start: Int64(22 * sr), end: Int64(40 * sr), audio: [Float](repeating: 0.1, count: 18 * sr))
        let audio = range.audio(for: [1, 2], ring: ring)
        #expect(audio?.source == .joined)
        #expect(audio?.samples.count == 38 * sr + Int(0.15 * Double(sr)))
    }

    @Test("A dropped phrase in the middle (gap in numbers) joins instead of reading the ring")
    func gapJoins() {
        let ring = ring(filledSeconds: 20)
        let range = QuestionAudioRange()
        phrase(range, 1, 1, 3, ring: ring)
        phrase(range, 3, 6, 8, ring: ring)   // 2 was noise and is gone
        let audio = range.audio(for: [1, 3], ring: ring)
        #expect(audio?.source == .joined)
        #expect(audio?.samples.count == 4 * sr + Int(0.15 * Double(sr)))
    }

    @Test("A range already pushed out of the ring falls back to the saved audio")
    func evictedFromRing() {
        let ring = ring(seconds: 10, filledSeconds: 40)
        let range = QuestionAudioRange()
        let s = Int64(2 * sr), e = Int64(5 * sr)
        range.record(utterance: 1, start: s, end: e, audio: [Float](repeating: 0.1, count: Int(e - s)))
        let audio = range.audio(for: [1], ring: ring)
        #expect(audio?.source == .joined)
        #expect(audio?.samples.count == 3 * sr)
    }

    @Test("Rehearsal: owner phrases never enter the question audio")
    func ownerPhrasesExcluded() {
        let ring = ring(filledSeconds: 20)
        let range = QuestionAudioRange()
        phrase(range, 1, 1, 3, ring: ring)
        phrase(range, 2, 4, 6, ring: ring)
        phrase(range, 3, 7, 9, ring: ring)
        range.setRoute(utterance: 1, owner: false)
        range.setRoute(utterance: 2, owner: true)
        range.setRoute(utterance: 3, owner: false)
        let audio = range.audio(for: [1, 2, 3], ring: ring)
        #expect(audio?.source == .joined)
        #expect(audio?.utterances == [1, 3])
        #expect(audio?.samples.count == 4 * sr + Int(0.15 * Double(sr)))
    }

    @Test("Released and dropped phrases free their audio; unknown phrases give nil")
    func release() {
        let ring = ring(filledSeconds: 10)
        let range = QuestionAudioRange()
        phrase(range, 1, 1, 3, ring: ring)
        phrase(range, 2, 4, 6, ring: ring)
        #expect(range.storedCount == 2)
        range.drop(utterance: 2)
        range.release(utterances: [1])
        #expect(range.storedCount == 0)
        #expect(range.audio(for: [1], ring: ring) == nil)
    }

    @Test("Stored audio is bounded in memory")
    func bounded() {
        let range = QuestionAudioRange(maxStoredSeconds: 10)
        for u in 1...6 { range.record(utterance: u, start: 0, end: 1, audio: [Float](repeating: 0, count: 4 * 16_000)) }
        #expect(range.storedCount == 2)
    }
}
