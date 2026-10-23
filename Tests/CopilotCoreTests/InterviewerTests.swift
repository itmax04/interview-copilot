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

    @Test func withoutProfileInterviewsForGeneralDeveloperRole() {
        // R-40: «Без профиля» — пустые резюме и вакансия, общие вопросы.
        let s = InterviewerPrompt.system(profile: Profile(name: "Без профиля"), language: "ru", redactPII: true)
        #expect(s.contains("If neither is given"))
        #expect(s.contains("software developer role"))
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

@Suite("Hybrid Ukrainian final — R-35")
struct HybridRecognizerTests {
    final class Fake: SpeechRecognizer, @unchecked Sendable {
        let text: String
        private(set) var calls: [(language: String?, reduced: Bool)] = []
        init(_ text: String) { self.text = text }
        func transcribe(_ samples: [Float], language: String?, prompt: String?, reducedContext: Bool) throws -> Transcription {
            calls.append((language, reducedContext))
            return Transcription(text: text, language: language ?? "ru", languageProbabilities: [:], audioSeconds: 1,
                                 elapsedMs: 100, noSpeechProbability: text.isEmpty ? 1 : 0)
        }
        func detectLanguage(_ samples: [Float]) throws -> (String, [String: Float]) { ("ru", [:]) }
        func cancel() {}
    }

    @Test func ukrainianLettersOrExplicitLanguageTriggerWhisper() {
        #expect(HybridRecognizer.needsUkrainian(language: "uk", text: "Расскажите о себе"))
        #expect(HybridRecognizer.needsUkrainian(language: nil, text: "Розкажіть про себе"))
        #expect(!HybridRecognizer.needsUkrainian(language: nil, text: "Расскажите о себе"))
        #expect(!HybridRecognizer.needsUkrainian(language: "ru", text: "Розкажіть"))
        #expect(!HybridRecognizer.needsUkrainian(language: nil, text: "Tell me about yourself"))
    }

    @Test func finalUsesWhisperWithUkrainianAndFullContextPartialStaysParakeet() throws {
        let parakeet = Fake("Розкажыте про сэбе"), whisper = Fake("Розкажіть про себе")
        let loads = Counter()
        let hybrid = HybridRecognizer(primary: parakeet, loadVerifier: { loads.add(); return whisper })
        let partial = try hybrid.transcribe([0], language: "uk", prompt: nil, reducedContext: true)
        #expect(partial.text == "Розкажыте про сэбе")
        #expect(whisper.calls.isEmpty && loads.value == 0)
        let final = try hybrid.transcribeFinal([0], language: "uk", prompt: nil, reducedContext: true)
        #expect(final.text == "Розкажіть про себе")
        #expect(final.language == "uk")
        #expect(whisper.calls.first?.language == "uk")
        #expect(whisper.calls.first?.reduced == false)
        _ = try hybrid.transcribeFinal([0], language: "uk", prompt: nil, reducedContext: false)
        #expect(loads.value == 1)
    }

    @Test func russianFinalStaysParakeetAndFailuresFallBack() throws {
        let whisper = Fake("не должно вызываться")
        let ru = HybridRecognizer(primary: Fake("Почему вы ушли?"), loadVerifier: { whisper })
        #expect(try ru.transcribeFinal([0], language: nil, prompt: nil, reducedContext: false).text == "Почему вы ушли?")
        #expect(whisper.calls.isEmpty)
        struct LoadError: Error {}
        let broken = HybridRecognizer(primary: Fake("Чому ви пішли?"), loadVerifier: { throw LoadError() })
        #expect(try broken.transcribeFinal([0], language: nil, prompt: nil, reducedContext: false).text == "Чому ви пішли?")
        let silent = HybridRecognizer(primary: Fake("Чому ви пішли?"), loadVerifier: { Fake("") })
        #expect(try silent.transcribeFinal([0], language: nil, prompt: nil, reducedContext: false).text == "Чому ви пішли?")
    }

    final class Counter: @unchecked Sendable {
        private(set) var value = 0
        func add() { value += 1 }
    }
}

@Suite("Шум, потерянные события, двухэтапный итог — R-37, R-38")
struct TurnRobustnessTests {
    func run(_ d: inout TurnDetector, from: Double, until: Double) -> Turn? {
        var t = from
        while t <= until {
            if let turn = d.tick(at: t) { return turn }
            t += 50
        }
        return nil
    }

    @Test func noiseAfterQuestionNoLongerBlocksTurn() {
        var d = TurnDetector()
        d.interviewerStartedSpeaking(at: 0)
        d.interviewerStoppedSpeaking(at: 2000)
        d.phraseFinal("Расскажите о вашем последнем проекте?", speechEnd: 2000)
        // Кашель: VAD открыл и закрыл фразу, текста нет.
        d.interviewerStartedSpeaking(at: 2200)
        d.interviewerStoppedSpeaking(at: 2500)
        #expect(d.tick(at: 3500) == nil) // ждём итог шума
        d.phraseDiscarded(speechEnd: 2500)
        let turn = run(&d, from: 3500, until: 4000)
        #expect(turn?.text == "Расскажите о вашем последнем проекте?")
        #expect(turn?.firedAt == 3500)
    }

    @Test func lostFinalAndLostSpeechEndExpire() {
        var d = TurnDetector()
        d.interviewerStartedSpeaking(at: 0)
        d.phraseFinal("Почему вы хотите сменить работу?", speechEnd: 2000)
        d.interviewerStartedSpeaking(at: 2300)
        d.interviewerStoppedSpeaking(at: 2600) // итог этой фразы так и не пришёл
        #expect(run(&d, from: 2700, until: 10_500) == nil)
        #expect(run(&d, from: 10_600, until: 11_000) != nil) // > 8 с — больше не ждём

        var stuck = TurnDetector()
        stuck.interviewerStartedSpeaking(at: 0)
        stuck.phraseFinal("Как вы решаете конфликты в команде?", speechEnd: 2000)
        stuck.interviewerStartedSpeaking(at: 2100) // конец речи потерялся
        #expect(run(&stuck, from: 2200, until: 31_000) == nil)
        #expect(run(&stuck, from: 32_200, until: 33_000) != nil)
    }

    @Test func discardedNoiseFromEarlierPhraseDoesNotSkipNewerFinal() {
        var d = TurnDetector()
        d.interviewerStartedSpeaking(at: 0)
        d.phraseFinal("Расскажите о себе подробнее", speechEnd: 1000)
        d.interviewerStartedSpeaking(at: 1200)
        d.interviewerStoppedSpeaking(at: 1400) // шум
        d.interviewerStartedSpeaking(at: 1600)
        d.interviewerStoppedSpeaking(at: 3000) // продолжение вопроса, итог ещё распознаётся
        d.phraseDiscarded(speechEnd: 1400)
        #expect(d.tick(at: 3900) == nil) // ждём итог продолжения, а не стреляем по половине вопроса
    }

    @Test func trialAndAnswerWaitForRevisedText() {
        var trial = TestCallTrial(clip: TestCallClip(id: "c", language: "uk", title: "t", text: "Розкажіть про себе", file: ""))
        trial.handle(.speechStarted(utterance: 1))
        trial.handle(.speechStarted(utterance: 2))
        trial.handle(.revising(utterance: 1))
        trial.handle(.final(utterance: 1, text: "Расскажите про себе", language: "ru", phraseEnd: 1_000_000_000, emittedAt: 1_500_000_000))
        trial.handle(.discarded(utterance: 2, phraseEnd: 2_000_000_000))
        trial.endPlayback(at: 10)
        trial.tick(at: 11)
        #expect(trial.result == nil) // ждём уточнения
        trial.handle(.revised(utterance: 1, text: "Розкажіть про себе", language: "uk"))
        trial.tick(at: 11.1)
        #expect(trial.result?.errors == 0)
        #expect(trial.result?.latencyMs == 500) // задержка — по быстрому итогу

        var a = AnswerCapture(startedAt: 0)
        a.handle(.speechStarted(utterance: 5), at: 1)
        a.handle(.revising(utterance: 5), at: 3)
        a.handle(.final(utterance: 5, text: "Я працюю", language: "uk", phraseEnd: 0, emittedAt: 0), at: 3)
        a.requestFinish(at: 3)
        #expect(!a.isComplete(at: 4))
        a.handle(.revised(utterance: 5, text: "Я працюю в команді", language: "uk"), at: 5)
        #expect(a.isComplete(at: 5) && a.text == "Я працюю в команді")
    }

    @Test func answerLanguageFollowsMenuOrUkrainianLetters() {
        #expect(PromptBuilder.answerLanguage(setting: "en", question: "Розкажіть") == "en")
        #expect(PromptBuilder.answerLanguage(setting: nil, question: "Розкажіть про себе") == "uk")
        #expect(PromptBuilder.answerLanguage(setting: nil, question: "Расскажите о себе") == nil)
        let u = PromptBuilder.user(question: "Расскажите про проэкт", transcript: [], cards: [], baseCard: nil, answerLanguage: "uk")
        #expect(u.contains("Answer in Ukrainian"))
    }
}

@Suite("Уточнение всех языков — R-37")
struct ReviseAllLanguagesTests {
    @Test func revisionLanguageFollowsMenuOrAlphabet() {
        #expect(HybridRecognizer.revisionLanguage(language: "en", text: "Привіт") == "en")
        #expect(HybridRecognizer.revisionLanguage(language: nil, text: "Розкажіть про себе") == "uk")
        #expect(HybridRecognizer.revisionLanguage(language: nil, text: "Мы используем поуст Griskl") == "ru")
        #expect(HybridRecognizer.revisionLanguage(language: nil, text: "We use PostGur SQL") == "en")
    }

    @Test func reviseAllAppliesToRussianAndEnglish() {
        let fake = HybridRecognizerTests.Fake("x")
        let only = HybridRecognizer(primary: fake, loadVerifier: { fake })
        let all = HybridRecognizer(primary: fake, reviseAllLanguages: true, loadVerifier: { fake })
        let ru = Transcription(text: "Мы используем Редис", language: "ru", languageProbabilities: [:], audioSeconds: 1, elapsedMs: 1, noSpeechProbability: 0)
        #expect(!only.revisionNeeded(ru, language: nil))
        #expect(all.revisionNeeded(ru, language: nil))
        var empty = ru; empty.text = ""
        #expect(!all.revisionNeeded(empty, language: nil))
    }
}
