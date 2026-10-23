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

    /// База OpenAI-совместимых провайдеров.
    public static func openAIBase(_ provider: ProviderID) -> URL {
        switch provider {
        case .groq: groqBase
        case .cerebras: cerebrasBase
        default: deepseekBase
        }
    }

    /// Запрос списка моделей — проверка ключа (R-18 «Проверить») и ID моделей (P-07).
    public static func listModels(_ provider: ProviderID, key: String) -> URLRequest {
        var request: URLRequest
        switch provider {
        case .gemini:
            var c = URLComponents(url: geminiBase.appendingPathComponent("models"), resolvingAgainstBaseURL: false)!
            c.queryItems = [URLQueryItem(name: "pageSize", value: "1000")]
            request = URLRequest(url: c.url!)
        case .deepseek, .groq, .cerebras:
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
        case .deepseek, .groq, .cerebras:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        }
    }
}
