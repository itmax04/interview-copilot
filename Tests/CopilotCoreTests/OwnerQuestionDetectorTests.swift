import Testing
@testable import CopilotCore

@Suite("OwnerQuestionDetector, словарь лекций и жёсткий замок языка")
struct OwnerQuestionDetectorTests {
    @Test func reaskWithinWindowReplacesLastQuestion() {
        let d1 = OwnerQuestionDetector.detect(
            text: "Тобто що таке фінансове право?",
            secondsSinceLastQuestion: 12,
            hasActiveQuestion: true
        )
        #expect(d1 == .replaceLastQuestion("Тобто що таке фінансове право?"))

        let d2 = OwnerQuestionDetector.detect(
            text: "Ви маєте на увазі основні риси фінансового права?",
            secondsSinceLastQuestion: 20,
            hasActiveQuestion: true
        )
        #expect(d2 == .replaceLastQuestion("Ви маєте на увазі основні риси фінансового права?"))

        let d3 = OwnerQuestionDetector.detect(
            text: "Повторю питання: які є види фінансового контролю?",
            secondsSinceLastQuestion: 8,
            hasActiveQuestion: true
        )
        #expect(d3 == .replaceLastQuestion("які є види фінансового контролю?"))
    }

    @Test func directQuestionCreatesNewWhenNoRecentCard() {
        let d1 = OwnerQuestionDetector.detect(
            text: "Що таке фінансове право?",
            secondsSinceLastQuestion: nil,
            hasActiveQuestion: false
        )
        #expect(d1 == .newQuestion("Що таке фінансове право?"))

        let d2 = OwnerQuestionDetector.detect(
            text: "Назвіть основні риси фінансового права.",
            secondsSinceLastQuestion: 45,
            hasActiveQuestion: true
        )
        #expect(d2 == .newQuestion("Назвіть основні риси фінансового права."))
    }

    @Test func shortTermCorrectionClarifiesLastQuestionWithin25s() {
        let d1 = OwnerQuestionDetector.detect(
            text: "Риси",
            secondsSinceLastQuestion: 7,
            hasActiveQuestion: true
        )
        #expect(d1 == .clarifyLastQuestion(correction: "Риси"))

        let d2 = OwnerQuestionDetector.detect(
            text: "Ні, основні риси фінансового права",
            secondsSinceLastQuestion: 15,
            hasActiveQuestion: true
        )
        #expect(d2 == .clarifyLastQuestion(correction: "Ні, основні риси фінансового права"))

        let stale = OwnerQuestionDetector.detect(
            text: "Основні риси",
            secondsSinceLastQuestion: 35,
            hasActiveQuestion: true
        )
        #expect(stale == .none)
    }

    @Test func ignoresNormalAnswersBackchannelsAndRhetoricalQuestions() {
        #expect(OwnerQuestionDetector.detect(
            text: "Добре, секунду, зараз відповім",
            secondsSinceLastQuestion: 5,
            hasActiveQuestion: true
        ) == .none)

        #expect(OwnerQuestionDetector.detect(
            text: "Я думаю, що фінансове право регулює державні фінанси.",
            secondsSinceLastQuestion: 10,
            hasActiveQuestion: true
        ) == .none)

        #expect(OwnerQuestionDetector.detect(
            text: "А що це означає? Це означає, що держава має переважаючі повноваження у відносинах.",
            secondsSinceLastQuestion: 12,
            hasActiveQuestion: true
        ) == .none)

        #expect(OwnerQuestionDetector.detect(
            text: "Фінансово-правові норми поділяються на матеріальні та процесуальні, причому матеріальні норми встановлюють права і обов'язки суб'єктів фінансових відносин у державі.",
            secondsSinceLastQuestion: 10,
            hasActiveQuestion: true
        ) == .none)
    }

    @Test func recognitionVocabularyExtractsFrequentLectureTermsWhenNoCards() {
        let lecture = """
        Фінансово-правові норми та їх основні риси. Основні риси фінансового права включають імперативність.
        Фінансово-правові норми поділяються на матеріальні та процесуальні. Матеріальні норми і процесуальні норми.
        Фінансово-правові санкції забезпечують фінансову дисципліну та фінансовий контроль.
        """
        let prompt = RecognitionVocabulary.prompt(cards: [], materials: [lecture], language: "uk", limit: 300)
        #expect(prompt.contains("фінансово-правові"))
        #expect(prompt.contains("риси"))
        #expect(prompt.contains("процесуальні"))
    }

    @Test func sanityGuardCatchesRussianAnswerWithoutYLetterWhenUkExpected() {
        let guardUk = OutputSanityGuard(config: .init(expectedLanguage: "uk", requireUnderstoodLine: true))
        let ruAnswer = """
        ❓ Что такое финансовое право?
        **Финансовое право — это система норм, которая регулирует распределение финансов и определяет порядок контроля, также включает судебную защиту.**
        """
        #expect(guardUk.check(ruAnswer, isFinal: true) == .languageMix)
    }
}
