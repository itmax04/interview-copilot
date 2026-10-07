import Foundation

/// Сообщение для модели. Изображения — JPEG (скриншот, R-14).
public struct LLMMessage: Sendable, Equatable {
    public enum Role: String, Sendable { case user, assistant }
    public var role: Role
    public var text: String
    public var images: [Data]

    public init(role: Role, text: String, images: [Data] = []) {
        self.role = role
        self.text = text
        self.images = images
    }
}

/// Назначение запроса — влияет на параметры (длина ответа, глубина рассуждения).
public enum LLMPurpose: String, Sendable {
    /// Подсказка на ход (R-11): коротко и быстро.
    case hint
    /// Сильная модель вручную (R-13): минимальная задержка, max_tokens 1024.
    case strong
    /// Решение задачи по скриншоту (R-14): нужен код, ответ длиннее.
    case screenshot
}

public struct LLMRequest: Sendable, Equatable {
    /// Постоянная системная часть (кэшируется у Anthropic, R-11).
    public var system: String
    public var messages: [LLMMessage]
    public var maxTokens: Int
    public var purpose: LLMPurpose

    public init(system: String, messages: [LLMMessage], maxTokens: Int, purpose: LLMPurpose) {
        self.system = system
        self.messages = messages
        self.maxTokens = maxTokens
        self.purpose = purpose
    }
}

public struct TokenUsage: Sendable, Equatable {
    public var input: Int
    public var output: Int
    /// Для Anthropic: прочитано из кэша промпта.
    public var cachedInput: Int

    public init(input: Int = 0, output: Int = 0, cachedInput: Int = 0) {
        self.input = input
        self.output = output
        self.cachedInput = cachedInput
    }
}

/// События потока от провайдера.
public enum LLMEvent: Sendable, Equatable {
    /// Фактическая модель (у Anthropic может отличаться из-за серверного fallback).
    case model(String)
    case text(String)
    case usage(TokenUsage)
    /// Конец ответа; `stopReason` — как у провайдера.
    case done(stopReason: String?)
}

public enum LLMError: Error, Equatable, CustomStringConvertible {
    case http(status: Int, message: String)
    case network(String)
    /// Первый токен не пришёл за отведённое время (R-09: 4 с).
    case firstTokenTimeout
    /// Модель отказалась (`stop_reason = refusal`, у Gemini — `SAFETY`).
    case refusal(String?)
    case noKey
    case cancelled
    case badResponse(String)

    /// 400/401/403 — ключ или запрос недействительны: не повторять у того же провайдера (R-09).
    public var isInvalidKey: Bool {
        if case .http(let status, _) = self { return status == 400 || status == 401 || status == 403 }
        return false
    }

    /// Триггер перехода к следующему провайдеру (R-09).
    public var triggersFallback: Bool {
        switch self {
        // Любая HTTP-ошибка — к следующему провайдеру (404 из-за опечатки в ID модели тоже, S-04);
        // 400/401/403 у этого провайдера больше не пробуются (R-09).
        case .http: true
        case .network, .firstTokenTimeout, .refusal, .noKey, .badResponse: true
        case .cancelled: false
        }
    }

    public var description: String {
        switch self {
        case .http(429, _): "лимит запросов (429)"
        case .http(let s, let m) where s == 401 || s == 403: "ключ недействителен (HTTP \(s))" + (m.isEmpty ? "" : ": \(m)")
        case .http(400, let m): "неверный запрос или ключ (HTTP 400)" + (m.isEmpty ? "" : ": \(m)")
        case .http(402, _): "закончились средства на счёте (402)"
        case .http(let s, let m): "HTTP \(s)" + (m.isEmpty ? "" : ": \(m)")
        case .network(let m): "сеть: \(m)"
        case .firstTokenTimeout: "нет ответа за отведённое время"
        case .refusal(let c): "модель отказалась отвечать" + (c.map { " (\($0))" } ?? "")
        case .noKey: "нет ключа"
        case .cancelled: "отменено"
        case .badResponse(let m): "неожиданный ответ: \(m)"
        }
    }
}

/// Провайдер языковой модели (ADR-0001 п. 7): свой HTTP-клиент с SSE, без SDK.
public protocol LLMProvider: Sendable {
    var id: ProviderID { get }
    func stream(_ request: LLMRequest, model: String, key: String) -> AsyncThrowingStream<LLMEvent, Error>
}
