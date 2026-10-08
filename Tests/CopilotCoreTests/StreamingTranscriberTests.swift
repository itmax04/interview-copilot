import Foundation
import Testing
@testable import CopilotCore

/// Подменный распознаватель: возвращает длину звука и язык, считает вызовы.
final class FakeRecognizer: SpeechRecognizer, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(samples: Int, language: String?, reducedContext: Bool, peak: Float)] = []
    var transcribeCalls: [(samples: Int, language: String?, reducedContext: Bool, peak: Float)] { lock.withLock { calls } }
    private(set) var detectCalls = 0
    var nativeMultilingual = false
    var detected = "uk"
    var text = "привіт"
    /// Средняя вероятность токенов по языку (для выбора uk/ru).
    var tokenProbability: [String: Float] = ["uk": 0.9, "ru": 0.7, "en": 0.6]

    /// Задержка распознавания (имитация модели), с.
    var delay: Double = 0

    func transcribe(_ samples: [Float], language: String?, prompt: String?, reducedContext: Bool) throws -> Transcription {
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        lock.withLock { calls.append((samples.count, language, reducedContext, samples.map { abs($0) }.max() ?? 0)) }
        let lang = language ?? detected
        return Transcription(text: text, language: lang, languageProbabilities: [:],
                             audioSeconds: Double(samples.count) / 16_000, elapsedMs: 1, noSpeechProbability: 0,
                             averageTokenProbability: tokenProbability[lang] ?? 0)
    }

    func detectLanguage(_ samples: [Float]) throws -> (String, [String: Float]) {
        lock.withLock { detectCalls += 1 }
        return (detected, [detected: 0.99])
    }

    func cancel() {}
}

final class EventSink: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [TranscriptEvent] = []
    var events: [TranscriptEvent] { lock.withLock { _events } }
    func add(_ e: TranscriptEvent) { lock.withLock { _events.append(e) } }

    func waitFor(_ predicate: ([TranscriptEvent]) -> Bool, timeout: Double = 3) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate(events) { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return predicate(events)
    }
}

@Suite("StreamingTranscriber — R-03, R-04")
struct StreamingTranscriberTests {
    /// Подаёт сигнал кусками по 20 мс, как настоящий захват.
    func feed(_ t: StreamingTranscriber, _ buffer: AudioRingBuffer, _ samples: [Float]) {
        var i = 0
        while i < samples.count {
            let chunk = Array(samples[i..<min(i + 320, samples.count)])
            buffer.append(chunk)
            t.process(chunk)
            i += 320
        }
    }

    func make(language: String? = nil, sticky: Bool = false) -> (StreamingTranscriber, AudioRingBuffer, FakeRecognizer, EventSink) {
        let buffer = AudioRingBuffer(seconds: 30)
        let fake = FakeRecognizer()
        let sink = EventSink()
        var config = StreamingTranscriber.Config()
        config.partialInterval = 0.5
        config.stickyLanguage = sticky
        let t = StreamingTranscriber(recognizer: fake, buffer: buffer, config: config) { sink.add($0) }
        t.setLanguage(language)
        return (t, buffer, fake, sink)
    }

    @Test func utteranceProducesStartPartialAndFinal() async {
        let (t, buffer, fake, sink) = make()
        feed(t, buffer, EnergyVADTests.noise(ms: 300, amplitude: 0.001))
        feed(t, buffer, EnergyVADTests.tone(ms: 2000, amplitude: 0.3))
        // Даём первой задаче освободить очередь, затем приходят новые сэмплы настоящего потока.
        try? await Task.sleep(for: .milliseconds(50))
        feed(t, buffer, EnergyVADTests.tone(ms: 500, amplitude: 0.3))
        #expect(await sink.waitFor { $0.contains { if case .partial = $0 { true } else { false } } })
        feed(t, buffer, EnergyVADTests.noise(ms: 600, amplitude: 0.001))
        let ok = await sink.waitFor { $0.contains { if case .final = $0 { true } else { false } } }
        #expect(ok)
        let events = sink.events
        #expect(events.first == .speechStarted(utterance: 1))
        #expect(events.contains { if case .partial(1, "привіт") = $0 { true } else { false } })
        #expect(events.contains { if case .speechEnded(1, _) = $0 { true } else { false } })
        guard case .final(let u, let text, let lang, let phraseEnd, let emitted)? = events.last else {
            Issue.record("последним должен быть final"); return
        }
        #expect(u == 1 && text == "привіт" && lang == "uk")
        #expect(emitted >= phraseEnd)
        // Детектор языка — один раз за реплику (дальше только сравнение uk/ru), итог — с известным языком.
        #expect(fake.detectCalls == 1)
        #expect(fake.transcribeCalls.last?.language == "uk")
        // Итог включает всю речь (2,5 с) и предзахват, но не больше буфера.
        let finalSamples = fake.transcribeCalls.last?.samples ?? 0
        #expect(finalSamples >= 40_000 && finalSamples <= 16_000 * 4)
    }

