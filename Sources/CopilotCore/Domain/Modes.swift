import Foundation

/// Режим ответа — R-08.
public enum AnswerMode: String, Codable, CaseIterable, Sendable {
    case bankOnly
    case bankAndHint
    case generateAlways

    public var title: String {
        switch self {
        case .bankOnly: L10n.t("Только база вопросов")
        case .bankAndHint: L10n.t("База + подсказка")
        case .generateAlways: L10n.t("Генерировать каждый ответ")
        }
    }
}

/// Язык распознавания — R-03.
public enum RecognitionLanguage: String, Codable, CaseIterable, Sendable {
    case auto
    case uk
    case ru
    case en

    /// Подпись в меню «Language: …» (R-15: «Auto (UK/RU/EN)»).
    public var menuTitle: String {
        switch self {
        case .auto: L10n.t("Авто (UK/RU/EN)")
        case .uk: "Українська"
        case .ru: "Русский"
        case .en: "English"
        }
    }

    /// Код языка для whisper; `nil` — автоопределение.
    public var whisperCode: String? { self == .auto ? nil : rawValue }
}

/// Провайдер языковой модели — R-09.
public enum ProviderID: String, Codable, CaseIterable, Sendable {
    case gemini
    case deepseek
    case anthropic
    /// Groq (COPILOT-03, R-36): бесплатный тариф, первый токен за доли секунды.
    case groq
    /// Cerebras (R-36): очень быстрый; постоянного бесплатного тарифа нет — пробные кредиты.
    case cerebras
    /// Свой OpenAI-совместимый API (COPILOT-04 R-06): адрес и модель — в настройках, ключ — в Связке ключей.
    case custom

    public var displayName: String {
        switch self {
        case .gemini: "Gemini"
        case .deepseek: "DeepSeek"
        case .anthropic: "Claude"
        case .groq: "Groq"
        case .cerebras: "Cerebras"
        case .custom: L10n.t("Свой API")
        }
    }

    /// OpenAI-совместимый Chat Completions (`data[].id` в списке моделей, Bearer-ключ).
    public var isOpenAICompatible: Bool { self == .deepseek || self == .groq || self == .cerebras || self == .custom }
}

/// Состояние слушания для строки «● Listening — <app>» — R-15.
public enum ListeningStatus: Sendable, Equatable {
    case listening(source: String)
    case paused(source: String)
    case noPermission
    case idle
    /// Сессии нет — приложение не слушает (COPILOT-09 R-02).
    case noSession

    public var dot: StatusDot {
        switch self {
        case .listening: .green
        case .paused, .idle, .noSession: .gray
        case .noPermission: .red
        }
    }
}

public enum StatusDot: Sendable, Equatable {
    case green, gray, red
}
