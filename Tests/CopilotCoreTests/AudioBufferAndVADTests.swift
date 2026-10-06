import Foundation
import Testing
@testable import CopilotCore

@Suite("AudioRingBuffer — R-04")
struct AudioRingBufferTests {
    @Test func capacityNeverExceeds30Seconds() {
        let b = AudioRingBuffer(seconds: 30, sampleRate: 16_000)
        #expect(b.capacity == 480_000)
        b.append([Float](repeating: 0.1, count: 500_000))
        #expect(b.endPosition == 500_000)
        #expect(b.startPosition == 20_000)
        #expect(b.read(from: 0).count == 480_000)
    }

    @Test func readRangesAndWrapAround() {
        let b = AudioRingBuffer(seconds: 0.001, sampleRate: 10_000) // 10 сэмплов
        b.append((0..<7).map(Float.init))
        b.append((7..<15).map(Float.init))
        #expect(b.startPosition == 5)
        #expect(b.read(from: 0) == (5..<15).map(Float.init))
        #expect(b.read(from: 10, to: 12) == [10, 11])
        #expect(b.latest(seconds: 0.0003) == [12, 13, 14])
        #expect(b.read(from: 20).isEmpty)
    }

    @Test func clear() {
        let b = AudioRingBuffer(seconds: 1, sampleRate: 100)
        b.append([1, 2, 3])
        b.clear()
        #expect(b.endPosition == 0)
        #expect(b.read(from: 0).isEmpty)
    }
}

@Suite("EnergyVAD — R-02")
struct EnergyVADTests {
    static func tone(ms: Int, amplitude: Float, sampleRate: Int = 16_000) -> [Float] {
        let n = sampleRate * ms / 1000
        return (0..<n).map { amplitude * sin(2 * .pi * 220 * Float($0) / Float(sampleRate)) }
    }

    static func noise(ms: Int, amplitude: Float, sampleRate: Int = 16_000) -> [Float] {
        var rng = SystemRandomNumberGenerator()
        return (0..<(sampleRate * ms / 1000)).map { _ in Float.random(in: -amplitude...amplitude, using: &rng) }
    }

    @Test func silenceIsNotSpeech() {
        var vad = EnergyVAD()
        vad.process([Float](repeating: 0, count: 16_000))
        #expect(!vad.isSpeech)
    }

    @Test func speechStartsAndEndsWithHangover() {
        var vad = EnergyVAD()
        var changes = vad.process(Self.noise(ms: 500, amplitude: 0.001))
        #expect(changes.isEmpty)
        changes = vad.process(Self.tone(ms: 400, amplitude: 0.3))
        #expect(changes == [true])
        #expect(vad.isSpeech)
        // Короче удержания (300 мс) — речь продолжается.
        changes = vad.process(Self.noise(ms: 200, amplitude: 0.001))
        #expect(changes.isEmpty)
        #expect(vad.isSpeech)
        changes = vad.process(Self.noise(ms: 200, amplitude: 0.001))
        #expect(changes == [false])
        #expect(!vad.isSpeech)
    }

    @Test func shortClickIsIgnored() {
        var vad = EnergyVAD()
        vad.process(Self.noise(ms: 300, amplitude: 0.001))
        let changes = vad.process(Self.tone(ms: 40, amplitude: 0.5) + Self.noise(ms: 300, amplitude: 0.001))
        #expect(changes.isEmpty)
    }

    @Test func steadyNoiseIsNotSpeech() {
        // Постоянный фон (вентилятор) поднимает уровень шума и не считается речью.
        var vad = EnergyVAD()
        vad.process(Self.noise(ms: 3000, amplitude: 0.02))
        #expect(!vad.isSpeech)
    }

    @Test func longSpeechWithShortGapsStaysSpeech() {
        // 5 с «слогов» по 200 мс с паузами 60 мс: одна непрерывная реплика, без ложного конца.
        var vad = EnergyVAD()
        vad.process(Self.noise(ms: 300, amplitude: 0.001))
        var changes: [Bool] = []
        for _ in 0..<19 {
            changes += vad.process(Self.tone(ms: 200, amplitude: 0.2) + Self.noise(ms: 60, amplitude: 0.001))
        }
        #expect(changes == [true])
        #expect(vad.isSpeech)
    }

    @Test func rmsDB() {
        #expect(EnergyVAD.rmsDB([][...]) == -120)
        let db = EnergyVAD.rmsDB([Float](repeating: 0.5, count: 100)[...])
        #expect(abs(db - (-6.02)) < 0.1)
    }
}
