import Foundation
import Testing
@testable import CopilotCore

/// Репетиция с собеседником в «Микрофон Mac» (живая самопроверка 2026-11-20, вариант C владельца):
/// чужой голос — вопросы и подсказки, голос владельца — ответы без ⌃⌥A. По умолчанию выключено — COPILOT-05 Q13 как был.
@Suite("Маршрут реплик по говорящему — репетиция с собеседником")
struct SpeakerRoutingTests {
    /// Одна фраза 1,5 с между паузами; события — в `sink`.
    func runPhrase(gate: StreamingTranscriber.VoiceCheck?, recognizer: any SpeechRecognizer = SlowRevisionRecognizer(revisionDelay: 0))
        async -> EventSink {
        let buffer = AudioRingBuffer(seconds: 30)
        let sink = EventSink()
        var config = StreamingTranscriber.Config()
        config.partialInterval = 10
        let t = StreamingTranscriber(recognizer: recognizer, buffer: buffer, config: config) { sink.add($0) }
        t.setLanguage("uk")
        t.setVoiceGate(gate)
        for chunk in [EnergyVADTests.noise(ms: 300, amplitude: 0.001), EnergyVADTests.tone(ms: 1500, amplitude: 0.3),
                      EnergyVADTests.noise(ms: 700, amplitude: 0.001)] {
            var i = 0
            while i < chunk.count {
                let part = Array(chunk[i..<min(i + 320, chunk.count)])
                buffer.append(part)
                t.process(part)
                i += 320
            }
        }
        _ = await sink.waitFor { events in
            events.contains { if case .final = $0 { true } else if case .foreignVoice = $0 { true } else { false } }
        }
        return sink
    }

    func index(_ events: [TranscriptEvent], _ match: (TranscriptEvent) -> Bool) -> Int? { events.firstIndex(where: match) }

    // MARK: Распознавание: вердикт на событии, итог и уточнение не теряются

    @Test func rejectedVoiceInRehearsalBecomesFinal() async throws {
        let sink = await runPhrase(gate: { _ in VoiceVerdict(similarity: 0.40, accepted: false, routeBySpeaker: true) })
        let events = sink.events
        let speaker = try #require(index(events) { if case .speaker(_, false, 0.40) = $0 { true } else { false } })
        let final = try #require(index(events) { if case .final(_, "черновик", _, _, _) = $0 { true } else { false } })
        #expect(speaker < final)
        #expect(!events.contains { if case .foreignVoice = $0 { true } else { false } })
    }

    @Test func acceptedVoiceInRehearsalIsMarkedOwner() async throws {
        let sink = await runPhrase(gate: { _ in VoiceVerdict(similarity: 0.66, accepted: true, routeBySpeaker: true) })
        let events = sink.events
        let speaker = try #require(index(events) { if case .speaker(_, true, 0.66) = $0 { true } else { false } })
        let final = try #require(index(events) { if case .final = $0 { true } else { false } })
        #expect(speaker < final)
    }

    @Test func phraseWithoutVerdictHasNoSpeaker() async {
        let sink = await runPhrase(gate: { _ in nil })   // < 0,5 с речи или CAM++ не загружена
        #expect(sink.events.contains { if case .final = $0 { true } else { false } })
        #expect(!sink.events.contains { if case .speaker = $0 { true } else { false } })
    }

    @Test func settingOffKeepsFilterBehavior() async {
        // Отклонённый голос — `foreignVoice` вместо итога, без уточнения (COPILOT-05 R-03, как раньше).
        let rejected = await runPhrase(gate: { _ in VoiceVerdict(similarity: 0.40, accepted: false) })
        #expect(rejected.events.contains { if case .foreignVoice(_, "черновик", 0.40, _) = $0 { true } else { false } })
        #expect(!rejected.events.contains { if case .final = $0 { true } else { false } })
        // Принятый — обычный итог, поток событий тот же, что до режима репетиции.
        let accepted = await runPhrase(gate: { _ in VoiceVerdict(similarity: 0.66, accepted: true) })
        #expect(accepted.events.contains { if case .final = $0 { true } else { false } })
        #expect(!accepted.events.contains { if case .speaker = $0 { true } else { false } })
    }

    // MARK: Проверка голоса: режим только там, где разрешён

