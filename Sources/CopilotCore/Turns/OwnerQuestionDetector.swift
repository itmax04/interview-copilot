import Foundation

/// Определяет, повторяет или уточняет ли владелец вопрос экзаменатора/собеседника своим голосом
/// (вместо обычного ответа), чтобы приложение могло обновить или сгенерировать подсказку без нажатия кнопок.
public enum OwnerQuestionDetector {
    public enum Decision: Equatable, Sendable {
        /// Обычная речь/ответ владельца или шум — идёт в память интервью как ответ, подсказку не запускает.
        case none
        /// Новый самостоятельный вопрос, продиктованный владельцем (нет недавней карточки в пределах окна).
        case newQuestion(String)
        /// Повтор / переспрос последнего вопроса (в пределах 30 с) — обновляет текущую карточку новой версией.
        case replaceLastQuestion(String)
        /// Короткая поправка формулировки/термина (1–5 слов в пределах 25 с, напр. «основні риси», «ні, риси»).
        case clarifyLastQuestion(correction: String)
    }

    public static let maxWords = 15
    /// Предел длины фразы во взведённом режиме «Уточнить» (D9): владелец может повторить вопрос целиком.
    public static let forcedMaxWords = 40
    public static let replaceWindowSeconds: TimeInterval = 30
    public static let clarifyWindowSeconds: TimeInterval = 25
    public static let maxClarifyWords = 5

    /// Маркеры естественного переспроса на звонке или диктовки вопроса.
    private static let reaskMarkers: [String] = [
        // UK
        "тобто", "ви маєте на увазі", "маєте на увазі", "ви питаєте", "питаєте про",
        "правильно зрозумів", "правильно я зрозумів", "правильно розумію", "ви про ",
        "повторю питання", "мається на увазі", "перепитаю", "уточню питання", "ще раз питання",
        // RU
        "то есть", "вы имеете в виду", "имеете в виду", "вы спрашиваете", "спрашиваете про",
        "правильно понял", "правильно я понял", "правильно понимаю", "вы про ",
        "повторю вопрос", "имеется в виду", "переспрошу", "уточню вопрос", "еще раз вопрос", "ещё раз вопрос",
        // EN
        "you mean", "do you mean", "are you asking", "so you're asking", "repeat the question",
    ]

    /// Начала прямых вопросов / экзаменационных формулировок (UK/RU/EN).
    private static let directQuestionStarters: [String] = [
        // UK
        "що таке", "що це", "що відрізняє", "що входить", "що належить", "що означає",
        "які ", "який ", "яка ", "яке ", "яким чином", "як ", "чому ", "навіщо ", "коли ", "де ", "хто ",
        "чим відрізняється", "чим відрізняються", "у чому", "в чому",
        "назвіть", "сформулюйте", "визначте", "класифікуйте", "охарактеризуйте",
        "розкажіть", "поясніть", "перелічіть", "порівняйте", "яка структура", "які види", "які методи",
        "які риси", "які ознаки", "які функції", "які повноваження", "які санкції",
        // RU
        "что такое", "что это", "что отличает", "что входит", "что относится", "что означает",
        "какие ", "какой ", "какая ", "какое ", "каким образом", "как ", "почему ", "зачем ", "когда ", "где ", "кто ",
        "чем отличается", "чем отличаются", "в чём", "в чем",
        "назовите", "сформулируйте", "определите", "классифицируйте", "охарактеризуйте",
        "расскажите", "объясните", "перечислите", "сравните", "какая структура", "какие виды", "какие методы",
        "какие черты", "какие признаки", "какие функции", "какие полномочия", "какие санкции",
        // EN
        "what is", "what are", "how does", "how do", "why ", "which ", "explain ", "define ", "list ",
    ]

    /// Явные начала собственного ответа владельца — никогда не триггерить на них.
    private static let answerStarters: [String] = [
        // UK
        "я думаю", "я вважаю", "на мою думку", "по-перше", "по-друге", "це означає", "це коли",
        "це система", "це сукупність", "це норми", "це право", "вони поділяються", "вони бувають",
        "до них належать", "сюди належать", "наприклад", "справа в тому", "в принципі", "загалом",
        "ми можемо", "я працював", "я робив", "у мене", "на моєму",
        // RU
        "я думаю", "я считаю", "по-моему", "во-первых", "во-вторых", "это означает", "это значит", "это когда",
        "это система", "это совокупность", "это нормы", "это право", "они делятся", "они бывают",
        "к ним относятся", "сюда относятся", "например", "дело в том", "в принципе", "в целом",
        "мы можем", "я работал", "я делал", "у меня", "на моём", "на моем",
        // EN
        "i think", "in my opinion", "firstly", "for example", "it means", "i worked", "in my project",
    ]

