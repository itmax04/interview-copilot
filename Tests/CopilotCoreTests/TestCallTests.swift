import Foundation
import Testing
@testable import CopilotCore

@Suite("Local test call")
struct TestCallTests {
    private var clip: TestCallClip {
        TestCallClip(id: "en-example", language: "en", title: "Example", text: "First sentence second sentence", file: "en-example.wav")
    }

    @Test func comparisonCountsSubstitutionDeletionAndInsertion() {
        let score = TranscriptComparison(reference: "one two three four", recognized: "one too four extra")
        #expect(score.referenceWords == 4)
        #expect(score.errors == 3)
        #expect(score.wordErrorRate == 0.75)
        #expect(TranscriptComparison(reference: "one", recognized: "one two three").wordErrorRate == 2)
    }

    @Test func normalizationPreservesNegationAndUkrainianWords() {
        #expect(TranscriptComparison(reference: "Ёж, об’єкт! DON'T.", recognized: "еж об'єкт don't").errors == 0)
        #expect(TranscriptComparison(reference: "не погодився", recognized: "погодився").errors == 1)
        #expect(TranscriptComparison(reference: "версія два", recognized: "версія 2").errors == 1)
        #expect(TranscriptComparison(reference: "one two", recognized: "").errors == 2)
    }

    @Test func waitsForAllUtterancesAndKeepsOriginalOrder() {
        var trial = TestCallTrial(clip: clip)
        trial.handle(.speechStarted(utterance: 4))
        trial.handle(.speechStarted(utterance: 5))
        trial.endPlayback(at: 100)
        trial.handle(.final(utterance: 5, text: "second sentence", language: "en", phraseEnd: 3_000_000_000, emittedAt: 3_600_000_000))
        trial.tick(at: 102)
        #expect(trial.result == nil)
        trial.handle(.final(utterance: 4, text: "First sentence", language: "en", phraseEnd: 1_000_000_000, emittedAt: 3_700_000_000))
        trial.tick(at: 102.1)
        #expect(trial.result?.recognized == clip.text)
        #expect(trial.result?.errors == 0)
        #expect(trial.result?.latencyMs == 700)
    }

    @Test func ignoresForeignAndLateFinals() {
        var trial = TestCallTrial(clip: clip)
        trial.handle(.final(utterance: 3, text: "Unrelated", language: "en", phraseEnd: 1, emittedAt: 2))
        #expect(trial.text.isEmpty)
        trial.handle(.speechStarted(utterance: 4))
        trial.handle(.final(utterance: 4, text: clip.text, language: "en", phraseEnd: 1, emittedAt: 2))
        trial.endPlayback(at: 0)
        trial.tick(at: 0.5)
        #expect(trial.result == nil)
        trial.tick(at: 1)
        trial.handle(.final(utterance: 4, text: "Late replacement", language: "en", phraseEnd: 1, emittedAt: 2))
        #expect(trial.result?.recognized == clip.text)
    }

    @Test func silenceAndUnfinishedQueueAreFailures() {
        var silent = TestCallTrial(clip: clip)
        silent.endPlayback(at: 0)
        silent.tick(at: 19)
        #expect(silent.result == nil)
        silent.tick(at: 20)
        #expect(silent.result?.problem != nil)
        #expect(silent.result?.wer == 100)
        var delayed = TestCallTrial(clip: clip)
        delayed.handle(.speechStarted(utterance: 1))
        delayed.handle(.final(utterance: 1, text: "First sentence", language: "en", phraseEnd: 1, emittedAt: 2))
        delayed.handle(.speechStarted(utterance: 2))
        delayed.endPlayback(at: 0)
        delayed.tick(at: 21)
        #expect(delayed.result?.problem != nil)
        #expect(delayed.result?.recognized == "First sentence")
    }

    @Test func parserWaitsForCompleteBodyAndRejectsAmbiguousFraming() {
        let prefix = "POST /token/ended/id HTTP/1.1\r\nHost: 127.0.0.1:1234\r\nContent-Length: 4\r\n\r\n"
        if case .incomplete = LocalHTTPParser.parse(Data((prefix + "ab").utf8)) {} else { Issue.record("Accepted incomplete body") }
        if case .request(let r) = LocalHTTPParser.parse(Data((prefix + "abcd").utf8)) {
            #expect(r.method == "POST")
            #expect(r.headers["host"] == "127.0.0.1:1234")
            #expect(r.body == Data("abcd".utf8))
        } else { Issue.record("Rejected full body") }
        for headers in ["Content-Length: -1", "Content-Length: 8193", "Transfer-Encoding: chunked", "Host: a\r\nHost: b"] {
            if case .invalid = LocalHTTPParser.parse(Data("POST / HTTP/1.1\r\n\(headers)\r\n\r\n".utf8)) {} else { Issue.record("Accepted ambiguous/invalid headers") }
        }
        if case .invalid = LocalHTTPParser.parse(Data(repeating: 65, count: 32_769)) {} else { Issue.record("Accepted oversized request") }
    }
}
