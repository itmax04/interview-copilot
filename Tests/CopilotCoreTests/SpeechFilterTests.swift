import Foundation
import Testing
@testable import CopilotCore

/// COPILOT-05: фильтр языка (R-05), словарь терминов (Q9), проверка речи перед распознаванием (R-02).
@Suite("Фильтр языка — COPILOT-05 R-05")
struct LanguageGateTests {
    let uk = LanguageGate(setting: .uk)
    let ru = LanguageGate(setting: .ru)
    let en = LanguageGate(setting: .en)
    let auto = LanguageGate(setting: .auto)

    @Test(arguments: [
        // S-02, AC-02: английские термины внутри фразы на выбранном языке сохраняются.
        "Как вы настраивали CI/CD и code review в GitLab?",
        "Розкажіть, як ви використовували Kubernetes і Docker у production.",
        "Какой у вас опыт с SwiftUI, Combine и async await?",
        "Чи працювали ви з REST API та GraphQL?",
        "Почему вы выбрали MVVM, а не VIPER?",
    ])
    func slavicPhrasesWithTermsPass(text: String) {
        for gate in [uk, ru, auto] {
            for channel in [LanguageGate.Channel.call, .mic, .allSystem] { #expect(gate.check(text, channel: channel) == .keep) }
        }
    }

    @Test func ukrainianAndRussianAreOneGroup() {
        // Q7: выбран украинский — русский проходит, и наоборот.
        #expect(uk.check("Расскажите о вашем последнем проекте.", channel: .mic) == .keep)
        #expect(ru.check("Розкажіть про ваш останній проєкт.", channel: .mic) == .keep)
    }

    @Test func foreignLanguageIsDropped() {
        // S-01: немецкий из ТВ — серым в любом канале.
        let de = "Heute Abend gibt es in den Nachrichten einen Bericht über das Wetter in Berlin."
        #expect(uk.check(de, channel: .mic) == .drop(language: "de"))
        #expect(uk.check(de, channel: .call) == .drop(language: "de"))
        #expect(auto.check(de, channel: .allSystem) == .drop(language: "de"))
        let fr = "Bonjour à tous, aujourd'hui nous allons parler de la météo et du sport."
        if case .drop = ru.check(fr, channel: .mic) {} else { Issue.record("французский должен отбрасываться") }
    }

    @Test func englishPhraseRulesDependOnChannel() {
        let phrase = "Let's continue in English. Tell me about your last project."
        // S-04, Q8: в звонке английская фраза интервьюера проходит.
        #expect(ru.check(phrase, channel: .call) == .keep)
        // В микрофоне и «Весь системный звук» — строго.
        #expect(ru.check(phrase, channel: .mic) == .drop(language: "en"))
        #expect(uk.check(phrase, channel: .allSystem) == .drop(language: "en"))
        // English и Auto — английский разрешён.
        #expect(en.check(phrase, channel: .mic) == .keep)
        #expect(auto.check(phrase, channel: .mic) == .keep)
    }

    @Test func shortEnglishTermPhrasesPassInMic() {
        // Q9: целиком английская фраза ≤ 4 слов из терминов — проходит.
        #expect(ru.check("Pull request and code review", channel: .mic) == .keep)
        #expect(uk.check("Yes, exactly.", channel: .mic) == .keep)
        #expect(ru.check("REST API", channel: .mic) == .keep)
        // Пятое слово или не-термин — уже обычная английская речь.
        #expect(ru.check("I really love watching football matches", channel: .mic) == .drop(language: "en"))
    }

    @Test func slavicSpeechIsDroppedWhenEnglishChosen() {
        #expect(en.check("Сегодня в новостях покажут погоду на завтра.", channel: .mic) == .drop(language: "uk/ru"))
        #expect(en.check("Сегодня в новостях покажут погоду на завтра.", channel: .call) == .drop(language: "uk/ru"))
    }

    @Test func shortUncertainPhrasesAreKept() {
        // R-05: короче 3 слов — не отбрасываем (лучше пропустить шум, чем потерять вопрос).
        #expect(en.check("Ну да", channel: .mic) == .keep)
        #expect(uk.check("Guten Tag", channel: .mic) == .keep)
        #expect(uk.check("", channel: .mic) == .keep)
    }

    @Test func dictionaryLearnsTermsFromProfile() {
        var terms = TermDictionary()
        #expect(!terms.allTerms(["supercoolframework"]))
        terms.add(texts: ["Опыт: SuperCoolFramework, VIPER, Alamofire"])
        #expect(terms.allTerms(["supercoolframework", "alamofire"]))
        let gate = LanguageGate(setting: .ru, terms: terms)
        #expect(gate.check("SuperCoolFramework with Alamofire", channel: .mic) == .keep)
    }
}

@Suite("Ответ по отфильтрованной реплике — COPILOT-05 S-08")
struct FilteredTurnTests {
    @Test func forceTextFiresForcedTurn() {
        var d = TurnDetector()
        d.phraseFinal("Как вы тестируете код?", speechEnd: 1000)
        let turn = d.forceText("Let's continue in English, please.", at: 5000)
        #expect(turn.text == "Let's continue in English, please." && turn.forced)
        #expect(d.pendingText.isEmpty)
    }
}

@Suite("Проверка речи перед распознаванием — COPILOT-05 R-02")
struct SpeechGateTests {
    @Test func rejectedUtteranceIsDiscardedWithoutRecognition() async {
        let buffer = AudioRingBuffer(seconds: 30)
        let fake = FakeRecognizer()
        let sink = EventSink()
        var config = StreamingTranscriber.Config()
        config.partialInterval = 10   // без частичных прогонов: считаем только итог
        let t = StreamingTranscriber(recognizer: fake, buffer: buffer, config: config) { sink.add($0) }
        t.setLanguage("uk")
        t.setSpeechGate { _ in false }
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
        #expect(await sink.waitFor { $0.contains { if case .discarded = $0 { true } else { false } } })
        #expect(!sink.events.contains { if case .final = $0 { true } else { false } })
        #expect(fake.transcribeCalls.isEmpty)
    }

