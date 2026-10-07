import Foundation

/// События цепочки для UI и учёта (R-09, R-10, R-20).
public enum ChainEvent: Sendable, Equatable {
    /// Начата попытка у провайдера.
    case attempt(ProviderID, model: String)
    /// Фактическая модель ответа (метка «Gemini · generated», S-03/S-04).
    case model(ProviderID, String)
    /// Первый токен; `afterMs` — от начала запроса цепочки (метрика AC-03 считается от конца хода снаружи).
    case firstToken(ProviderID, afterMs: Double)
    case text(String)
    /// Предыдущий частичный текст отброшен: ответ начинается заново у другого провайдера.
    case restart(ProviderID)
    /// Провайдер не ответил; `invalidKey` — показать «ключ недействителен» в настройках (R-09).
    case providerFailed(ProviderID, LLMError)
    case usage(ProviderID, model: String, TokenUsage)
    case finished(ProviderID, model: String)
    /// Ни один провайдер не ответил (S-04: «Модели недоступны: <причина>»).
    case exhausted(reason: String)
}

/// Память о недавно отказавших моделях: модель, не ответившая вовремя или вернувшая 429/5xx, пропускается
/// несколько минут, чтобы каждый ход не терял 4 с на её таймауте (живой созвон H-4: gemini-3.8-flash раз за разом
/// не отвечала за 4 с, первые слова приходили через 4,8 с вместо ≤ 2,5 с).
public final class ProviderHealth: @unchecked Sendable {
    public static let shared = ProviderHealth()
    private let lock = NSLock()
    private var until: [String: Date] = [:]
    public var cooldown: TimeInterval = 300

    public init() {}

    static func key(_ p: ProviderID, _ model: String) -> String { "\(p.rawValue)/\(model)" }

    public func isCoolingDown(_ p: ProviderID, _ model: String, now: Date = Date()) -> Bool {
        lock.withLock { (until[Self.key(p, model)] ?? .distantPast) > now }
    }

    public func reportFailure(_ p: ProviderID, _ model: String, _ error: LLMError, now: Date = Date()) {
        switch error {
        case .firstTokenTimeout, .http(429, _), .network: break
        case .http(let s, _) where s >= 500: break
        default: return
        }
        lock.withLock { until[Self.key(p, model)] = now.addingTimeInterval(cooldown) }
    }

    public func reportSuccess(_ p: ProviderID, _ model: String) {
        lock.withLock { until[Self.key(p, model)] = nil }
    }

    public func reset() { lock.withLock { until.removeAll() } }
}

/// Цепочка провайдеров с автопереходом — R-09.
/// Порядок из настроек, провайдеры без ключа пропускаются; переход при 429/5xx, сетевой ошибке, отказе модели,
/// неверном ключе (400/401/403 — без повтора у того же провайдера) и если первый токен не пришёл за `firstTokenTimeout`.
public struct ProviderChain: Sendable {
    public struct Step: Sendable {
        public var provider: LLMProvider
        public var model: String
        public var key: String?

        public init(provider: LLMProvider, model: String, key: String?) {
            self.provider = provider
            self.model = model
            self.key = key
        }
    }

    public var steps: [Step]
    public var firstTokenTimeout: Double
    public var health: ProviderHealth?

    public init(steps: [Step], firstTokenTimeout: Double = 4, health: ProviderHealth? = nil) {
        self.steps = steps
        self.firstTokenTimeout = firstTokenTimeout
        self.health = health
    }

