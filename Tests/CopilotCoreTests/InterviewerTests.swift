import Foundation
import Testing
@testable import CopilotCore

@Suite("AI interviewer — COPILOT-03")
struct InterviewerTests {
    private let profile = Profile(name: "Test", resume: "iOS developer, mail me at dev@example.com", job: "Senior iOS engineer")

    @Test func firstRequestStartsInterviewInChosenLanguage() {
        let r = InterviewerPrompt.request(profile: profile, language: "uk", history: [], questionCount: 5, redactPII: true)
        #expect(r.system.contains("Speak only Ukrainian."))
        #expect(r.system.contains("Senior iOS engineer"))
        #expect(!r.system.contains("dev@example.com"))
        #expect(r.messages.count == 1)
        #expect(r.messages[0].role == .user)
        #expect(r.messages[0].text.contains("question 1 of 5"))
        #expect(r.maxTokens == 200)
    }

    @Test func historyAlternatesQuestionsAndAnswersAndMarksLastQuestion() {
        let history = [InterviewExchange(question: "Tell me about yourself.", answer: "I build apps, call " + "+380 67 " + "123 45 67"),
                       InterviewExchange(question: "Why this company?", answer: "  ")]
        let r = InterviewerPrompt.request(profile: profile, language: "en", history: history, questionCount: 3, redactPII: true)
        #expect(r.messages.map(\.role) == [.user, .assistant, .user, .assistant, .user])
        #expect(r.messages[1].text == "Tell me about yourself.")
        #expect(r.messages[2].text.contains("<answer>"))
        #expect(r.messages[2].text.contains("[телефон]"))
        #expect(r.messages[4].text.contains("(no answer was recognized)"))
        #expect(r.messages[4].text.contains("question 3 of 3. It is the last question."))
    }

    @Test func spokenTextDropsMarkupAndSpeakerLabel() {
        #expect(InterviewerPrompt.spoken("Interviewer: **Расскажите**  о «себе».\n") == "Расскажите о себе.")
        #expect(InterviewerPrompt.spoken("# Що вас мотивує?") == "Що вас мотивує?")
    }

    @Test func wavHeaderAndLength() {
        let data = WAVEncoder.encode([0, 0.5, -0.5, 2], sampleRate: 22_050)
        #expect(data.count == 44 + 8)
        #expect(String(data: data.prefix(4), encoding: .ascii) == "RIFF")
        #expect(String(data: data[8..<12], encoding: .ascii) == "WAVE")
        let rate = data[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        #expect(UInt32(littleEndian: rate) == 22_050)
        let clipped = data[50..<52].withUnsafeBytes { $0.loadUnaligned(as: Int16.self) }
        #expect(Int16(littleEndian: clipped) == 32767)
    }

    @Test func answerAutoFinishesAfterSilenceOnlyWhenEverythingIsRecognized() {
        var a = AnswerCapture(startedAt: 0)
        #expect(!a.shouldAutoFinish(at: 10, silence: 3)) // ещё ничего не сказано
        a.handle(.speechStarted(utterance: 7), at: 1)
        a.handle(.speechEnded(utterance: 7, at: 0), at: 4)
        #expect(!a.shouldAutoFinish(at: 9, silence: 3)) // итог ещё не пришёл
        a.handle(.final(utterance: 7, text: "Я працюю з iOS", language: "uk", phraseEnd: 0, emittedAt: 0), at: 4.5)
        #expect(!a.shouldAutoFinish(at: 6, silence: 3))
        #expect(a.shouldAutoFinish(at: 7.6, silence: 3))
        #expect(!a.shouldAutoFinish(at: 7.6, silence: 0)) // только по кнопке
        #expect(a.speechSeconds == 3)
    }

    @Test func answerWaitsForPendingUtterancesAfterButtonAndKeepsOrder() {
        var a = AnswerCapture(startedAt: 0)
        a.handle(.speechStarted(utterance: 2), at: 1)
        a.handle(.speechStarted(utterance: 3), at: 3)
        a.handle(.final(utterance: 3, text: "second", language: "en", phraseEnd: 0, emittedAt: 0), at: 5)
        a.requestFinish(at: 5)
        #expect(!a.isComplete(at: 6))
        a.handle(.final(utterance: 2, text: "first", language: "en", phraseEnd: 0, emittedAt: 0), at: 6)
        #expect(a.isComplete(at: 6))
        #expect(a.text == "first second")
        var stuck = AnswerCapture(startedAt: 0)
        stuck.handle(.speechStarted(utterance: 1), at: 1)
        stuck.requestFinish(at: 2)
        #expect(!stuck.isComplete(at: 10))
        #expect(stuck.isComplete(at: 17))
    }

    @Test func correctionScoresRecognizedAnswer() {
        var record = InterviewTurnRecord(id: "q1", index: 1, language: "ru", question: "Почему вы ушли?", result: nil, provider: nil)
        #expect(record.questionErrors == 3)
        record.answer = "Я хотел больше ответственности"
        record.correct("Я хотел больше ответственности и роста")
        #expect(record.answerWords == 6)
        #expect(record.answerErrors == 2)
        record.correct("   ")
        #expect(record.corrected == nil)
        #expect(record.answerWER == nil)
    }

    @Test @MainActor func synthesizesSpeechWhenVoiceIsInstalled() async throws {
        guard SpeechSynth.voice(for: "ru") != nil else { return }
        let wav = try await SpeechSynth.wav("Расскажите о себе.", language: "ru")
        // Тишина 1,5 с плюс речь: больше полутора секунд звука.
        let rate = wav[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        let seconds = Double(wav.count - 44) / 2 / Double(UInt32(littleEndian: rate))
        #expect(seconds > 1.8)
        #expect(seconds < 10)
    }
}
