import Foundation
import Testing
@testable import CopilotCore

@Suite("COPILOT-15 P-11 — owner channel (AC-09) and fallback B")
struct OwnerAnswerRedecodeTests {
    private func feed(_ t: StreamingTranscriber, _ buffer: AudioRingBuffer, _ samples: [Float]) {
        var i = 0
        while i < samples.count {
            let chunk = Array(samples[i..<min(i + 320, samples.count)])
            buffer.append(chunk)
            t.process(chunk)
            i += 320
        }
    }

    // MARK: assembler

    @Test("Phrases join into one answer after the owner pause")
    func assemblesAfterPause() {
        var a = OwnerAnswerAssembler(pauseMs: 1000)
        a.phraseFinal(text: "перша частина", utterance: 4, speechEnd: 1000)
        #expect(a.tick(at: 1500, speaking: false) == nil)
        a.phraseFinal(text: "друга частина", utterance: 5, speechEnd: 2000)
        #expect(a.tick(at: 2900, speaking: false) == nil)
        let answer = a.tick(at: 3000, speaking: false)
        #expect(answer?.utterances == [4, 5])
        #expect(answer?.provisionalText == "перша частина друга частина")
        #expect(!a.hasPending)
    }

    @Test("The answer waits while the owner is still speaking, and reset drops it")
    func waitsWhileSpeaking() {
        var a = OwnerAnswerAssembler(pauseMs: 1000)
        a.phraseFinal(text: "відповідь", utterance: 1, speechEnd: 0)
        #expect(a.tick(at: 5000, speaking: true) == nil)
        #expect(a.tick(at: 5000, speaking: false)?.utterances == [1])
        a.phraseFinal(text: "ще", utterance: 2, speechEnd: 0)
        a.reset()
        #expect(a.tick(at: 9000, speaking: false) == nil)
    }

    // MARK: owner audio, no Whisper

    private func ownerTranscriber(_ fake: any SpeechRecognizer, _ buffer: AudioRingBuffer, config: StreamingTranscriber.Config = .init()) -> (StreamingTranscriber, EventSink) {
        let sink = EventSink()
        var c = config
        c.partialInterval = 3600
        c.vad = StreamingTranscriber.microphoneVAD
        let t = StreamingTranscriber(recognizer: fake, buffer: buffer, config: c) { sink.add($0) }
        t.setLanguage("uk")
        return (t, sink)
    }

    @Test("An owner answer is re-decoded from its own audio range and no Whisper pass runs")
    func ownerAnswerRedecoded() async {
        let buffer = AudioRingBuffer(seconds: 30)
        let rec = SlowRevisionRecognizer(revisionDelay: 0)   // revisionNeeded == true: any revise call would be counted
        let (t, sink) = ownerTranscriber(rec, buffer)
        feed(t, buffer, EnergyVADTests.noise(ms: 300, amplitude: 0.001))
        for _ in 0..<2 {
            feed(t, buffer, EnergyVADTests.tone(ms: 1500, amplitude: 0.3))
            feed(t, buffer, EnergyVADTests.noise(ms: 900, amplitude: 0.001))
        }
        let finals = await sink.waitFor { $0.filter { if case .final = $0 { true } else { false } }.count == 2 }
        #expect(finals)
        let ids = sink.events.compactMap { e -> Int? in if case .final(let u, _, _, _, _) = e { u } else { nil } }
        let result = await t.redecodeQuestion(utterances: ids, turn: -1, provisional: "чернетка чернетка", release: true)
        #expect(result?.text == "черновик")
        #expect((result?.audioMs ?? 0) > 3000)
        #expect(rec.revisions == 0)
        #expect(t.questionRanges.storedCount == 0)   // звук освобождён после использования
    }

    // MARK: fallback B (R-14)

    @Test("hintWaitsForWhisper is off by default: the question text comes from the fast pass only")
    func switchOffByDefault() async {
        let buffer = AudioRingBuffer(seconds: 30)
        let rec = SlowRevisionRecognizer(revisionDelay: 0)
        let (t, sink) = ownerTranscriber(rec, buffer)
        feed(t, buffer, EnergyVADTests.noise(ms: 300, amplitude: 0.001))
        feed(t, buffer, EnergyVADTests.tone(ms: 1500, amplitude: 0.3))
        feed(t, buffer, EnergyVADTests.noise(ms: 900, amplitude: 0.001))
        _ = await sink.waitFor { $0.contains { if case .final = $0 { true } else { false } } }
        let result = await t.redecodeQuestion(utterances: [1], turn: 1, provisional: "x")
        #expect(result?.text == "черновик")
        #expect(rec.revisions == 0)
        #expect(StreamingTranscriber.Config().hintWaitsForWhisper == false)
    }

    @Test("With hintWaitsForWhisper the Whisper text replaces the Parakeet text and the budget is raised")
    func switchOnUsesWhisper() async {
        var config = StreamingTranscriber.Config()
        config.hintWaitsForWhisper = true
        let buffer = AudioRingBuffer(seconds: 30)
        let rec = SlowRevisionRecognizer(revisionDelay: 0)
        let (t, sink) = ownerTranscriber(rec, buffer, config: config)
        feed(t, buffer, EnergyVADTests.noise(ms: 300, amplitude: 0.001))
        feed(t, buffer, EnergyVADTests.tone(ms: 1500, amplitude: 0.3))
        feed(t, buffer, EnergyVADTests.noise(ms: 900, amplitude: 0.001))
        _ = await sink.waitFor { $0.contains { if case .final = $0 { true } else { false } } }
        let result = await t.redecodeQuestion(utterances: [1], turn: 1, provisional: "x")
        #expect(result?.text == "уточнено")
        #expect(rec.revisions >= 1)
        #expect(QuestionRedecoder.Config(waitsForWhisper: true).budget > QuestionRedecoder.Config().budget)
    }

    // MARK: rehearsal (AC-07)

    @Test("Rehearsal: owner phrases are left out of the question audio")
    func rehearsalQuestionExcludesOwner() {
        let ring = AudioRingBuffer(seconds: 30, sampleRate: 16_000)
        ring.append([Float](repeating: 0.1, count: 16_000 * 12))
        let range = QuestionAudioRange()
        func put(_ u: Int, _ s: Int, _ e: Int) {
            range.record(utterance: u, start: Int64(s * 16_000), end: Int64(e * 16_000), audio: ring.read(from: Int64(s * 16_000), to: Int64(e * 16_000)))
        }
        put(1, 0, 3); put(2, 4, 6); put(3, 7, 10)
        range.setRoute(utterance: 2, owner: true)   // голос владельца — ответ, не вопрос
        let audio = range.audio(for: [1, 2, 3], ring: ring)
        #expect(audio?.source == .joined)
        #expect(audio?.samples.count == 6 * 16_000 + Int(0.15 * 16_000))
    }
}