    /// Запуск. Отмена задачи-потребителя (новый ход, R-10) прерывает текущий запрос.
    public func run(_ request: LLMRequest) -> AsyncStream<ChainEvent> {
        AsyncStream { continuation in
            let task = Task {
                let start = DispatchTime.now().uptimeNanoseconds
                var reasons: [String] = []
                var usable = steps.filter { $0.key?.isEmpty == false }
                // Недавно отказавшие модели — в конец очереди (не выкидываем: вдруг все остальные тоже не отвечают).
                if let health {
                    let fresh = usable.filter { !health.isCoolingDown($0.provider.id, $0.model) }
                    let cooling = usable.filter { health.isCoolingDown($0.provider.id, $0.model) }
                    usable = fresh + cooling
                }
                if usable.isEmpty {
                    continuation.yield(.exhausted(reason: "нет ключей"))
                    continuation.finish()
                    return
                }
                var attemptIndex = 0
                var invalidKey = Set<ProviderID>()
                for step in usable {
                    if Task.isCancelled { break }
                    let pid = step.provider.id
                    // 400/401/403 — у этого провайдера больше не пробуем, в том числе запасную модель (R-09).
                    if invalidKey.contains(pid) { continue }
                    continuation.yield(.attempt(pid, model: step.model))
                    if attemptIndex > 0 { continuation.yield(.restart(pid)) }
                    attemptIndex += 1
                    do {
                        try await Self.runStep(step, request: request, timeout: firstTokenTimeout, start: start, continuation: continuation)
                        health?.reportSuccess(pid, step.model)
                        continuation.finish()
                        return
                    } catch let error as LLMError {
                        if error == .cancelled || Task.isCancelled { break }
                        var detail = ""
                        if case .http(_, let m) = error { detail = m }
                        Log.llm.error("provider \(pid.rawValue, privacy: .public) model=\(step.model, privacy: .public) failed: \(error.description, privacy: .public) \(String(detail.prefix(200)), privacy: .public)")
                        continuation.yield(.providerFailed(pid, error))
                        health?.reportFailure(pid, step.model, error)
                        reasons.append("\(pid.displayName) \(step.model): \(error.description)")
                        if error.isInvalidKey { invalidKey.insert(pid) }
                        guard error.triggersFallback else { break }
                    } catch {
                        if Task.isCancelled { break }
                        let e = LLMError.network(error.localizedDescription)
                        continuation.yield(.providerFailed(pid, e))
                        reasons.append("\(pid.displayName) \(step.model): \(e.description)")
                    }
                }
                if !Task.isCancelled {
                    continuation.yield(.exhausted(reason: reasons.joined(separator: "; ")))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Один провайдер; бросает ошибку, если нужен переход. Таймаут первого токена — гонка с часами.
    static func runStep(_ step: Step, request: LLMRequest, timeout: Double, start: UInt64,
                        continuation: AsyncStream<ChainEvent>.Continuation) async throws {
        let pid = step.provider.id
        let stream = step.provider.stream(request, model: step.model, key: step.key ?? "")
        let gotFirst = FirstTokenFlag()
        let stepStart = DispatchTime.now().uptimeNanoseconds

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                var model = step.model
                var usage: TokenUsage?
                for try await event in stream {
                    switch event {
                    case .model(let m):
                        model = m
                        continuation.yield(.model(pid, m))
                    case .text(let t):
                        if gotFirst.set() {
                            let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
                            continuation.yield(.firstToken(pid, afterMs: ms))
                        }
                        continuation.yield(.text(t))
                    case .usage(let u):
                        usage = u
                    case .done:
                        break
                    }
                }
                if let usage { continuation.yield(.usage(pid, model: model, usage)) }
                if !gotFirst.isSet { throw LLMError.badResponse("пустой ответ") }
                continuation.yield(.finished(pid, model: model))
            }
            group.addTask {
                // Сторож первого токена (R-09: 4 с).
                while true {
                    try await Task.sleep(for: .milliseconds(50))
                    if gotFirst.isSet { return }
                    if Double(DispatchTime.now().uptimeNanoseconds - stepStart) / 1e9 >= timeout {
                        throw LLMError.firstTokenTimeout
                    }
                }
            }
            do {
                // Ждём завершения потока; сторож завершится сам после первого токена.
                for try await _ in group {}
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }
}

final class FirstTokenFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    /// true, если флаг установлен этим вызовом.
    func set() -> Bool {
        lock.withLock {
            if value { return false }
            value = true
            return true
        }
    }
}

/// Сборка цепочки из настроек: порядок, ID моделей, ключи; при достигнутом бюджете платные провайдеры
/// выключены (R-18 Budget), Gemini Free продолжает работать.
public enum ChainFactory {
    public static func providers(transport: StreamingTransport = URLSessionStreamingTransport()) -> [ProviderID: LLMProvider] {
        [.gemini: GeminiProvider(transport: transport), .deepseek: DeepSeekProvider(transport: transport),
         .anthropic: AnthropicProvider(transport: transport)]
    }

    public static func isPaid(_ p: ProviderID, settings: AppSettings) -> Bool {
        p != .gemini || !settings.geminiFreeTier
    }

    public static func chain(settings: AppSettings, secrets: SecretStore,
                             providers: [ProviderID: LLMProvider]) -> ProviderChain {
        var steps: [ProviderChain.Step] = []
        for p in settings.chain {
            guard let provider = providers[p] else { continue }
            if settings.paidProvidersSuspended && isPaid(p, settings: settings) { continue }
            let key = try? secrets.get(p)
            steps.append(ProviderChain.Step(provider: provider, model: settings.modelIDs.effective(p), key: key))
            // Запасная модель Gemini сразу после основной: при перегрузке основной ответ всё равно бесплатный.
            let backup = settings.modelIDs.geminiBackup.trimmingCharacters(in: .whitespaces)
            if p == .gemini, !backup.isEmpty, backup != settings.modelIDs.effective(.gemini) {
                steps.append(ProviderChain.Step(provider: provider, model: backup, key: key))
            }
        }
        return ProviderChain(steps: steps, firstTokenTimeout: settings.firstTokenTimeout, health: .shared)
    }

    /// Сильная модель (S-05, S-06): только она, без цепочки. Без ключа — nil (кнопка неактивна).
    public static func strong(settings: AppSettings, secrets: SecretStore, providers: [ProviderID: LLMProvider],
                              fallbackToGemini: Bool) -> ProviderChain? {
        var order = [settings.strongProvider]
        if fallbackToGemini && settings.strongProvider != .gemini { order.append(.gemini) }
        var steps: [ProviderChain.Step] = []
        for p in order {
            guard let provider = providers[p], let key = try? secrets.get(p), !key.isEmpty else { continue }
            if settings.paidProvidersSuspended && isPaid(p, settings: settings) { continue }
            steps.append(ProviderChain.Step(provider: provider, model: settings.modelIDs.effective(p), key: key))
            let backup = settings.modelIDs.geminiBackup.trimmingCharacters(in: .whitespaces)
            if p == .gemini, fallbackToGemini, !backup.isEmpty, backup != settings.modelIDs.effective(.gemini) {
                steps.append(ProviderChain.Step(provider: provider, model: backup, key: key))
            }
        }
        guard let first = steps.first else { return nil }
        // Скриншот без ключа Anthropic уходит в Gemini (S-06); ручной вызов — только сильная модель (S-05).
        return ProviderChain(steps: fallbackToGemini ? steps : [first], firstTokenTimeout: max(settings.firstTokenTimeout, 8))
    }
}
