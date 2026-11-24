import Foundation
import Testing
@testable import CopilotCore

/// COPILOT-18: «Микрофон выкл.» — чистая логика (отрезки, настройка, метки истории и разбора, хоткей, пауза без отмены движка).
@Suite("Микрофон выкл. — COPILOT-18")
struct OwnerMicToggleTests {
    private let start = Date(timeIntervalSince1970: 1_792_400_000)
    private func at(_ s: Double) -> Date { start.addingTimeInterval(s) }

    // MARK: AC-02 отрезки

    @Test func intervalOpensAndClosesOnToggle() {
        var v: [MicMutedInterval] = []
        MicMutedInterval.apply(muted: true, at: at(10), to: &v)
        #expect(v == [MicMutedInterval(start: at(10), end: nil)])
        MicMutedInterval.apply(muted: true, at: at(12), to: &v)         // повтор того же состояния — без изменений
        #expect(v.count == 1)
        MicMutedInterval.apply(muted: false, at: at(40), to: &v)
        #expect(v == [MicMutedInterval(start: at(10), end: at(40))])
        MicMutedInterval.apply(muted: false, at: at(50), to: &v)        // уже включён
        #expect(v.count == 1 && v[0].end == at(40))
        MicMutedInterval.apply(muted: true, at: at(60), to: &v)
        MicMutedInterval.close(&v, at: at(90))                          // конец сессии закрывает открытый отрезок
        #expect(v.count == 2 && v[1].end == at(90))
    }

    @Test func intervalContains() {
        let v = [MicMutedInterval(start: at(10), end: at(20)), MicMutedInterval(start: at(30), end: nil)]
        #expect(MicMutedInterval.contains(at(15), in: v))
        #expect(!MicMutedInterval.contains(at(25), in: v))
        #expect(MicMutedInterval.contains(at(500), in: v))
    }

    // MARK: AC-01 настройка

    @Test func voiceClarificationIsOffByDefaultAndOldFilesLoad() throws {
        #expect(AppSettings().ownerVoiceClarification == false)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"schemaVersion":4}"#.utf8))
        #expect(old.ownerVoiceClarification == false)
        var s = AppSettings()
        s.ownerVoiceClarification = true
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back.ownerVoiceClarification == true)
    }

    // MARK: AC-07 история и разбор

    private func record() -> SessionRecord {
        var r = SessionRecord(id: "s", startedAt: start, source: "Meet")
        r.utterances = [.init(id: 1, text: "Расскажите о проекте?", language: "ru", at: at(5))]
        r.ownerUtterances = [.init(id: 1, text: "Это был платёжный сервис.", language: "", at: at(60))]
        r.micMutedIntervals = [MicMutedInterval(start: at(20), end: at(50))]
        return r
    }

    @Test func timelineMarksMutedInterval() {
        let t = record().timeline
        let m = t.first { $0.speaker == .micOff }
        #expect(m != nil)
        #expect(m?.clock == "0:20")
        #expect(m?.mutedRange == "0:20–0:50")
        #expect(t.map(\.speaker) == [.interviewer, .micOff, .owner])
        var open = record()
        open.micMutedIntervals = [MicMutedInterval(start: at(20), end: nil)]
        #expect(open.timeline.first { $0.speaker == .micOff }?.mutedRange == "0:20–…")
    }

    @Test func reviewTranscriptSaysTheMicWasOffNotSilent() {
        let text = ReviewPrompt.transcriptText(record(), redactPII: false)
        #expect(text.contains("microphone was switched off"))
        #expect(text.contains("[0:20]"))
        #expect(text.contains("until 0:50"))
        // Без отрезков разбор прежний.
        var plain = record()
        plain.micMutedIntervals = []
        #expect(!ReviewPrompt.transcriptText(plain, redactPII: false).contains("switched off"))
    }

    @Test func oldSessionFilesWithoutIntervalsLoad() throws {
        let r = SessionRecord(id: "s", startedAt: start, source: nil)
        var data = try JSONEncoder().encode(r)
        var obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        obj.removeValue(forKey: "micMutedIntervals")
        data = try JSONSerialization.data(withJSONObject: obj)
        let back = try JSONDecoder().decode(SessionRecord.self, from: data)
        #expect(back.micMutedIntervals.isEmpty)
    }

    @Test func intervalsAreTimesOnly() throws {
        let data = try JSONEncoder().encode(MicMutedInterval(start: at(1), end: at(2)))
        let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys.sorted()
        #expect(keys == ["end", "start"])
    }

    // MARK: AC-04 хоткей

    @Test func hotkeyDefaults() {
        #expect(HotkeyBinding.defaults[.toggleMic]?.displayString == "⌃⌥M")
        #expect(HotkeyBinding.sessionDefaults[.toggleMic]?.displayString == "⇧⌘M")
        #expect(HotkeyAction.allCases.last == .toggleMic)
        #expect(HotkeyAction.allCases.firstIndex(of: .nextAnswer) == HotkeyAction.allCases.count - 2)
    }

    @Test func speakingSignalReturnsWhenMicIsReenabledMidPhrase() {
        var g = OwnerSpeakingGate()
        #expect(g.detector(true, current: false) == true)       // говорит, микрофон включён
        #expect(g.setOff(true, current: true) == false)         // выключили: сигнал гасится
        #expect(g.detector(false, current: false) == nil)       // пауза/речь при выключенном — ничего не сообщаем
        #expect(g.detector(true, current: false) == nil)
        #expect(g.setOff(false, current: false) == true)        // включили посреди фразы — сигнал сразу возвращается
        #expect(g.detector(false, current: true) == false)
        #expect(g.setOff(true, current: false) == nil)
        #expect(g.setOff(false, current: false) == nil)         // не говорил — нечего возвращать
    }

    // MARK: AC-03 пауза владельца не отменяет общий движок

    @Test func ownerPauseCanLeaveTheSharedEngineAlone() {
        let engine = CancelCounter()
        let t = StreamingTranscriber(recognizer: engine, buffer: AudioRingBuffer(seconds: 5), config: .init()) { _ in }
        t.setPaused(true, cancelRecognizer: false)
        #expect(engine.cancels == 0)
        t.setPaused(false)
        t.setPaused(true)
        #expect(engine.cancels == 1)
    }
}

private final class CancelCounter: SpeechRecognizer, @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var cancels: Int { lock.withLock { n } }
    func transcribe(_ samples: [Float], language: String?, prompt: String?, reducedContext: Bool) throws -> Transcription {
        Transcription(text: "", language: language ?? "uk", languageProbabilities: [:], audioSeconds: 0, elapsedMs: 0,
                      noSpeechProbability: 0, averageTokenProbability: 0)
    }
    func detectLanguage(_ samples: [Float]) throws -> (String, [String: Float]) { ("uk", ["uk": 1]) }
    func cancel() { lock.withLock { n += 1 } }
}
