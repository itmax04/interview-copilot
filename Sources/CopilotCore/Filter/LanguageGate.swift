import Foundation
import NaturalLanguage

/// Фильтр языка реплики — COPILOT-05 R-05, R-06. Чистая логика: итоговый текст → «оставить» или «серым с причиной».
///
/// - Разрешено: Українська / Русский → {uk, ru} (одна группа: Parakeet пишет украинскую речь то «по-русски», Q7);
///   English → {en}; Auto → {uk, ru, en} (Q12).
/// - Латинские слова внутри фразы на разрешённом языке не мешают: фраза оценивается по большинству слов (Q9).
/// - Целиком английская фраза при uk/ru: в канале звонка проходит (Q8); в микрофоне и «Весь системный звук» — только
///   короткая (≤ 4 слов) и из терминов словаря (Q9).
/// - Фраза короче 3 слов, язык которой не очевиден, не отбрасывается: лучше пропустить шум, чем потерять вопрос.
public struct LanguageGate: Sendable {
    public enum Channel: String, Sendable {
        /// Звук приложения созвона — интервьюеры.
        case call
        /// Микрофон Mac.
        case mic
        /// «Весь системный звук»: кроме звонка там видео и уведомления — правила строже, как у микрофона (Q8).
        case allSystem
    }

    public enum Verdict: Sendable, Equatable {
        case keep
        /// Код языка фразы («de», «en», «uk/ru») — для серой строки и журнала.
        case drop(language: String)
    }

    public var allowed: Set<String>
    public var terms: TermDictionary

    /// Не больше стольких слов в английской фразе-термине (Q9).
    public static let maxTermPhraseWords = 4
    /// Короче — язык не очевиден, фраза не отбрасывается.
    public static let minWordsToDrop = 3

    public init(setting: RecognitionLanguage, terms: TermDictionary = TermDictionary()) {
        switch setting {
        case .uk, .ru: allowed = ["slavic"]
        case .en: allowed = ["en"]
        case .auto: allowed = ["slavic", "en"]
        }
        self.terms = terms
    }

    public func check(_ text: String, channel: Channel) -> Verdict {
        let words = Self.words(text)
        guard !words.isEmpty else { return .keep }
        let cyrillic = words.filter(Self.isCyrillic).count
        let latin = words.filter(Self.isLatin).count
        let other = words.count - cyrillic - latin

        if cyrillic >= latin && cyrillic >= other {
            return allowed.contains("slavic") || words.count < Self.minWordsToDrop ? .keep : .drop(language: "uk/ru")
        }
        if other > latin {
            return words.count < Self.minWordsToDrop ? .keep : .drop(language: Self.dominantLanguage(text) ?? "?")
        }
        // Латиница: английский или другой язык (немецкий из ТВ и т. п.).
        let allTerms = terms.allTerms(words)
        // Лимит — по значимым словам: «pull request and code review» — четыре термина.
        let meaningful = words.filter { !BuiltinTerms.glue.contains($0) }.count
        if allTerms && meaningful <= Self.maxTermPhraseWords { return .keep }
        let language = Self.dominantLanguage(text)
        let isEnglish = language == nil || language == "en"
        if !isEnglish {
            // Короткое или похожее на набор терминов («Kubernetes Deployment») — не отбрасываем.
            if words.count < Self.minWordsToDrop || allTerms { return .keep }
            return .drop(language: language ?? "?")
        }
        if allowed.contains("en") || channel == .call { return .keep }
        return words.count < Self.minWordsToDrop ? .keep : .drop(language: "en")
    }

    // MARK: Разбор

    static func words(_ text: String) -> [String] {
        text.lowercased()
            .split { !($0.isLetter || $0.isNumber || $0 == "'" || $0 == "’" || $0 == "-" || $0 == "+" || $0 == "#" || $0 == "/" || $0 == ".") }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".-/'’")) }
            .filter { $0.contains { $0.isLetter } }
    }

    static func isCyrillic(_ word: String) -> Bool {
        word.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
    }

    static func isLatin(_ word: String) -> Bool {
        !isCyrillic(word) && word.unicodeScalars.contains { $0.properties.isAlphabetic && $0.value < 0x0250 }
    }

    /// Язык латинского текста по Apple NaturalLanguage (на устройстве). nil — не определён.
    static func dominantLanguage(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, probability) = recognizer.languageHypotheses(withMaximum: 1).first, probability >= 0.5 else { return nil }
        return language.rawValue
    }
}

/// Словарь английских терминов, которые сохраняются в речи на другом языке (COPILOT-05 R-05, Q9):
/// встроенный IT-список, слова латиницей из резюме, вакансии и базы вопросов.
public struct TermDictionary: Sendable, Equatable {
    public private(set) var words: Set<String>

    public init(extra: [String] = []) {
        words = BuiltinTerms.words
        add(texts: extra)
    }

    /// Слова латиницей из текстов профиля (резюме, вакансия, вопросы и ответы базы).
    public mutating func add(texts: [String]) {
        for text in texts {
            for word in LanguageGate.words(text) where LanguageGate.isLatin(word) && word.count >= 2 {
                words.insert(word)
            }
        }
    }

    /// Все слова фразы — термины или служебные слова между ними («CI and CD», «pull request»).
    public func allTerms(_ phraseWords: [String]) -> Bool {
        let meaningful = phraseWords.filter { !BuiltinTerms.glue.contains($0) }
        return !meaningful.isEmpty && meaningful.allSatisfy { words.contains($0) }
    }
}