    /// Короткие слова-паразиты и заполнители пауз, которые не должны считаться поправкой термина.
    private static let fillerWords: Set<String> = [
        "так", "да", "ні", "нет", "ну", "ось", "вот", "ага", "угу", "окей", "ок", "ok", "yes", "no",
        "добре", "хорошо", "ладно", "звісно", "конечно", "зрозуміло", "понятно", "зрозумів", "понял",
        "дякую", "спасибо", "секунду", "секундочку", "хвилинку", "хвилину", "минутку", "минуту", "момент", "зараз", "сейчас",
        "відповім", "отвечу", "подумаю", "почну", "начну", "скажу", "розкажу", "расскажу", "спробую", "попробую",
        "значить", "значит", "дивіться", "смотрите", "слухайте", "слушайте", "давайте", "почекайте", "подождите",
        "хм", "мм", "ем", "ээ", "ммм", "ааа", "ой", "алло", "привіт", "привет", "вітаю", "здравствуйте",
        "чути", "слышно", "видно", "раз", "два", "три", "перевірка", "проверка", "тест",
    ]

    static func isFiller(_ word: String) -> Bool { fillerWords.contains(word) }

    /// Явные префиксы поправки («ні, риси», «не рейси а риси»).
    private static let correctionPrefixes: [String] = [
        "ні, ", "нет, ", "не ", "я про ", "мав на увазі ", "имел в виду ",
    ]

    public static func detect(text: String, secondsSinceLastQuestion: TimeInterval?,
                              hasActiveQuestion: Bool) -> Decision {
        detect(text: text, secondsSinceLastQuestion: secondsSinceLastQuestion, hasActiveQuestion: hasActiveQuestion, wordLimit: maxWords)
    }

    static func detect(text: String, secondsSinceLastQuestion: TimeInterval?, hasActiveQuestion: Bool, wordLimit: Int) -> Decision {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }

        let words = extractWords(trimmed)
        guard !words.isEmpty, words.count <= wordLimit else { return .none }

        // Бэкченнелы и слова-заполнители («добре, секунду», «так, зрозумів») никогда не запускают подсказку.
        if words.allSatisfy({ fillerWords.contains($0) }) || TurnDetector.isBackchannel(trimmed) {
            return .none
        }

        let lower = trimmed.lowercased()

        // Риторический вопрос внутри уже начавшегося ответа («А що це означає? Це означає, що держава…»).
        if let qMark = lower.firstIndex(of: "?") {
            let afterQ = String(lower[lower.index(after: qMark)...])
            if extractWords(afterQ).count >= 4 {
                return .none
            }
        }

        // Явное начало ответа кандидата — не перехватываем.
        if answerStarters.contains(where: { lower.hasPrefix($0) }) {
            return .none
        }

        let withinReplace = hasActiveQuestion && (secondsSinceLastQuestion.map { $0 <= replaceWindowSeconds } ?? false)
        let withinClarify = hasActiveQuestion && (secondsSinceLastQuestion.map { $0 <= clarifyWindowSeconds } ?? false)

        // 1. Естественный переспрос («тобто що таке…», «ви маєте на увазі…», «ви питаєте про…»).
        if reaskMarkers.contains(where: { lower.contains($0) }) {
            let cleaned = stripMetaPrefix(trimmed)
            guard !cleaned.isEmpty else { return .none }
            return withinReplace ? .replaceLastQuestion(cleaned) : .newQuestion(cleaned)
        }

        // 2. Прямой вопрос или экзаменационная формулировка («що таке…», «назвіть основні риси…», или заканчивается на «?»).
        let isDirectQuestion = directQuestionStarters.contains(where: { lower.hasPrefix($0) })
            || (trimmed.hasSuffix("?") && words.count >= 2)
        if isDirectQuestion {
            return withinReplace ? .replaceLastQuestion(trimmed) : .newQuestion(trimmed)
        }

        // 3. Короткая поправка термина в первые 25 с после вопроса собеседника («Риси», «Основні риси», «Ні, риси»).
        if withinClarify, words.count <= maxClarifyWords {
            let hasCorrectionPrefix = correctionPrefixes.contains(where: { lower.hasPrefix($0) })
            let startsWithFiller = words.first.map { fillerWords.contains($0) } ?? false
            // Отсекаем фразы, начинающиеся с заполнителей пауз («добре, зараз…», «так, дивіться…»),
            // кроме явной поправки («ні, риси», «нет, …»).
            if hasCorrectionPrefix || (!startsWithFiller && words.contains(where: { !fillerWords.contains($0) && $0.count >= 4 })) {
                return .clarifyLastQuestion(correction: trimmed)
            }
        }

        return .none
    }

    /// Убирает только явную служебную вводку диктовки («Повторю питання: …»), оставляя сам смысл переспроса.
    private static func stripMetaPrefix(_ text: String) -> String {
        let lower = text.lowercased()
        let meta = ["повторю питання:", "повторю вопрос:", "повторю питання ", "повторю вопрос ",
                    "перепитаю:", "переспрошу:", "repeat the question:"]
        for p in meta where lower.hasPrefix(p) {
            let rest = String(text.dropFirst(p.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return rest.isEmpty ? text : rest
        }
        return text
    }

    private static func extractWords(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
