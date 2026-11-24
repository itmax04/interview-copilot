import Foundation
import Testing
@testable import CopilotCore

@MainActor
@Suite("COPILOT-15 P-09 — gated drafts (AC-05)")
struct DraftGatingTests {
    final class Probe: @unchecked Sendable {
        var requests: [[Int]] = []
        var drafts: [String] = []
        var cancels = 0
        var result: String? = "полный вопрос"
        var delayMs: UInt64 = 0
    }

    private func make(_ p: Probe) -> DraftGate {
        DraftGate(redecode: { utterances in
            p.requests.append(utterances)
            if p.delayMs > 0 { try? await Task.sleep(nanoseconds: p.delayMs * 1_000_000) }
            return p.result
        }, onDraft: { p.drafts.append($0) }, onCancel: { p.cancels += 1 })
    }

    private func settle() async { try? await Task.sleep(nanoseconds: 60_000_000) }

    @Test("A draft starts only from the re-decoded text, never from the phrase text")
    func draftIsRedecoded() async {
        let p = Probe(); let gate = make(p)
        gate.offer(utterances: [1, 2])
        await settle()
        #expect(p.requests == [[1, 2]])
        #expect(p.drafts == ["полный вопрос"])
    }

    @Test("The same phrase list is requested once")
    func once() async {
        let p = Probe(); let gate = make(p)
        gate.offer(utterances: [1]); await settle()
        gate.offer(utterances: [1]); await settle()
        #expect(p.requests.count == 1)
        #expect(p.drafts.count == 1)
    }

    @Test("A failed re-decode gives no draft")
    func failed() async {
        let p = Probe(); p.result = nil; let gate = make(p)
        gate.offer(utterances: [1]); await settle()
        #expect(p.drafts.isEmpty)
    }

    @Test("The speaker continues: a started draft is cancelled, a pending request is dropped")
    func continues() async {
        let p = Probe(); let gate = make(p)
        gate.offer(utterances: [1]); await settle()
        gate.cancel()
        #expect(p.cancels == 1)
        p.delayMs = 100
        gate.offer(utterances: [1, 2])
        gate.cancel()
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(p.drafts.count == 1)   // the late result of the dropped request never starts
        #expect(p.cancels == 1)
    }

    @Test("A longer phrase list replaces the previous draft")
    func replaced() async {
        let p = Probe(); let gate = make(p)
        gate.offer(utterances: [1]); await settle()
        p.result = "длиннее"
        gate.offer(utterances: [1, 2]); await settle()
        #expect(p.cancels == 1)
        #expect(p.drafts == ["полный вопрос", "длиннее"])
    }

    @Test("The turn fired: a late result does not start a draft, a started one stays for the turn")
    func turnFired() async {
        let p = Probe(); p.delayMs = 100; let gate = make(p)
        gate.offer(utterances: [1])
        gate.turnFired()
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(p.drafts.isEmpty)
        let q = Probe(); let g2 = make(q)
        g2.offer(utterances: [1]); await settle()
        g2.turnFired()
        #expect(q.cancels == 0)
    }

    @Test("The detector hands the phrase numbers of a finished-looking phrase")
    func detectorSnapshot() {
        var d = TurnDetector(config: .init())
        d.phraseFinal("Розкажіть про ваш досвід роботи з Swift", speechEnd: 1000, utterance: 7)
        let snap = d.draftSnapshot(at: 1200)
        #expect(snap?.utterances == [7])
        var d2 = TurnDetector(config: .init())
        d2.phraseFinal("Розкажіть про ваш досвід роботи з Swift", speechEnd: 1000)
        #expect(d2.draftSnapshot(at: 1200) == nil)
    }
}
