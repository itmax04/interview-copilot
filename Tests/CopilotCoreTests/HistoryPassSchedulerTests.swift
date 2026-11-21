import Foundation
import Testing
@testable import CopilotCore

/// COPILOT-15 R-07, AC-02: фоновый проход Whisper по истории — один в работе, новый заменяет ожидающий,
/// устаревший (> 8 с в очереди) не запускается, пока идёт реплика — ждёт.
@Suite("HistoryPassScheduler")
struct HistoryPassSchedulerTests {
    final class Harness: @unchecked Sendable {
        let lock = NSLock()
        var time = 0.0
        var busy = false
        var started: [Int] = []
        var applied: [(turn: Int, text: String)] = []
        var concurrent = 0
        var maxConcurrent = 0
        let gate = DispatchSemaphore(value: 0)
        var blocking = false

        func scheduler(maxAge: Double = 8) -> HistoryPassScheduler {
            HistoryPassScheduler(maxAge: maxAge,
                                 now: { [self] in lock.withLock { time } },
                                 isBusy: { [self] in lock.withLock { busy } },
                                 run: { [self] job in
                lock.withLock { started.append(job.turn); concurrent += 1; maxConcurrent = max(maxConcurrent, concurrent) }
                if lock.withLock({ blocking }) { gate.wait() }
                lock.withLock { concurrent -= 1 }
                return Transcription(text: "whisper \(job.turn)", language: "uk", languageProbabilities: [:],
                                     audioSeconds: job.audio.seconds, elapsedMs: 1, noSpeechProbability: 0)
            }, apply: { [self] job, r in lock.withLock { applied.append((job.turn, r.text)) } })
        }
        func set(time t: Double) { lock.withLock { time = t } }
        func set(busy b: Bool) { lock.withLock { busy = b } }
        func set(blocking b: Bool) { lock.withLock { blocking = b } }
        func appliedTurns() -> [Int] { lock.withLock { applied.map(\.turn) } }
        func startedTurns() -> [Int] { lock.withLock { started } }
    }

    static func audio() -> QuestionAudio { QuestionAudio(samples: [Float](repeating: 0.1, count: 16_000), source: .joined, utterances: [1]) }

    func wait(_ condition: @escaping () -> Bool, timeout: Double = 3) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return condition()
    }

    @Test("A submitted job runs and its text is applied")
    func runsAndApplies() async {
        let h = Harness()
        let s = h.scheduler()
        s.submit(turn: 1, audio: Self.audio(), language: "uk", oldText: "old")
        #expect(await wait { h.appliedTurns() == [1] })
        #expect(s.stats.applied == 1)
    }

    @Test("One in flight; the newest waiting job replaces older waiting ones")
    func oneInFlightNewestReplaces() async {
        let h = Harness()
        h.set(blocking: true)
        let s = h.scheduler()
        s.submit(turn: 1, audio: Self.audio(), language: "uk", oldText: "a")
        #expect(await wait { h.startedTurns() == [1] })
        s.submit(turn: 2, audio: Self.audio(), language: "uk", oldText: "b")
        s.submit(turn: 3, audio: Self.audio(), language: "uk", oldText: "c")
        s.submit(turn: 4, audio: Self.audio(), language: "uk", oldText: "d")
        h.set(blocking: false)
        h.gate.signal()
        #expect(await wait { h.appliedTurns() == [1, 4] })
        #expect(h.startedTurns() == [1, 4])
        #expect(h.lock.withLock { h.maxConcurrent } == 1)
        #expect(s.stats.replaced == 2)
        #expect(s.stats.maxInFlight == 1)
    }

    @Test("A job that waited longer than 8 s is dropped, not run")
    func staleJobIsDropped() async {
        let h = Harness()
        h.set(blocking: true)
        let s = h.scheduler()
        s.submit(turn: 1, audio: Self.audio(), language: "uk", oldText: "a")
        #expect(await wait { h.startedTurns() == [1] })
        s.submit(turn: 2, audio: Self.audio(), language: "uk", oldText: "b")
        h.set(time: 9)   // turn 2 prowls in the queue for 9 s
        h.set(blocking: false)
        h.gate.signal()
        #expect(await wait { s.stats.droppedStale == 1 })
        #expect(h.appliedTurns() == [1])
        #expect(h.startedTurns() == [1])
    }

    @Test("While a new utterance is in progress the job waits, and starts after kick")
    func waitsWhileSpeechInProgress() async {
        let h = Harness()
        h.set(busy: true)
        let s = h.scheduler()
        s.submit(turn: 1, audio: Self.audio(), language: "uk", oldText: "a")
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(h.startedTurns().isEmpty)
        h.set(busy: false)
        s.kick()
        #expect(await wait { h.appliedTurns() == [1] })
    }

    @Test("A job waiting through a long utterance is stale by the time the CPU is free")
    func staleAfterLongSpeech() async {
        let h = Harness()
        h.set(busy: true)
        let s = h.scheduler()
        s.submit(turn: 1, audio: Self.audio(), language: "uk", oldText: "a")
        h.set(time: 12)
        h.set(busy: false)
        s.kick()
        #expect(await wait { s.stats.droppedStale == 1 })
        #expect(h.startedTurns().isEmpty)
    }

    @Test("reset drops the waiting job and the result of the one in flight")
    func resetDropsEverything() async {
        let h = Harness()
        h.set(blocking: true)
        let s = h.scheduler()
        s.submit(turn: 1, audio: Self.audio(), language: "uk", oldText: "a")
        #expect(await wait { h.startedTurns() == [1] })
        s.submit(turn: 2, audio: Self.audio(), language: "uk", oldText: "b")
        s.reset()
        h.set(blocking: false)
        h.gate.signal()
        try? await Task.sleep(nanoseconds: 150_000_000)
        #expect(h.appliedTurns().isEmpty)
        #expect(h.startedTurns() == [1])
    }

    @Test("An unchanged text is not applied")
    func unchangedTextSkipped() async {
        let h = Harness()
        let s = h.scheduler()
        s.submit(turn: 1, audio: Self.audio(), language: "uk", oldText: "whisper 1")
        #expect(await wait { s.stats.started == 1 && h.lock.withLock { h.concurrent } == 0 })
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(h.appliedTurns().isEmpty)
    }
}
