import Foundation

/// Результат проверки ключа (R-18 Keys → «Проверить»). Значение ключа в результат не попадает.
public enum KeyCheckResult: Equatable, Sendable {
    case ok(models: [String])
    /// 400/401/403 — «ключ недействителен» (R-09).
    case invalidKey(status: Int, message: String)
    case failed(message: String)

    public var summary: String {
        switch self {
        case .ok(let models): L10n.f("OK · моделей: %lld", models.count)
        case .invalidKey(let status, let message): L10n.f("Ключ недействителен (HTTP %lld)", status) + (message.isEmpty ? "" : ": \(message)")
        case .failed(let message): L10n.f("Ошибка: %@", message)
        }
    }
}

public struct KeyVerifier: Sendable {
    let transport: HTTPTransport

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func verify(_ provider: ProviderID, key: String) async -> KeyCheckResult {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .failed(message: L10n.t("нет ключа")) }
        if provider == .custom, CustomEndpoint.shared.baseURL == nil {
            return .failed(message: L10n.t("не задан адрес API (https://…/v1)"))
        }
        do {
            let (data, response) = try await transport.data(for: ProviderEndpoints.listModels(provider, key: key))
            switch response.statusCode {
            case 200..<300:
                return .ok(models: Self.parseModelIDs(provider, data))
            case 400, 401, 403:
                return .invalidKey(status: response.statusCode, message: Self.errorMessage(data, redacting: key))
            case 429:
                return .failed(message: L10n.t("лимит запросов (HTTP 429), повторите позже"))
            default:
                let detail = Self.errorMessage(data, redacting: key)
                return .failed(message: "HTTP \(response.statusCode)" + (detail.isEmpty ? "" : ": \(detail)"))
            }
        } catch let error as URLError {
            return .failed(message: L10n.f("сеть: %@", error.code == .timedOut ? L10n.t("таймаут") : error.localizedDescription))
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    /// Gemini: `models[].name` = "models/<id>"; DeepSeek и Anthropic: `data[].id`.
    static func parseModelIDs(_ provider: ProviderID, _ data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        switch provider {
        case .gemini:
            let models = json["models"] as? [[String: Any]] ?? []
            return models.compactMap { $0["name"] as? String }.map {
                $0.hasPrefix("models/") ? String($0.dropFirst("models/".count)) : $0
            }
        case .deepseek, .anthropic, .groq, .cerebras, .custom:
            let models = json["data"] as? [[String: Any]] ?? []
            return models.compactMap { $0["id"] as? String }
        }
    }

    /// Текст ошибки провайдера (`error.message`), без значения ключа, не длиннее 160 символов.
    static func errorMessage(_ data: Data, redacting key: String) -> String {
        var message = ""
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any], let m = error["message"] as? String {
                message = m
            } else if let m = json["message"] as? String {
                message = m
            }
        }
        if key.count >= 8 { message = message.replacingOccurrences(of: key, with: "[key]") } // короткие тестовые значения не трогаем
        return String(message.prefix(160))
    }
}
