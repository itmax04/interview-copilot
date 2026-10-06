import Foundation

/// Режим ответа — R-08.
public enum AnswerMode: String, Codable, CaseIterable, Sendable {
    case bankOnly
    case bankAndHint
    case generateAlways

    public var title: String {
        switch self {
        case .bankOnly: "Question bank only"
        case .bankAndHint: "Bank + hint"
        case .generateAlways: "Generate every answer"
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
        case .auto: "Auto (UK/RU/EN)"
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

    public var displayName: String {
        switch self {
        case .gemini: "Gemini"
        case .deepseek: "DeepSeek"
        case .anthropic: "Claude"
        }
    }
}

/// Состояние слушания для строки «● Listening — <app>» — R-15.
public enum ListeningStatus: Sendable, Equatable {
    case listening(source: String)
    case paused(source: String)
    case noPermission
    case idle

    public var dot: StatusDot {
        switch self {
        case .listening: .green
        case .paused, .idle: .gray
        case .noPermission: .red
        }
    }
}

public enum StatusDot: Sendable, Equatable {
    case green, gray, red
}
