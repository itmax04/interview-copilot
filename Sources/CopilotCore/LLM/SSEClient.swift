import Foundation

/// Событие Server-Sent Events.
public struct SSEEvent: Sendable, Equatable {
    public var event: String?
    public var data: String
}

/// Потоковый HTTP: статус и строки тела. Подменяется в тестах фикстурами (`Tests/Fixtures/`).
public protocol StreamingTransport: Sendable {
    func lines(for request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<String, Error>)
}

public struct URLSessionStreamingTransport: StreamingTransport {
    let session: URLSession

    public init(session: URLSession = URLSessionStreamingTransport.makeSession()) {
        self.session = session
    }

    public static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.urlCache = nil
        return URLSession(configuration: config)
    }

    public func lines(for request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<String, Error>) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw LLMError.badResponse(L10n.t("не HTTP")) }
        let stream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines { continuation.yield(line) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return (http, stream)
    }
}

/// Разбор SSE: строки `event:` / `data:`, событие заканчивается пустой строкой.
/// `URLSession.AsyncBytes.lines` пропускает пустые строки, поэтому новое событие начинается и с нового `event:`/`data:`
/// после уже собранного `data:`.
public struct SSEParser {
    private var event: String?
    private var data: [String] = []

    public init() {}

    /// Подать строку; возвращает готовые события.
    public mutating func feed(_ line: String) -> [SSEEvent] {
        var out: [SSEEvent] = []
        if line.isEmpty {
            if let e = flush() { out.append(e) }
            return out
        }
        if line.hasPrefix(":") { return out } // комментарий
        let (field, value) = Self.split(line)
        switch field {
        case "event":
            if !data.isEmpty, let e = flush() { out.append(e) }
            event = value
        case "data":
            // Без пустых строк-разделителей каждая строка data: — отдельное событие (так шлют Gemini и OpenAI-совместимые).
            if !data.isEmpty, let e = flush() { out.append(e) }
            data.append(value)
        default:
            break
        }
        return out
    }

    public mutating func finish() -> SSEEvent? { flush() }

    private mutating func flush() -> SSEEvent? {
        defer { event = nil; data = [] }
        guard !data.isEmpty else { return nil }
        return SSEEvent(event: event, data: data.joined(separator: "\n"))
    }

    static func split(_ line: String) -> (String, String) {
        guard let colon = line.firstIndex(of: ":") else { return (line, "") }
        var value = line[line.index(after: colon)...]
        if value.hasPrefix(" ") { value = value.dropFirst() }
        return (String(line[..<colon]), String(value))
    }
}

enum SSE {
    /// Открывает поток: при статусе не 2xx читает тело и бросает `LLMError.http` с текстом ошибки (без ключа).
    static func open(_ request: URLRequest, transport: StreamingTransport, key: String) async throws -> AsyncThrowingStream<SSEEvent, Error> {
        let response: HTTPURLResponse
        let lines: AsyncThrowingStream<String, Error>
        do {
            (response, lines) = try await transport.lines(for: request)
        } catch let error as URLError {
            throw error.code == .cancelled ? LLMError.cancelled : LLMError.network(error.localizedDescription)
        }
        guard (200..<300).contains(response.statusCode) else {
            var body = ""
            do {
                for try await line in lines {
                    body += line
                    if body.count > 4000 { break }
                }
            } catch {}
            var message = errorMessage(body, key: key)
            // 429: когда снова пробовать этот ключ — до обрезки текста (у Groq «try again in» — в конце длинного сообщения).
            if response.statusCode == 429,
               let wait = RetryHint.seconds(header: response.value(forHTTPHeaderField: "retry-after"), body: body) {
                message = RetryHint.tag(wait) + message
            }
            throw LLMError.http(status: response.statusCode, message: message)
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                var parser = SSEParser()
                do {
                    for try await line in lines {
                        for e in parser.feed(line) { continuation.yield(e) }
                    }
                    if let e = parser.finish() { continuation.yield(e) }
                    continuation.finish()
                } catch let error as URLError {
                    continuation.finish(throwing: error.code == .cancelled ? LLMError.cancelled : LLMError.network(error.localizedDescription))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func errorMessage(_ body: String, key: String) -> String {
        var message = ""
        if let data = body.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) {
            let dict = (json as? [String: Any]) ?? ((json as? [[String: Any]])?.first ?? [:])
            if let error = dict["error"] as? [String: Any], let m = error["message"] as? String { message = m }
            else if let m = dict["message"] as? String { message = m }
        } else if !body.hasPrefix("<") {
            // Простой текст (прокси, «свой API»): причина видна владельцу; HTML-страницы ошибок не показываем.
            message = body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if key.count >= 8 { message = message.replacingOccurrences(of: key, with: "[key]") } // короткие тестовые значения не трогаем
        return String(redactIdentifiers(message).prefix(200))
    }

    /// Идентификаторы аккаунта и похожее на ключи — не в журнал и не в интерфейс: Groq пишет в ошибке 429 id организации
    /// (`org_…`), а прокси иногда повторяют ключ из запроса (COPILOT-12).
    static func redactIdentifiers(_ text: String) -> String {
        var out = text
        for (pattern, replacement) in [(#"org_[A-Za-z0-9]{6,}"#, "org_[id]"),
                                       (#"\b(?:gsk_|sk-ant-|sk-|csk-|AIza)[A-Za-z0-9_\-]{12,}"#, "[key]")] {
            out = out.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return out
    }

    static func json(_ data: String) -> [String: Any]? {
        guard let d = data.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }
}
