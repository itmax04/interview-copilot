import Foundation
import Testing
@testable import CopilotCore

@Suite("COPILOT-15 P-04 — QuestionRedecoder (AC-05)")
struct TurnRedecodeTests {
    private func feed(_ t: StreamingTranscriber, _ buffer: AudioRingBuffer, _ samples: [Float]) {
        var i = 0
        while i < samples.count {
            let chunk = Array(samples[i..<min(i + 320, samples.count)])
            buffer.append(chunk)
            t.process(chunk)
            i += 320
        }
    }

    private func twoPhrases() async -> (StreamingTranscriber, AudioRingBuffer, FakeRecognizer) {
        let buffer = AudioRingBuffer(seconds: 30)
        let fake = FakeRecognizer()
        let sink = EventSink()
        var config = StreamingTranscriber.Config()
        config.allowRevision = false
        let t = StreamingTranscriber(recognizer: fake, buffer: buffer, config: config) { sink.add($0) }
        t.setLanguage("uk")
        feed(t, buffer, EnergyVADTests.noise(ms: 300, amplitude: 0.001))
        for _ in 0..<2 {
            feed(t, buffer, EnergyVADTests.tone(ms: 1500, amplitude: 0.3))
            feed(t, buffer, EnergyVADTests.noise(ms: 700, amplitude: 0.001))
        }
        _ = await sink.waitFor { $0.filter { if case .final = $0 { true } else { false } }.count == 2 }
        return (t, buffer, fake)
    }

    @Test("The re-decode runs one pass over the whole question audio and returns that text")
    func wholeQuestionPass() async {
        let (t, _, fake) = await twoPhrases()
        let before = fake.transcribeCalls.count
        fake.text = "полный вопрос целиком"
        let result = await t.redecodeQuestion(utterances: [1, 2], turn: 1, provisional: "пол вопрос")
        #expect(result?.text == "полный вопрос целиком")
        #expect(result?.source == .ring)
        #expect(fake.transcribeCalls.count == before + 1)
        // Звук обеих фраз и паузы между ними (> одной фразы, 1,5 с + 0,3 с pre-roll).
        #expect((fake.transcribeCalls.last?.samples ?? 0) > 16_000 * 3)
        #expect(fake.transcribeCalls.last?.reducedContext == false)
    }

    @Test("The result is cached per utterance list so the draft and the turn see the same text")
    func cached() async {
        let (t, _, fake) = await twoPhrases()
        fake.text = "первый результат"
        let first = await t.redecodeQuestion(utterances: [1, 2], turn: 1, provisional: "x")
        let calls = fake.transcribeCalls.count
        fake.text = "другой результат"
        let second = await t.redecodeQuestion(utterances: [1, 2], turn: 2, provisional: "x")
        #expect(second == first)
        #expect(fake.transcribeCalls.count == calls)
    }

    @Test("Unknown phrases (no audio) fall back: nil")
    func noAudio() async {
        let (t, _, _) = await twoPhrases()
        let result = await t.redecodeQuestion(utterances: [41, 42], turn: 1, provisional: "x")
        #expect(result == nil)
    }

    @Test("Audio is released after the turn used it")
    func released() async {
        let (t, _, _) = await twoPhrases()
        _ = await t.redecodeQuestion(utterances: [1, 2], turn: 1, provisional: "x", release: true)
        #expect(t.questionRanges.storedCount == 0)
    }

    @Test("A pass over the budget gives nil, the failure never blocks")
    func overBudget() async {
        let fake = FakeRecognizer()
        fake.delay = 1.5
        var config = QuestionRedecoder.Config()
        config.budget = 0.1
        let redecoder = QuestionRedecoder(recognizer: fake, config: config)
        let audio = QuestionAudio(samples: [Float](repeating: 0.1, count: 16_000), source: .joined, utterances: [1])
        let started = Date()
        let result = await redecoder.run(audio, language: nil, turn: 1, provisionalWords: 3)
        #expect(result == nil)
        #expect(Date().timeIntervalSince(started) < 1.0)
    }

    @Test("Empty text is a failure")
    func emptyText() async {
        let fake = FakeRecognizer()
        fake.text = ""
        let redecoder = QuestionRedecoder(recognizer: fake)
        let audio = QuestionAudio(samples: [Float](repeating: 0.1, count: 16_000), source: .ring, utterances: [1])
        #expect(await redecoder.run(audio, language: nil, turn: 1, provisionalWords: 3) == nil)
    }
}
