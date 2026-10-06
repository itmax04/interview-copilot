import Foundation

/// Адреса и заголовки API провайдеров. Ключ передаётся только в заголовке по HTTPS (R-23).
/// Источники: Gemini — ai.google.dev/api/models; DeepSeek — api-docs.deepseek.com/api/list-models;
/// Anthropic — skill `claude-api` (curl/examples.md, «Required Headers»).
public enum ProviderEndpoints {
    public static let geminiBase = URL(string: "https://generativelanguage.googleapis.com/v1beta")!
    public static let deepseekBase = URL(string: "https://api.deepseek.com")!
    public static let anthropicBase = URL(string: "https://api.anthropic.com/v1")!
    public static let anthropicVersion = "2023-06-01"

    /// Запрос списка моделей — проверка ключа (R-18 «Проверить») и ID моделей (P-07).
    public static func listModels(_ provider: ProviderID, key: String) -> URLRequest {
        var request: URLRequest
        switch provider {
        case .gemini:
            var c = URLComponents(url: geminiBase.appendingPathComponent("models"), resolvingAgainstBaseURL: false)!
            c.queryItems = [URLQueryItem(name: "pageSize", value: "1000")]
            request = URLRequest(url: c.url!)
        case .deepseek:
            request = URLRequest(url: deepseekBase.appendingPathComponent("models"))
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
        case .deepseek:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        }
    }
}
