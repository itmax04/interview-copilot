import Foundation

/// Тип сессии — COPILOT-09 R-06 (решение владельца Q5).
public enum SessionType: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Собеседование: резюме, вакансия, материалы, вопросы профиля; ответ от лица кандидата.
    case interview
    /// Обычный звонок: «что сказать» по теме, инструкциям и материалам — без резюме и карточек (Q14).
    case regular
    /// ИИ-собеседование (COPILOT-03) — запуск из мастера.
    case mock

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .interview: "Собеседование"
        case .regular: "Обычный звонок"
        case .mock: "ИИ-собеседование"
        }
    }
}

/// Настройки сессии из мастера «Создать сессию» — COPILOT-09 R-01. Последние значения — по умолчанию для следующей.
public struct SessionConfig: Codable, Equatable, Sendable {
    public var type: SessionType = .interview
    public var profileID: String?
    public var company = ""
    public var jobDescription = ""
    public var language: RecognitionLanguage = .auto
    /// Модель, с которой начинать цепочку (nil — порядок из настроек).
    public var firstProvider: ProviderID?
    /// Указания на эту сессию — важнее инструкций профиля и общих (Q7).
    public var instructions = ""
    /// Auto Generate (Q4): отвечать на найденные вопросы самому; выключено — только ручной Answer.
    public var autoGenerate = true
    /// Сохранять расшифровку и ответы в историю.
    public var saveTranscript = true
    /// Разбор после End (Q15).
    public var reviewAfterEnd = true
    /// План длительности, минут (0 — без плана); предупреждение за 5 минут (Q12).
    public var plannedMinutes = 0

    public init() {}

    public static let planWarningMinutes = 5
    public static let plannedMinutesRange = 0...240

    /// Поля, которые не переносятся в следующую сессию: компания и вакансия — свои у каждого звонка (исследование 7.1:
    /// «повторное резюме не должно молча переносить вакансию чужой компании»), указания на сессию — тоже.
    public func defaultsForNext() -> SessionConfig {
        var c = self
        c.company = ""
        c.jobDescription = ""
        c.instructions = ""
        c.plannedMinutes = min(max(c.plannedMinutes, Self.plannedMinutesRange.lowerBound), Self.plannedMinutesRange.upperBound)
        return c
    }

    /// Что не так с заполнением (шаг «Детали»); пусто — можно дальше.
    public func validationErrors(profileExists: Bool) -> [String] {
        var out: [String] = []
        if type == .interview, !profileExists { out.append("Выберите профиль или создайте новый") }
        if !Self.plannedMinutesRange.contains(plannedMinutes) { out.append("План — от 0 до 240 минут") }
        return out
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SessionConfig()
        func v<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? fallback }
        type = v(.type, d.type)
        profileID = v(.profileID, d.profileID)
        company = v(.company, d.company)
        jobDescription = v(.jobDescription, d.jobDescription)
        language = v(.language, d.language)
        firstProvider = v(.firstProvider, d.firstProvider)
        instructions = v(.instructions, d.instructions)
        autoGenerate = v(.autoGenerate, d.autoGenerate)
        saveTranscript = v(.saveTranscript, d.saveTranscript)
        reviewAfterEnd = v(.reviewAfterEnd, d.reviewAfterEnd)
        plannedMinutes = v(.plannedMinutes, d.plannedMinutes)
    }

    enum CodingKeys: String, CodingKey {
        case type, profileID, company, jobDescription, language, firstProvider, instructions, autoGenerate, saveTranscript,
             reviewAfterEnd, plannedMinutes
    }

    /// Цепочка сессии: выбранная модель — первой, остальные — в прежнем порядке.
    public func chain(from base: [ProviderID]) -> [ProviderID] {
        guard let first = firstProvider, base.contains(first) else { return base }
        return [first] + base.filter { $0 != first }
    }
}

/// Жизненный цикл сессии — COPILOT-09 R-02.
public enum SessionPhase: Equatable, Sendable {
    /// Сессии нет — приложение не слушает.
    case none
    case starting
    case active
    case ending
    case failed(String)
}

/// Таймер сессии и предупреждение по плану (R-02, Q12).
public struct SessionClock: Equatable, Sendable {
    public var startedAt: Date
    public var plannedMinutes: Int

    public init(startedAt: Date, plannedMinutes: Int) {
        self.startedAt = startedAt
        self.plannedMinutes = plannedMinutes
    }

    /// «12:47» или «1:02:05».
    public func elapsedText(now: Date = Date()) -> String {
        let s = max(0, Int(now.timeIntervalSince(startedAt)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    /// Пора предупредить: до конца плана ≤ 5 минут (и план задан).
    public func shouldWarn(now: Date = Date()) -> Bool {
        guard plannedMinutes > 0 else { return false }
        let left = Double(plannedMinutes * 60) - now.timeIntervalSince(startedAt)
        return left <= Double(SessionConfig.planWarningMinutes * 60)
    }

    /// Минут до конца плана (отрицательное — план превышен); nil — плана нет.
    public func minutesLeft(now: Date = Date()) -> Int? {
        guard plannedMinutes > 0 else { return nil }
        return Int((Double(plannedMinutes * 60) - now.timeIntervalSince(startedAt)) / 60)
    }
}
