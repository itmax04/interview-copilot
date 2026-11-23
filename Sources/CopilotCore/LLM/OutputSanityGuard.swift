import Foundation

/// Проверка качества сгенерированного ответа (защита от «случайных букв», смеси языков и деградации модели).
/// Работает синхронно, без доп. вызовов LLM; при срабатывании `AnswerController` отбрасывает сломанный поток
/// и повторяет запрос на следующей модели цепочки (например, Groq → Gemini).
public struct OutputSanityGuard: Sendable {
    public enum Issue: String, Sendable, Equatable {
        /// Иероглифы (CJK), арабский, деванагари, тайский, иврит, символ замены U+FFFD или управляющие символы.
        case foreignScript = "foreign_script"
        /// Кириллица и латиница смешаны внутри одного неразрывного слова (не дефисный термин вроде `iOS-застосунку`).
        case mixedWordScript = "mixed_word_script"
        /// Избыточные комбинирующие диакритические знаки после NFC-нормализации (артефакты вроде `отдельну́ю`).
        case combiningMarks = "combining_marks"
        /// Срыв целевого языка (например, русские буквы `ы/э/ё/ъ` в украинском ответе или `і/ї/є/ґ` в русском).
        case languageMix = "language_mix"
        /// Зацикливание токенов / фраз.
        case repetitionLoop = "repetition_loop"
        /// Случайный набор согласных в слове (не аббревиатура).
        case consonantGibberish = "consonant_gibberish"
        /// Утечка служебных XML-тегов промпта в ответ пользователю.
        case promptLeak = "prompt_leak"
        /// Финальный ответ слишком короткий (и не является маркером «—»).
        case tooShort = "too_short"
        /// В финальном ответе отсутствует обязательная строка «❓ …».
        case missingUnderstoodLine = "missing_understood_line"
    }

    public struct Config: Sendable, Equatable {
        /// Ожидаемый язык ответа (`"uk"`, `"ru"`, `"en"` или `nil` — любой).
        public var expectedLanguage: String?
        /// Проверять наличие строки «❓ …» на завершённом ответе.
        public var requireUnderstoodLine: Bool
        /// Порог буферизации перед первым показом стрима (символов), чтобы мусор не мигал на экране.
        public var earlyBufferChars: Int

        public init(expectedLanguage: String? = nil, requireUnderstoodLine: Bool = false, earlyBufferChars: Int = 90) {
            self.expectedLanguage = expectedLanguage
            self.requireUnderstoodLine = requireUnderstoodLine
            self.earlyBufferChars = earlyBufferChars
        }
    }

    public var config: Config

    public init(config: Config = Config()) {
        self.config = config
    }