    @Test func ukrainianWinsOverRussianByTokenConfidence() {
        let (t, _, fake, _) = make()
        fake.detected = "ru" // детектор ошибся
        fake.tokenProbability = ["uk": 0.91, "ru": 0.72]
        let r = t.resolveLanguage([Float](repeating: 0.1, count: 32_000), skipDetector: false)
        #expect(r?.code == "uk")
        #expect(r?.confidence == 1)
        #expect(abs((r?.ukMinusRu ?? 0) - 0.19) < 0.001)
    }

    @Test func closeScoresAreNotConfident() {
        let (t, _, fake, _) = make()
        fake.tokenProbability = ["uk": 0.80, "ru": 0.78]
        #expect(t.resolveLanguage([Float](repeating: 0.1, count: 32_000), skipDetector: false)?.confidence == 0.5)
    }

    @Test func englishSkipsUkRuComparison() {
        let (t, _, fake, _) = make()
        fake.detected = "en"
        let r = t.resolveLanguage([Float](repeating: 0.1, count: 32_000), skipDetector: false)
        #expect(r?.code == "en")
        #expect(r?.ukMinusRu == nil)
        #expect(fake.transcribeCalls.isEmpty)
    }

    @Test func stickyLanguageAfterTwoConfidentUtterances() async {
        let (t, buffer, fake, sink) = make(sticky: true)
        fake.detected = "en"
        fake.tokenProbability["en"] = 0.95 // уверенное распознавание
        for i in 1...4 {
            feed(t, buffer, EnergyVADTests.noise(ms: 300, amplitude: 0.001))
            feed(t, buffer, EnergyVADTests.tone(ms: 2000, amplitude: 0.3))
            feed(t, buffer, EnergyVADTests.noise(ms: 600, amplitude: 0.001))
            #expect(await sink.waitFor { events in events.filter { if case .final = $0 { true } else { false } }.count == i })
        }
        // Детектор — только в первых двух репликах, дальше язык разговора.
        #expect(fake.detectCalls == 2)
    }

    @Test func explicitLanguageSkipsDetection() async {
        let (t, buffer, fake, sink) = make(language: "ru")
        feed(t, buffer, EnergyVADTests.noise(ms: 300, amplitude: 0.001))
        feed(t, buffer, EnergyVADTests.tone(ms: 1500, amplitude: 0.3))
        feed(t, buffer, EnergyVADTests.noise(ms: 600, amplitude: 0.001))
        #expect(await sink.waitFor { $0.contains { if case .final = $0 { true } else { false } } })
        #expect(fake.detectCalls == 0)
        #expect(fake.transcribeCalls.allSatisfy { $0.language == "ru" })
    }

    @Test func silenceProducesNothing() async {
        let (t, buffer, fake, sink) = make()
        feed(t, buffer, EnergyVADTests.noise(ms: 2000, amplitude: 0.001))
        try? await Task.sleep(for: .milliseconds(200))
        #expect(sink.events.isEmpty)
        #expect(fake.transcribeCalls.isEmpty)
    }

    @Test func pauseDropsCurrentUtterance() async {
        let (t, buffer, fake, sink) = make(language: "en")
        feed(t, buffer, EnergyVADTests.noise(ms: 300, amplitude: 0.001))
        feed(t, buffer, EnergyVADTests.tone(ms: 300, amplitude: 0.3))
        t.setPaused(true)
        feed(t, buffer, EnergyVADTests.tone(ms: 1000, amplitude: 0.3) + EnergyVADTests.noise(ms: 600, amplitude: 0.001))
        try? await Task.sleep(for: .milliseconds(200))
        #expect(!sink.events.contains { if case .final = $0 { true } else { false } })
        #expect(fake.transcribeCalls.isEmpty)
    }

    @Test func pauseRightAfterPhraseDropsQueuedFinal() async {
        // Ревью P-13: итог, поставленный в очередь до паузы, не выдаётся (S-08).
        let (t, buffer, fake, sink) = make(language: "ru")
        fake.delay = 0.3
        feed(t, buffer, EnergyVADTests.noise(ms: 300, amplitude: 0.001))
        feed(t, buffer, EnergyVADTests.tone(ms: 1500, amplitude: 0.3))
        feed(t, buffer, EnergyVADTests.noise(ms: 400, amplitude: 0.001)) // фраза закончилась → итог в очереди
        t.setPaused(true)
        try? await Task.sleep(for: .milliseconds(1500))
        #expect(!sink.events.contains { if case .final = $0 { true } else { false } })
    }