    @Test func gateVerdictCarriesRoutingOnlyWhenAllowed() {
        var state = VoiceGateBox.State()
        state.print = VoicePrint(embedding: [1], speechSeconds: 20, selfSimilarityMin: 0.80)   // порог 0,72
        state.routeBySpeaker = true
        let mic = VoiceGateBox.verdict(similarity: 0.40, speechSeconds: 2, state: state, allowRouting: true)
        #expect(mic == VoiceVerdict(similarity: 0.40, accepted: false, routeBySpeaker: true))
        // Микрофон на созвоне (канал владельца) — чужой голос всегда отбрасывается.
        let call = VoiceGateBox.verdict(similarity: 0.40, speechSeconds: 2, state: state, allowRouting: false)
        #expect(call?.routeBySpeaker == false)
        state.routeBySpeaker = false
        #expect(VoiceGateBox.verdict(similarity: 0.80, speechSeconds: 2, state: state, allowRouting: true)
                == VoiceVerdict(similarity: 0.80, accepted: true, routeBySpeaker: false))
        // Короткая фраза — мягче порог (0,72 − 0,1).
        #expect(VoiceGateBox.verdict(similarity: 0.65, speechSeconds: 0.7, state: state, allowRouting: true)?.accepted == true)
    }

    // MARK: Приложение: вопрос или ответ владельца

    @Test func rehearsalRoutesBySpeaker() {
        var router = SpeakerRouter(rehearsal: true)
        router.noteSpeaker(utterance: 1, owner: false)
        router.noteSpeaker(utterance: 2, owner: true)
        #expect(router.route(utterance: 1, ownerAnswering: false) == .question)      // чужой голос → вопрос, подсказка
        #expect(router.route(utterance: 2, ownerAnswering: false) == .ownerAnswer)   // свой → ответ без ⌃⌥A
    }

    @Test func phraseWithoutVerdictFollowsOwnerAnsweringState() {
        let router = SpeakerRouter(rehearsal: true)
        #expect(router.route(utterance: 3, ownerAnswering: false) == .question)
        #expect(router.route(utterance: 3, ownerAnswering: true) == .ownerAnswer)
    }

    @Test func ownerAnsweringIsManualOverride() {
        var router = SpeakerRouter(rehearsal: true)
        router.noteSpeaker(utterance: 1, owner: false)   // порог ошибся на голосе владельца — ⌃⌥A всё равно ответ
        #expect(router.route(utterance: 1, ownerAnswering: true) == .ownerAnswer)
    }

    @Test func settingOffKeepsSelfTestRouting() {
        var router = SpeakerRouter(rehearsal: false)
        router.noteSpeaker(utterance: 1, owner: true)
        // COPILOT-05 Q13: владелец сам читает вопросы; ответ — только по ⌃⌥A.
        #expect(router.route(utterance: 1, ownerAnswering: false) == .question)
        #expect(router.route(utterance: 1, ownerAnswering: true) == .ownerAnswer)
    }

    @Test func verdictIsForgottenAndBounded() {
        var router = SpeakerRouter(rehearsal: true)
        router.noteSpeaker(utterance: 1, owner: true)
        router.forget(utterance: 1)
        #expect(router.route(utterance: 1, ownerAnswering: false) == .question)
        for u in 10..<(10 + SpeakerRouter.capacity + 5) { router.noteSpeaker(utterance: u, owner: true) }
        #expect(router.route(utterance: 10, ownerAnswering: false) == .question)   // старейший вытеснен
        #expect(router.route(utterance: 10 + SpeakerRouter.capacity + 4, ownerAnswering: false) == .ownerAnswer)
        router.reset()
        #expect(router.route(utterance: 10 + SpeakerRouter.capacity + 4, ownerAnswering: false) == .question)
    }

    // MARK: Настройка

    @Test func settingIsOffByDefaultAndOldSettingsLoad() throws {
        #expect(!AppSettings().rehearsalWithInterviewer)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"ownerVoiceOnly":true}"#.utf8))
        #expect(!old.rehearsalWithInterviewer && old.ownerVoiceOnly)
        var s = AppSettings()
        s.rehearsalWithInterviewer = true
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s)).rehearsalWithInterviewer)
    }
}