    /// Проверяет частичный (`isFinal == false`) или завершённый (`isFinal == true`) текст ответа.
    /// Возвращает `nil`, если текст выглядит здоровым.
    public func check(_ rawText: String, isFinal: Bool) -> Issue? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return isFinal ? .tooShort : nil }
        if PromptBuilder.isNoAnswer(trimmed) { return nil }
        if !isFinal, trimmed.count <= 3, "—–-".contains(trimmed) { return nil }

        let nfc = trimmed.precomposedStringWithCanonicalMapping

        if hasPromptLeak(nfc) { return .promptLeak }
        if hasForeignScriptOrControl(nfc) { return .foreignScript }
        if hasMixedWordScript(nfc) { return .mixedWordScript }
        if hasRepetitionLoop(nfc) { return .repetitionLoop }
        if hasConsonantGibberish(nfc) { return .consonantGibberish }

        // Проверяем только сам ответ (без строки «❓», в которой может быть цитата из STT).
        let body = UnderstoodLine.answer(nfc)
        let targetForLang = body.isEmpty ? nfc : body

        if hasExcessiveCombiningMarks(targetForLang) { return .combiningMarks }
        if let lang = config.expectedLanguage, hasLanguageMix(targetForLang, expected: lang) { return .languageMix }

        if isFinal {
            if config.requireUnderstoodLine, UnderstoodLine.split(nfc).line == nil {
                return .missingUnderstoodLine
            }
            let meaningfulCount = targetForLang.unicodeScalars.filter { !$0.properties.isWhitespace }.count
            if meaningfulCount < 8 { return .tooShort }
        }

        return nil
    }

    // MARK: - Детекторы

    private static let leakedTokens = [
        "<materials>", "</materials>",
        "<interview_history>", "</interview_history>",
        "<earlier_in_interview>", "</earlier_in_interview>",
        "<active_topic>", "</active_topic>",
        "<active_task>", "</active_task>",
        "<owner_instructions>", "</owner_instructions>",
        "<profile>", "</profile>",
        "Shown suggestion (may not have been said)",
    ]

    private func hasPromptLeak(_ text: String) -> Bool {
        Self.leakedTokens.contains { text.contains($0) }
    }

    private func hasForeignScriptOrControl(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let v = scalar.value
            // Заменяющий символ битого UTF-8 или неожиданные управляющие символы (кроме \n, \r, \t).
            if v == 0xFFFD { return true }
            if v < 0x20, v != 0x09, v != 0x0A, v != 0x0D { return true }
            // CJK, Hiragana/Katakana, Hangul, Arabic, Hebrew, Devanagari, Thai, Bengali, Tamil.
            if (0x3040...0x30FF).contains(v)
                || (0x4E00...0x9FFF).contains(v)
                || (0x3400...0x4DBF).contains(v)
                || (0xAC00...0xD7AF).contains(v)
                || (0x0590...0x05FF).contains(v)
                || (0x0600...0x06FF).contains(v)
                || (0x0900...0x097F).contains(v)
                || (0x0E00...0x0E7F).contains(v) {
                return true
            }
        }
        return false
    }

    /// Кириллица + латиница внутри одного неразрывного буквенного слова (разбиваем по пробелам, дефисам и пунктуации).
    private func hasMixedWordScript(_ text: String) -> Bool {
        var suspiciousTokens = 0
        for token in letterTokens(in: text) {
            var cyr = 0
            var lat = 0
            for scalar in token.unicodeScalars {
                if Self.isCyrillic(scalar) { cyr += 1 }
                else if Self.isLatin(scalar) { lat += 1 }
            }
            if cyr > 0, lat > 0 {
                // Явная каша в одном слове (≥2 букв одного алфавита и ≥2 другого) — сразу брак.
                if cyr >= 2, lat >= 2 { return true }
                suspiciousTokens += 1
            }
        }
        return suspiciousTokens >= 2
    }

    /// После NFC-нормализации обычные укр/рус/англ буквы (`й`, `ї`, `ё`) уже слиты в один скаляр.
    /// Оставшиеся комбинирующие знаки (ударение U+0301 и т.п.) — признак артефактов генерации.
    private func hasExcessiveCombiningMarks(_ text: String) -> Bool {
        var strayMarks = 0
        for scalar in text.unicodeScalars {
            let cat = scalar.properties.generalCategory
            if cat == .nonspacingMark || cat == .enclosingMark {
                // Вариационные селекторы эмодзи (U+FE0E/U+FE0F) допустимы.
                if scalar.value == 0xFE0E || scalar.value == 0xFE0F { continue }
                strayMarks += 1
                if strayMarks >= 2 { return true }
            }
        }
        return false
    }

    private static let ruOnlyLetters: Set<Character> = ["ы", "э", "ё", "ъ"]
    private static let ukOnlyLetters: Set<Character> = ["і", "ї", "є", "ґ"]
    /// Частотные служебные слова, существующие только в русском (ловят чисто русский ответ при ожидаемом «uk» даже без ы/э/ё/ъ).
    private static let ruOnlyFunctionWords: Set<String> = [
        "это", "что", "как", "или", "только", "также", "можно", "нужно", "если", "когда",
        "чтобы", "который", "которая", "которое", "которые", "является", "являются",
        "потому", "поэтому", "между", "очень", "всегда", "здесь", "включает", "регулирует", "определяет",
    ]

    private func hasLanguageMix(_ text: String, expected: String) -> Bool {
        let lower = text.lowercased()
        let tokens = letterTokens(in: lower)
        let cyrTokens = tokens.filter { $0.unicodeScalars.contains(where: Self.isCyrillic) }
        guard cyrTokens.count >= 4 else { return false }

        switch expected {
        case "uk":
            let ruWords = cyrTokens.filter { word in word.contains { Self.ruOnlyLetters.contains($0) } }.count
            if ruWords >= 2 { return true }
            let ukWords = cyrTokens.filter { word in word.contains { Self.ukOnlyLetters.contains($0) } }.count
            if cyrTokens.count <= 10, ruWords >= 1, ukWords == 0 {
                return true
            }
            if cyrTokens.count >= 8, ukWords == 0 {
                let ruFunc = cyrTokens.filter { Self.ruOnlyFunctionWords.contains($0) }.count
                if ruFunc >= 2 || (ruWords >= 1 && ruFunc >= 1) { return true }
            }
            return false
        case "ru":
            let ukWords = cyrTokens.filter { word in word.contains { Self.ukOnlyLetters.contains($0) } }.count
            if ukWords >= 2 { return true }
            if cyrTokens.count <= 10, ukWords >= 1 {
                let ruWords = cyrTokens.filter { word in word.contains { Self.ruOnlyLetters.contains($0) } }.count
                if ruWords == 0 { return true }
            }
            return false
        default:
            return false
        }
    }

    /// Повторение одного фрагмента ≥ 16 символов 3+ раза подряд или одинаковых строк 3+ раза.
    private func hasRepetitionLoop(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.count >= 12 }
        if lines.count >= 3 {
            var counts: [String: Int] = [:]
            for l in lines {
                counts[l, default: 0] += 1
                if counts[l, default: 0] >= 3 { return true }
            }
        }
        let chars = Array(text.lowercased())
        guard chars.count >= 48 else { return false }
        // Ищем повторяющийся хвост (12..40 символов), повторенный 3 раза подряд.
        for period in 12...min(40, chars.count / 3) {
            let start = chars.count - period * 3
            let a = chars[start..<(start + period)]
            let b = chars[(start + period)..<(start + period * 2)]
            let c = chars[(start + period * 2)..<chars.count]
            if a.elementsEqual(b), b.elementsEqual(c) { return true }
        }
        return false
    }

    private static let vowels: Set<Character> = [
        "a", "e", "i", "o", "u", "y",
        "а", "е", "ё", "и", "і", "ї", "є", "о", "у", "ы", "э", "ю", "я",
    ]

    /// Длинные непроизносимые цепочки согласных внутри строчного слова (не аббревиатура в ВЕРХНЕМ РЕГИСТРЕ).
    private func hasConsonantGibberish(_ text: String) -> Bool {
        for token in letterTokens(in: text) {
            guard token.count >= 7 else { continue }
            // Пропускаем аббревиатуры полностью в верхнем регистре (HTTPS, PostgreSQL и т.п.).
            if token == token.uppercased() { continue }
            let hasCyr = token.unicodeScalars.contains(where: Self.isCyrillic)
            let limit = hasCyr ? 7 : 8
            var run = 0
            for ch in token.lowercased() {
                if Self.vowels.contains(ch) || ch == "ь" || ch == "ъ" {
                    run = 0
                } else {
                    run += 1
                    if run >= limit { return true }
                }
            }
        }
        return false
    }

    private func letterTokens(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for ch in text {
            if ch.isLetter {
                current.append(ch)
            } else if !current.isEmpty {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func isCyrillic(_ s: UnicodeScalar) -> Bool {
        (0x0400...0x04FF).contains(s.value) || (0x0500...0x052F).contains(s.value)
    }

    private static func isLatin(_ s: UnicodeScalar) -> Bool {
        (0x0041...0x005A).contains(s.value) || (0x0061...0x007A).contains(s.value)
    }
}
