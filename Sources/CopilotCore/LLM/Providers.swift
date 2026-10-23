import Foundation

/// Gemini: `streamGenerateContent?alt=sse` (ai.google.dev/api/generate-content), ключ — заголовок `x-goog-api-key` (R-23).
public struct GeminiProvider: LLMProvider {
    public let id = ProviderID.gemini
    let transport: StreamingTransport
    /// Уровень рассуждения для подсказок; nil — не передавать thinkingConfig (умолчание модели).
    let hintThinkingLevel: String?

    public init(transport: StreamingTransport = URLSessionStreamingTransport(), hintThinkingLevel: String? = "low") {
        self.transport = transport
        self.hintThinkingLevel = hintThinkingLevel
    }

    public func makeRequest(_ request: LLMRequest, model: String, key: String, withThinking: Bool = true) throws -> URLRequest {
        var c = URLComponents(url: ProviderEndpoints.geminiBase.appendingPathComponent("models/\(model):streamGenerateContent"),
                              resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "alt", value: "sse")]
        var r = URLRequest(url: c.url!)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        ProviderEndpoints.authorize(&r, provider: .gemini, key: key)
        let contents: [[String: Any]] = request.messages.map { m in
            var parts: [[String: Any]] = m.images.map { ["inline_data": ["mime_type": "image/jpeg", "data": $0.base64EncodedString()]] }
            parts.append(["text": m.text])
            return ["role": m.role == .user ? "user" : "model", "parts": parts]
        }
        var generation: [String: Any] = ["maxOutputTokens": request.maxTokens]
        // Минимальная задержка для подсказок (thinking_level «low» — самый быстрый для Gemini 3.x Flash).
        if !withThinking {
            // Модель не принимает thinkingConfig — умолчание модели.
        } else if request.purpose == .screenshot {
            generation["thinkingConfig"] = ["thinkingLevel": "medium"]
        } else if let level = hintThinkingLevel {
            generation["thinkingConfig"] = ["thinkingLevel": level]
        }
        if request.purpose == .hint { generation["temperature"] = 0.4 }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": request.system]]],
            "contents": contents,
            "generationConfig": generation,
        ]
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return r
    }

    public func stream(_ request: LLMRequest, model: String, key: String) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let events: AsyncThrowingStream<SSEEvent, Error>
                    do {
                        events = try await SSE.open(try makeRequest(request, model: model, key: key), transport: transport, key: key)
                    } catch LLMError.http(400, let message) where message.lowercased().contains("thinking") {
                        // Модель не знает этот thinking_level (у разных Flash набор уровней разный) — без него.
                        events = try await SSE.open(try makeRequest(request, model: model, key: key, withThinking: false),
                                                    transport: transport, key: key)
                    }
                    continuation.yield(.model(model))
                    var usage = TokenUsage()
                    var stop: String?
                    for try await e in events {
                        guard let json = SSE.json(e.data) else { continue }
                        if let error = json["error"] as? [String: Any] {
                            throw LLMError.http(status: error["code"] as? Int ?? 500, message: error["message"] as? String ?? "")
                        }
                        if let feedback = json["promptFeedback"] as? [String: Any], let reason = feedback["blockReason"] as? String {
                            throw LLMError.refusal(reason)
                        }
                        for cand in json["candidates"] as? [[String: Any]] ?? [] {
                            let parts = (cand["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
                            for p in parts where (p["thought"] as? Bool) != true {
                                if let t = p["text"] as? String, !t.isEmpty { continuation.yield(.text(t)) }
                            }
                            if let reason = cand["finishReason"] as? String {
                                stop = reason
                                if ["SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII", "RECITATION"].contains(reason) {
                                    throw LLMError.refusal(reason)
                                }
                            }
                        }
                        if let u = json["usageMetadata"] as? [String: Any] {
                            usage.input = u["promptTokenCount"] as? Int ?? usage.input
                            usage.output = (u["candidatesTokenCount"] as? Int ?? 0) + (u["thoughtsTokenCount"] as? Int ?? 0)
                            usage.cachedInput = u["cachedContentTokenCount"] as? Int ?? 0
                        }
                    }
                    continuation.yield(.usage(usage))
                    continuation.yield(.done(stopReason: stop))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// DeepSeek: OpenAI-совместимый `/chat/completions` (api-docs.deepseek.com/api/create-chat-completion).
public struct DeepSeekProvider: LLMProvider {
    public let id = ProviderID.deepseek
    let transport: StreamingTransport

    public init(transport: StreamingTransport = URLSessionStreamingTransport()) {
        self.transport = transport
    }

    public func makeRequest(_ request: LLMRequest, model: String, key: String) throws -> URLRequest {
        var r = URLRequest(url: ProviderEndpoints.deepseekBase.appendingPathComponent("chat/completions"))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        ProviderEndpoints.authorize(&r, provider: .deepseek, key: key)
        var messages: [[String: Any]] = [["role": "system", "content": request.system]]
        for m in request.messages {
            if m.images.isEmpty {
                messages.append(["role": m.role.rawValue, "content": m.text])
            } else {
                var parts: [[String: Any]] = m.images.map {
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\($0.base64EncodedString())"]]
                }
                parts.append(["type": "text", "text": m.text])
                messages.append(["role": m.role.rawValue, "content": parts])
            }
        }
        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": true,
            "stream_options": ["include_usage": true],
            "max_tokens": request.maxTokens,
            // Подсказки — без рассуждений (минимальная задержка); скриншот — с ними.
            "thinking": request.purpose == .screenshot ? ["type": "enabled", "reasoning_effort": "low"] : ["type": "disabled"],
        ]
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return r
    }

    public func stream(_ request: LLMRequest, model: String, key: String) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let events = try await SSE.open(try makeRequest(request, model: model, key: key), transport: transport, key: key)
                    var usage = TokenUsage()
                    var stop: String?
                    var announced = false
                    for try await e in events {
                        if e.data == "[DONE]" { break }
                        guard let json = SSE.json(e.data) else { continue }
                        if !announced { continuation.yield(.model(json["model"] as? String ?? model)); announced = true }
                        for choice in json["choices"] as? [[String: Any]] ?? [] {
                            if let t = (choice["delta"] as? [String: Any])?["content"] as? String, !t.isEmpty {
                                continuation.yield(.text(t))
                            }
                            if let reason = choice["finish_reason"] as? String {
                                stop = reason
                                if reason == "content_filter" { throw LLMError.refusal(reason) }
                                if reason == "insufficient_system_resource" { throw LLMError.http(status: 503, message: reason) }
                            }
                        }
                        if let u = json["usage"] as? [String: Any] {
                            usage.input = u["prompt_tokens"] as? Int ?? 0
                            usage.output = u["completion_tokens"] as? Int ?? 0
                            usage.cachedInput = u["prompt_cache_hit_tokens"] as? Int ?? 0
                        }
                    }
                    continuation.yield(.usage(usage))
                    continuation.yield(.done(stopReason: stop))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Anthropic Messages API, raw HTTP + SSE (skill `claude-api`: curl/examples.md, model-migration.md § Claude Sonnet 5.5).
/// - Подсказка и «сильная модель вручную» (R-13): `thinking: between_tools` (без расширенного рассуждения — минимальная
///   задержка; `disabled` у Sonnet 5.5 даёт 400) и `effort: low`.
/// - Скриншот (R-14): адаптивное рассуждение, `effort: medium`.
/// - Серверный fallback на отказ: `fallbacks: "default"` + `anthropic-beta: server-side-fallback-2026-07-01` (R-13).
/// - Системная часть помечена `cache_control` (R-11, кэш промпта).
public struct AnthropicProvider: LLMProvider {
    public let id = ProviderID.anthropic
    let transport: StreamingTransport
    public static let fallbackBeta = "server-side-fallback-2026-07-01"

    public init(transport: StreamingTransport = URLSessionStreamingTransport()) {
        self.transport = transport
    }

    public func makeRequest(_ request: LLMRequest, model: String, key: String) throws -> URLRequest {
        var r = URLRequest(url: ProviderEndpoints.anthropicBase.appendingPathComponent("messages"))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        ProviderEndpoints.authorize(&r, provider: .anthropic, key: key)
        let supportsFallback = model.hasPrefix("claude-sonnet-5-5") || model.hasPrefix("claude-opus-5") || model.hasPrefix("claude-fable-5-1")
        if supportsFallback { r.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta") }
        let messages: [[String: Any]] = request.messages.map { m in
            var content: [[String: Any]] = m.images.map {
                ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": $0.base64EncodedString()]]
            }
            content.append(["type": "text", "text": m.text])
            return ["role": m.role.rawValue, "content": content]
        }
        var body: [String: Any] = [
            "model": model,
            "max_tokens": request.maxTokens,
            "stream": true,
            "system": [["type": "text", "text": request.system, "cache_control": ["type": "ephemeral"]]],
            "messages": messages,
        ]
        let isSonnet55 = model.hasPrefix("claude-sonnet-5-5")
        switch request.purpose {
        case .hint, .strong:
            if isSonnet55 { body["thinking"] = ["type": "between_tools"] }
            if !model.hasPrefix("claude-haiku") { body["output_config"] = ["effort": "low"] }
        case .screenshot:
            if !model.hasPrefix("claude-haiku") {
                body["thinking"] = ["type": "adaptive"]
                body["output_config"] = ["effort": "medium"]
            }
        }
        if supportsFallback { body["fallbacks"] = "default" }
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return r
    }

    public func stream(_ request: LLMRequest, model: String, key: String) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let events = try await SSE.open(try makeRequest(request, model: model, key: key), transport: transport, key: key)
                    var usage = TokenUsage()
                    var stop: String?
                    var textBlocks = Set<Int>()
                    for try await e in events {
                        guard let json = SSE.json(e.data), let type = json["type"] as? String else { continue }
                        switch type {
                        case "message_start":
                            let message = json["message"] as? [String: Any] ?? [:]
                            continuation.yield(.model(message["model"] as? String ?? model))
                            if let u = message["usage"] as? [String: Any] {
                                usage.input = (u["input_tokens"] as? Int ?? 0) + (u["cache_creation_input_tokens"] as? Int ?? 0)
                                usage.cachedInput = u["cache_read_input_tokens"] as? Int ?? 0
                                usage.output = u["output_tokens"] as? Int ?? 0
                            }
                        case "content_block_start":
                            let block = json["content_block"] as? [String: Any] ?? [:]
                            // Читаем блоки по типу: thinking и служебный fallback пропускаем.
                            if block["type"] as? String == "text", let index = json["index"] as? Int { textBlocks.insert(index) }
                        case "content_block_delta":
                            let delta = json["delta"] as? [String: Any] ?? [:]
                            if delta["type"] as? String == "text_delta", let index = json["index"] as? Int, textBlocks.contains(index),
                               let t = delta["text"] as? String, !t.isEmpty {
                                continuation.yield(.text(t))
                            }
                        case "message_delta":
                            if let d = json["delta"] as? [String: Any], let reason = d["stop_reason"] as? String {
                                stop = reason
                                if reason == "refusal" {
                                    let category = (d["stop_details"] as? [String: Any])?["category"] as? String
                                    throw LLMError.refusal(category)
                                }
                            }
                            if let u = json["usage"] as? [String: Any], let out = u["output_tokens"] as? Int { usage.output = out }
                        case "error":
                            let err = json["error"] as? [String: Any] ?? [:]
                            let kind = err["type"] as? String ?? ""
                            let status = kind == "overloaded_error" ? 529 : (kind == "rate_limit_error" ? 429 : 500)
                            throw LLMError.http(status: status, message: err["message"] as? String ?? kind)
                        default:
                            break
                        }
                    }
                    continuation.yield(.usage(usage))
                    continuation.yield(.done(stopReason: stop))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Провайдер-заглушка для тестов и проверки цепочки без сети (AC-07).
public struct MockProvider: LLMProvider {
    public enum Behavior: Sendable {
        case reply([String], delay: Double = 0)
        case fail(LLMError)
        case failAfter([String], LLMError)
        case hang
    }

    public let id: ProviderID
    let behavior: Behavior

    public init(id: ProviderID, behavior: Behavior) {
        self.id = id
        self.behavior = behavior
    }

    public func stream(_ request: LLMRequest, model: String, key: String) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.model(model))
                switch behavior {
                case .reply(let chunks, let delay):
                    for c in chunks {
                        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                        if Task.isCancelled { continuation.finish(throwing: LLMError.cancelled); return }
                        continuation.yield(.text(c))
                    }
                    continuation.yield(.usage(TokenUsage(input: 100, output: chunks.count)))
                    continuation.yield(.done(stopReason: "end_turn"))
                    continuation.finish()
                case .fail(let error):
                    continuation.finish(throwing: error)
                case .failAfter(let chunks, let error):
                    for c in chunks { continuation.yield(.text(c)) }
                    continuation.finish(throwing: error)
                case .hang:
                    try? await Task.sleep(for: .seconds(60))
                    continuation.finish(throwing: LLMError.cancelled)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Groq и Cerebras — OpenAI-совместимый Chat Completions с SSE (COPILOT-03, R-36).
/// Источники (2026-10-23): console.groq.com/docs/openai, /docs/reasoning; inference-docs.cerebras.ai/resources/openai,
/// /api-reference/chat-completions.
/// - gpt-oss — рассуждающая модель: `reasoning_effort` low/medium/high (подсказки — low); рассуждение тратит токены
///   из `max_completion_tokens`, поэтому лимит увеличен. Groq: `include_reasoning: false` — текст рассуждения не приходит.
/// - Qwen: `reasoning_effort: none` — без рассуждения.
/// - `usage`: Cerebras — в последнем фрагменте; Groq — в `usage` или `x_groq.usage`. `stream_options` не отправляем.
/// - Изображений модели не принимают: запрос со скриншотом сразу уходит следующему провайдеру.
public struct OpenAICompatibleProvider: LLMProvider {
    public let id: ProviderID
    let transport: StreamingTransport

    public init(_ id: ProviderID, transport: StreamingTransport = URLSessionStreamingTransport()) {
        self.id = id
        self.transport = transport
    }

    static func isReasoning(_ model: String) -> Bool { model.contains("gpt-oss") }

    public func makeRequest(_ request: LLMRequest, model: String, key: String) throws -> URLRequest {
        guard request.messages.allSatisfy({ $0.images.isEmpty }) else {
            throw LLMError.badResponse("\(id.displayName) не принимает изображения")
        }
        var r = URLRequest(url: ProviderEndpoints.openAIBase(id).appendingPathComponent("chat/completions"))
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        ProviderEndpoints.authorize(&r, provider: id, key: key)
        var messages: [[String: Any]] = [["role": "system", "content": request.system]]
        for m in request.messages { messages.append(["role": m.role.rawValue, "content": m.text]) }
        var body: [String: Any] = ["model": model, "messages": messages, "stream": true]
        if Self.isReasoning(model) {
            body["reasoning_effort"] = request.purpose == .screenshot ? "medium" : "low"
            body["max_completion_tokens"] = request.maxTokens + 1024
            if id == .groq { body["include_reasoning"] = false }
        } else {
            if model.lowercased().contains("qwen") { body["reasoning_effort"] = "none" }
            body["max_completion_tokens"] = request.maxTokens
        }
        if request.purpose == .hint { body["temperature"] = 0.4 }
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return r
    }

    public func stream(_ request: LLMRequest, model: String, key: String) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let events = try await SSE.open(try makeRequest(request, model: model, key: key), transport: transport, key: key)
                    var usage = TokenUsage()
                    var stop: String?
                    var announced = false
                    for try await e in events {
                        if e.data == "[DONE]" { break }
                        guard let json = SSE.json(e.data) else { continue }
                        if let error = json["error"] as? [String: Any] {
                            throw LLMError.http(status: 503, message: error["message"] as? String ?? "stream error")
                        }
                        if !announced { continuation.yield(.model(json["model"] as? String ?? model)); announced = true }
                        for choice in json["choices"] as? [[String: Any]] ?? [] {
                            if let t = (choice["delta"] as? [String: Any])?["content"] as? String, !t.isEmpty {
                                continuation.yield(.text(t))
                            }
                            if let reason = choice["finish_reason"] as? String {
                                stop = reason
                                if reason == "content_filter" { throw LLMError.refusal(reason) }
                            }
                        }
                        let u = json["usage"] as? [String: Any] ?? (json["x_groq"] as? [String: Any])?["usage"] as? [String: Any]
                        if let u {
                            usage.input = u["prompt_tokens"] as? Int ?? usage.input
                            usage.output = u["completion_tokens"] as? Int ?? usage.output
                        }
                    }
                    continuation.yield(.usage(usage))
                    continuation.yield(.done(stopReason: stop))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
