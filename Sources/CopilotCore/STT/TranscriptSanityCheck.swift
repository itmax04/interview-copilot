import Foundation

/// Быстрая проверка внятности распознанной реплики до отправки в LLM (E-04).
/// Выявляет явно битые / оборванные обрывки STT при перебиваниях на динамиках,
/// чтобы в режиме «Экзамен» модель не выдумывала ответ на шум, а честно предупредила о неразборчивости.
public enum TranscriptSanityCheck {
    /// Возвращает `true`, если текст выглядит как невнятный обрывок / мусор распознавания.
    public static func looksUnclear(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        // Известные короткие уточнения и явные вопросы с «?» считаются осмысленными.
        if TurnDetector.isShortFollowUp(trimmed) || FollowUpDetector.isFollowUp(trimmed) {
            return hasGarbledTokens(trimmed)
        }

        let words = trimmed.split(whereSeparator: \.isWhitespace).map {
            $0.trimmingCharacters(in: .punctuationCharacters)
        }.filter { !$0.isEmpty }
        guard !words.isEmpty else { return true }

        // 1–2 очень коротких слова без знака «?» и без ключевого слова вопроса — вероятный обрывок.
        if words.count <= 2, !trimmed.hasSuffix("?") {
            let totalLetters = words.joined().filter(\.isLetter).count
            if totalLetters < 5 { return true }
        }

        return hasGarbledTokens(trimmed)
    }

    private static func hasGarbledTokens(_ text: String) -> Bool {
        if text.contains("\u{FFFD}") { return true }
        let guarder = OutputSanityGuard(config: .init(expectedLanguage: nil, requireUnderstoodLine: false))
        if let issue = guarder.check(text, isFinal: false) {
            switch issue {
            case .foreignScript, .mixedWordScript, .consonantGibberish, .combiningMarks:
                return true
            default:
                break
            }
        }
        return false
    }
}
