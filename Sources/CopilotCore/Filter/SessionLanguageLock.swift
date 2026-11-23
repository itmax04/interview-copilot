import Foundation

/// Язык сессии для фильтра — COPILOT-16 R-03, R-04. Чистая логика, без аудио и UI.
///
/// - При языке «Авто» после первых 3 оставленных фраз интервьюера (≥ 3 слов) одной группы (slavic или en) фильтр
///   закрепляется за этой группой до конца сессии. До этого фильтр ведёт себя как «Авто».
/// - Смешанные или короткие фразы замок не двигают: серия одной группы прерывается фразой другой группы.
/// - Если в сессии на uk/ru (заданной или закреплённой) подряд отброшены 2 фразы как `en`, один раз поднимается
///   подсказка «Разрешить английский»; действие разрешает английский до конца сессии (не настройка приложения).
/// - Начало сессии вызывает `reset()`.
public struct SessionLanguageLock: Sendable, Equatable {
    /// Сколько фраз одной группы закрепляют язык.
    public static let phrasesToLock = 3
    /// Минимум слов во фразе, которая учитывается.
    public static let minWords = 3
    /// Сколько отброшенных подряд `en`-фраз поднимают подсказку.
    public static let dropsToNotice = 2

    public private(set) var lockedGroup: String?
    public private(set) var englishAllowed = false
    public private(set) var noticeRaised = false
    private var streakGroup: String?
    private var streakCount = 0
    private var consecutiveEnglishDrops = 0

    public init() {}

    /// Новая сессия: всё с чистого листа.
    public mutating func reset() { self = SessionLanguageLock() }

    /// Язык для `LanguageGate` в этой сессии.
    public func effectiveSetting(_ base: RecognitionLanguage) -> RecognitionLanguage {
        guard base == .auto else {
            // Явный uk/ru + разрешённый английский → слависские языки и английский (как «Авто»).
            return englishAllowed && base != .en ? .auto : base
        }
        if englishAllowed { return .auto }
        switch lockedGroup {
        case "slavic": return .uk
        case "en": return .en
        default: return .auto
        }
    }

    /// Английский сейчас не разрешён в сессии на uk/ru: только тогда подсказка уместна.
    public func isSlavicOnly(_ base: RecognitionLanguage) -> Bool {
        let effective = effectiveSetting(base)
        return effective == .uk || effective == .ru
    }

    /// Фраза интервьюера оставлена фильтром. Возвращает группу, если именно эта фраза закрепила язык.
    @discardableResult
    public mutating func observeKept(_ text: String, base: RecognitionLanguage, terms: TermDictionary = TermDictionary()) -> String? {
        consecutiveEnglishDrops = 0
        guard base == .auto, lockedGroup == nil, !englishAllowed, Self.words(text).count >= Self.minWords else { return nil }
        // Смешанная фраза (≥ 3 слов, группы нет) прерывает серию; короткая серию не трогает.
        guard let group = Self.group(of: text, terms: terms) else { resetStreak(); return nil }
        if streakGroup == group { streakCount += 1 } else { streakGroup = group; streakCount = 1 }
        guard streakCount >= Self.phrasesToLock else { return nil }
        lockedGroup = group
        return group
    }

    /// Фраза отброшена фильтром с языком `language` («en», «de», «uk/ru»…). Возвращает true, когда пора поднять подсказку.
    public mutating func observeDrop(language: String, base: RecognitionLanguage) -> Bool {
        guard language == "en", isSlavicOnly(base) else { consecutiveEnglishDrops = 0; return false }
        consecutiveEnglishDrops += 1
        guard consecutiveEnglishDrops >= Self.dropsToNotice, !noticeRaised else { return false }
        noticeRaised = true
        return true
    }

    /// Владелец разрешил английский до конца сессии.
    public mutating func allowEnglish() {
        englishAllowed = true
        consecutiveEnglishDrops = 0
        resetStreak()
    }

    private mutating func resetStreak() { streakGroup = nil; streakCount = 0 }

    // MARK: Группа фразы

    static func words(_ text: String) -> [String] { LanguageGate.words(text) }

    /// «slavic» — кириллица; «en» — латиница, определённая как английская; иначе nil (смешанная/другой язык/термины).
    static func group(of text: String, terms: TermDictionary) -> String? {
        let words = words(text)
        guard words.count >= minWords else { return nil }
        let cyrillic = words.filter(LanguageGate.isCyrillic).count
        let latin = words.filter(LanguageGate.isLatin).count
        if cyrillic > latin { return "slavic" }
        if latin > cyrillic, !terms.allTerms(words), LanguageGate.dominantLanguage(text) == "en" { return "en" }
        return nil
    }
}