    @Test func sileroSeparatesSpeechFromSilenceWhenInstalled() throws {
        guard SileroSpeechGate.isInstalled(in: AppPaths.models) else { return } // модель не установлена — проверка в eval `filter`
        let gate = try SileroSpeechGate.load(from: AppPaths.models)
        let silence = [Float](repeating: 0, count: 16_000 * 2)
        #expect(gate.speechProbability(silence) < 0.5)
        let speechURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("evals/audio/ru-about-me.wav")
        let speech = try AudioFileReader.read16kMono(speechURL)
        #expect(gate.speechProbability(speech) >= 0.5)
    }
}

@Suite("Микрофон: шум комнаты и выдумки Whisper — COPILOT-05, живой лог 2026-10-23")
struct MicrophoneNoiseTests {
    /// Шум у микрофона −50 dBFS (комната): со старым порогом (−62) открывал реплику, с порогом микрофона — нет.
    @Test func roomNoiseDoesNotOpenUtteranceWithMicrophoneThreshold() {
        // Амплитуда ~0,0045 ≈ −47 dBFS по пику, RMS ниже: уровень шума комнаты из лога (−46…−58).
        let room = EnergyVADTests.tone(ms: 1500, amplitude: 0.0045)
        let quiet = EnergyVADTests.noise(ms: 3000, amplitude: 0.0001)
        var callVAD = EnergyVAD(config: StreamingTranscriber.Config().vad)
        _ = callVAD.process(quiet)
        #expect(callVAD.process(room).contains(true))
        var micVAD = EnergyVAD(config: StreamingTranscriber.microphoneVAD)
        _ = micVAD.process(quiet)
        #expect(!micVAD.process(room).contains(true))
        // Голос рядом с микрофоном (−25…−30 dBFS) по-прежнему речь.
        #expect(micVAD.process(EnergyVADTests.tone(ms: 1000, amplitude: 0.05)).contains(true))
    }

    @Test func whisperHallucinationsAreDroppedOnlyWhenShort() {
        #expect(HallucinationFilter.isLikely("Дякую!", audioSeconds: 0.9))
        #expect(HallucinationFilter.isLikely("  Спасибо за просмотр. ", audioSeconds: 1.5))
        #expect(HallucinationFilter.isLikely("Thank you.", audioSeconds: 0.7))
        #expect(HallucinationFilter.isLikely("Продолжение следует...", audioSeconds: 2))
        // Длинная реплика или «спасибо» внутри фразы — настоящая речь.
        #expect(!HallucinationFilter.isLikely("Дякую!", audioSeconds: 3.5))
        #expect(!HallucinationFilter.isLikely("Спасибо, а теперь расскажите о себе", audioSeconds: 2))
        #expect(!HallucinationFilter.isLikely("", audioSeconds: 0.5))
    }
}