    @Test func twoUtterancesAreNumbered() async {
        let (t, buffer, _, sink) = make(language: "en")
        for _ in 0..<2 {
            feed(t, buffer, EnergyVADTests.noise(ms: 300, amplitude: 0.001))
            feed(t, buffer, EnergyVADTests.tone(ms: 800, amplitude: 0.3))
            feed(t, buffer, EnergyVADTests.noise(ms: 500, amplitude: 0.001))
        }
        #expect(await sink.waitFor { events in events.filter { if case .final = $0 { true } else { false } }.count == 2 })
        let finals = sink.events.compactMap { e -> Int? in if case .final(let u, _, _, _, _) = e { u } else { nil } }
        #expect(finals == [1, 2])
    }
    @Test func queuedFinalKeepsAudioAndLanguageAfterBufferWraps() async {
        let (t, buffer, fake, sink) = make(language: "en")
        fake.delay = 0.3
        feed(t, buffer, EnergyVADTests.noise(ms: 300, amplitude: 0.001))
        feed(t, buffer, EnergyVADTests.tone(ms: 1500, amplitude: 0.3))
        feed(t, buffer, EnergyVADTests.noise(ms: 600, amplitude: 0.001))
        t.setLanguage("ru")
        feed(t, buffer, EnergyVADTests.tone(ms: 1500, amplitude: 0.3))
        feed(t, buffer, EnergyVADTests.noise(ms: 600, amplitude: 0.001))
        // Новые 31 с вытесняют обе фразы, пока модель занята. Итоги обязаны сохранить их звук.
        buffer.append([Float](repeating: 0, count: 31 * 16_000))
        #expect(await sink.waitFor { $0.filter { if case .final = $0 { true } else { false } }.count == 2 })
        let languages = sink.events.compactMap { e -> String? in
            if case .final(_, _, let language, _, _) = e { language } else { nil }
        }
        #expect(languages == ["en", "ru"])
        let finals = fake.transcribeCalls.filter { !$0.reducedContext }
        #expect(finals.count == 2)
        #expect(finals.allSatisfy { $0.samples >= 24_000 && $0.peak > 0.25 })
    }

    @Test func oneAudioBlockCanContainTwoCompleteUtterances() async {
        let (t, buffer, fake, sink) = make(language: "en")
        let phrase = EnergyVADTests.tone(ms: 800, amplitude: 0.3)
            + EnergyVADTests.noise(ms: 600, amplitude: 0.001)
        let audio = EnergyVADTests.noise(ms: 300, amplitude: 0.001) + phrase + phrase
        buffer.append(audio)
        t.process(audio)
        #expect(await sink.waitFor { $0.filter { if case .final = $0 { true } else { false } }.count == 2 })
        let calls = fake.transcribeCalls
        #expect(calls.count == 2)
        #expect(calls.allSatisfy { $0.samples > 12_800 && $0.samples < 24_000 })
        #expect(!calls.contains { $0.reducedContext })
        #expect(sink.events.prefix(4).map { e -> String in
            switch e {
            case .speechStarted(let u): "start\(u)"
            case .speechEnded(let u, _): "end\(u)"
            default: "text"
            }
        } == ["start1", "end1", "start2", "end2"])
    }

    @Test func fastModeCanStillUseReducedFinalContext() async {
        let buffer = AudioRingBuffer(seconds: 30)
        let fake = FakeRecognizer()
        let sink = EventSink()
        var config = StreamingTranscriber.Config()
        config.finalReducedContext = true
        config.partialInterval = 100
        let t = StreamingTranscriber(recognizer: fake, buffer: buffer, config: config) { sink.add($0) }
        t.setLanguage("en")
        feed(t, buffer, EnergyVADTests.noise(ms: 300, amplitude: 0.001))
        feed(t, buffer, EnergyVADTests.tone(ms: 800, amplitude: 0.3))
        feed(t, buffer, EnergyVADTests.noise(ms: 600, amplitude: 0.001))
        #expect(await sink.waitFor { $0.contains { if case .final = $0 { true } else { false } } })
        #expect(fake.transcribeCalls.count == 1)
        #expect(fake.transcribeCalls.first?.reducedContext == true)
    }

    @Test func nativeMultilingualDoesNotRunWhisperLanguageComparison() async {
        let (t, buffer, fake, sink) = make()
        fake.nativeMultilingual = true
        feed(t, buffer, EnergyVADTests.noise(ms: 300, amplitude: 0.001))
        feed(t, buffer, EnergyVADTests.tone(ms: 2200, amplitude: 0.3))
        feed(t, buffer, EnergyVADTests.noise(ms: 600, amplitude: 0.001))
        #expect(await sink.waitFor { $0.contains { if case .final = $0 { true } else { false } } })
        #expect(fake.detectCalls == 0)
        #expect(fake.transcribeCalls.allSatisfy { $0.language == nil })
    }

}
