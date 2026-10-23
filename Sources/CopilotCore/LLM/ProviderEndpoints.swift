import Foundation

/// Адреса и заголовки API провайдеров. Ключ передаётся только в заголовке по HTTPS (R-23).
/// Источники: Gemini — ai.google.dev/api/models; DeepSeek — api-docs.deepseek.com/api/list-models;
/// Anthropic — skill `claude-api` (curl/examples.md, «Required Headers»);
/// Groq — console.groq.com/docs/openai; Cerebras — inference-docs.cerebras.ai/resources/openai (2026-10-23).
public enum ProviderEndpoints {
    public static let geminiBase = URL(string: "https://generativelanguage.googleapis.com/v1beta")!
    public static let deepseekBase = URL(string: "https://api.deepseek.com")!
    public static let anthropicBase = URL(string: "https://api.anthropic.com/v1")!
    public static let anthropicVersion = "2023-06-01"
    public static let groqBase = URL(string: "https://api.groq.com/openai/v1")!
    public static let cerebrasBase = URL(string: "https://api.cerebras.ai/v1")!

    /// База OpenAI-совместимых провайдеров. Для своего API — адрес из настроек (`CustomEndpoint`);
    /// пока он не задан, запрос не отправляется (`OpenAICompatibleProvider`, `KeyVerifier`).
    public static func openAIBase(_ provider: ProviderID) -> URL {
        switch provider {
        case .groq: groqBase
        case .cerebras: cerebrasBase
        case .custom: CustomEndpoint.shared.baseURL ?? URL(string: "https://localhost.invalid")!
        default: deepseekBase
        }
    }

    /// Адрес своего API (COPILOT-04 R-06): HTTPS; HTTP — только для этого Mac (Ollama, LM Studio),
    /// иначе ключ ушёл бы открытым текстом (R-23). Завершающий «/» и `/chat/completions` отрезаются.
    public static func customBaseURL(_ text: String) -> URL? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in ["/chat/completions", "/"] where t.hasSuffix(suffix) { t = String(t.dropLast(suffix.count)) }
        guard let url = URL(string: t), let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(), !host.isEmpty
        else { return nil }
        if scheme == "https" { return url }
        if scheme == "http", ["localhost", "127.0.0.1", "::1"].contains(host) { return url }
        return nil
    }

    /// Запрос списка моделей — проверка ключа (R-18 «Проверить») и ID моделей (P-07).
    public static func listModels(_ provider: ProviderID, key: String) -> URLRequest {
        var request: URLRequest
        switch provider {
        case .gemini:
            var c = URLComponents(url: geminiBase.appendingPathComponent("models"), resolvingAgainstBaseURL: false)!
            c.queryItems = [URLQueryItem(name: "pageSize", value: "1000")]
            request = URLRequest(url: c.url!)
        case .deepseek, .groq, .cerebras, .custom:
            request = URLRequest(url: openAIBase(provider).appendingPathComponent("models"))
        case .anthropic:
            var c = URLComponents(url: anthropicBase.appendingPathComponent("models"), resolvingAgainstBaseURL: false)!
            c.queryItems = [URLQueryItem(name: "limit", value: "1000")]
            request = URLRequest(url: c.url!)
        }
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        authorize(&request, provider: provider, key: key)
        return request
    }

    public static func authorize(_ request: inout URLRequest, provider: ProviderID, key: String) {
        switch provider {
        case .gemini:
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        case .deepseek, .groq, .cerebras, .custom:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        }
    }
}

/// Текущий адрес своего API (COPILOT-04 R-06). Обновляется из настроек: при применении настроек и при сборке цепочки.
public final class CustomEndpoint: @unchecked Sendable {
    public static let shared = CustomEndpoint()
    private let lock = NSLock()
    private var url: URL?

    public var baseURL: URL? {
        get { lock.withLock { url } }
        set { lock.withLock { url = newValue } }
    }

    public func update(from settings: AppSettings) {
        baseURL = ProviderEndpoints.customBaseURL(settings.customBaseURL)
    }
}
