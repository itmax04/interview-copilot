import Foundation
import Testing
@testable import CopilotCore

@Suite("Несколько ключей одного провайдера — COPILOT-09")
struct MultiKeyTests {
    private let request = LLMRequest(system: "s", messages: [LLMMessage(role: .user, text: "q")], maxTokens: 400, purpose: .hint)
    private let limit = LLMError.http(status: 429, message: "rate limit")

    private func step(_ id: ProviderID, slot: Int, _ b: MockProvider.Behavior) -> ProviderChain.Step {
        ProviderChain.Step(provider: MockProvider(id: id, behavior: b), model: "\(id.rawValue)-model", key: "key-\(slot)", keySlot: slot)
    }

    private func run(_ chain: ProviderChain) async -> [ChainEvent] {
        var out: [ChainEvent] = []
        for await e in chain.run(request) { out.append(e) }
        return out
    }

    private func text(_ events: [ChainEvent]) -> String {
        var s = ""
        for e in events {
            if case .text(let t) = e { s += t }
            if case .restart = e { s = "" }
        }
        return s
    }

    @Test func storeKeepsSlotsAndOldPrimaryName() throws {
        let store = InMemorySecretStore([.groq: "g1"])
        #expect(KeySlots.account(.groq, 1) == "groq" && KeySlots.account(.groq, 3) == "groq#3")
        #expect(store.freeExtraSlot(.groq) == 2)
        try store.set("g2", for: .groq, slot: 2)
        try store.set("g3", for: .groq, slot: 3)
        #expect(store.slots(.groq) == [1, 2, 3])
        #expect(store.keys(.groq).map(\.key) == ["g1", "g2", "g3"])
        #expect(try store.get(.groq) == "g1")           // прежний вызов — основной ключ
        #expect(store.freeExtraSlot(.groq) == 4)
        // Без основного ключа провайдер остается с ключами — дополнительные работают.
        try store.delete(.groq)
        #expect(store.contains(.groq) && store.slots(.groq) == [2, 3])
        try store.delete(.groq, slot: 2)
        #expect(store.freeExtraSlot(.groq) == 2)
        // Ограничения нет: 12 ключей одного провайдера.
        for slot in 2...12 { try store.set("x\(slot)", for: .cerebras, slot: slot) }
        #expect(store.slots(.cerebras) == Array(2...12) && store.freeExtraSlot(.cerebras) == 13)
        #expect(!store.contains(.gemini) && store.accounts().contains("groq#3"))
        #expect(KeySlots.slot(of: "groq#12", provider: .groq) == 12 && KeySlots.slot(of: "groq", provider: .groq) == 1)
        #expect(KeySlots.slot(of: "groq#x", provider: .groq) == nil && KeySlots.slot(of: "cerebras#2", provider: .groq) == nil)
    }

    @Test func deletingAKeyRenumbersTheRestWithoutGaps() throws {
        let store = InMemorySecretStore([.groq: "g1"])
        for (slot, v) in [(2, "g2"), (3, "g3"), (4, "g4")] { try store.set(v, for: .groq, slot: slot) }
        try store.delete(.groq, slot: 2)
        try store.compactSlots(.groq)
        #expect(store.keys(.groq).map(\.slot) == [1, 2, 3])
        #expect(store.keys(.groq).map(\.key) == ["g1", "g3", "g4"])
        // Удален основной — его место занимает следующий.
        try store.delete(.groq, slot: 1)
        try store.compactSlots(.groq)
        #expect(store.keys(.groq).map(\.key) == ["g3", "g4"] && store.slots(.groq) == [1, 2])
    }

    @Test func manyKeysAreAllTriedBeforeTheNextProvider() async {
        let health = ProviderHealth()
        var steps = (1...7).map { step(.groq, slot: $0, .fail(limit)) }
        steps.append(step(.groq, slot: 8, .reply(["восьмой ключ"])))
        steps.append(step(.cerebras, slot: 1, .reply(["другой провайдер"])))
        let events = await run(ProviderChain(steps: steps, health: health))
        #expect(text(events) == "восьмой ключ")
        #expect(!events.contains(.attempt(.cerebras, model: "cerebras-model")))
        // Все ключи с лимитом — тогда следующий провайдер.
        let exhausted = (1...3).map { step(.groq, slot: $0, .fail(limit)) } + [step(.cerebras, slot: 1, .reply(["cerebras"]))]
        #expect(text(await run(ProviderChain(steps: exhausted, health: ProviderHealth()))) == "cerebras")
    }

    @Test func rateLimitCooldownFollowsTheProviderHint() {
        let health = ProviderHealth()
        let now = Date(timeIntervalSince1970: 1_792_400_000)
        health.reportFailure(.groq, "m", slot: 1, .http(status: 429, message: RetryHint.tag(6.2) + "Rate limit reached"), now: now)
        #expect(health.isCoolingDown(.groq, "m", slot: 1, now: now.addingTimeInterval(5)))
        #expect(!health.isCoolingDown(.groq, "m", slot: 1, now: now.addingTimeInterval(7)))
        // Дневной лимит — часы; без подсказки — минута.
        health.reportFailure(.groq, "m", slot: 2, .http(status: 429, message: "on requests per day (RPD). Please try again in 1h2m3s."), now: now)
        #expect(health.isCoolingDown(.groq, "m", slot: 2, now: now.addingTimeInterval(3700)))
        #expect(!health.isCoolingDown(.groq, "m", slot: 2, now: now.addingTimeInterval(3730)))
        health.reportFailure(.groq, "m", slot: 3, .http(status: 429, message: "rate limit"), now: now)
        #expect(health.isCoolingDown(.groq, "m", slot: 3, now: now.addingTimeInterval(59)))
        #expect(!health.isCoolingDown(.groq, "m", slot: 3, now: now.addingTimeInterval(61)))
    }

    @Test(arguments: [
        ("Rate limit reached for model `m` on tokens per minute (TPM): Limit 8000. Please try again in 6.18s. Need more tokens?", 6.18),
        ("Please try again in 1m30.5s.", 90.5),
        ("please try again in 2h", 7200.0),
        ("please try again in 750ms", 0.75),
        (#"{"error":{"details":[{"retryDelay": "34s"}]}}"#, 34.0),
        ("[retry-after 12.00s] Rate limit", 12.0),
    ])
    func retryHintIsReadFromProviderTexts(text: String, seconds: Double) {
        #expect(abs((RetryHint.seconds(inText: text) ?? -1) - seconds) < 0.001)
    }

    /// Ответ 429 Groq с заголовком и длинным текстом: подсказка не теряется при обрезке текста до 200 символов.
    struct RateLimitedTransport: StreamingTransport {
        let header: String?
        func lines(for request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<String, Error>) {
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: "HTTP/1.1",
                                           headerFields: header.map { ["retry-after": $0] } ?? [:])!
            let body = #"{"error":{"message":"Rate limit reached for model `openai/gpt-oss-120b` in organization `org_synthetic` "#
                + #"service tier `on_demand` on tokens per minute (TPM): Limit 8000, Used 7863, Requested 924. Please try again in "#
                + #"5.84s. Need more tokens? Upgrade to Dev Tier today at https://console.groq.com/settings/billing","type":"tokens"}}"#
            return (response, AsyncThrowingStream { c in c.yield(body); c.finish() })
        }
    }

    @Test(arguments: [("9", 9.0), (nil, 5.84)] as [(String?, Double)])
    func rateLimitResponseCarriesTheWaitTime(header: String?, seconds: Double) async {
        let provider = OpenAICompatibleProvider(.groq, transport: RateLimitedTransport(header: header))
        var caught: LLMError?
        do {
            for try await _ in provider.stream(request, model: "openai/gpt-oss-120b", key: "synthetic-test-value") {}
        } catch let e as LLMError { caught = e } catch {}
        guard case .http(429, let message)? = caught else { Issue.record("нет 429: \(String(describing: caught))"); return }
        #expect(abs((RetryHint.seconds(inText: message) ?? -1) - seconds) < 0.01)
        #expect(message.count <= 200 + RetryHint.tag(seconds).count)
    }

    @Test func retryHeaderWinsAndMissingHintIsNil() {
        #expect(RetryHint.seconds(header: "7", body: "Please try again in 60s") == 7)
        #expect(RetryHint.seconds(header: nil, body: "Please try again in 60s") == 60)
        #expect(RetryHint.seconds(header: nil, body: "rate limit") == nil)
        #expect(RetryHint.seconds(inText: "try again in a moment") == nil)
    }

    @Test func factoryPutsAllKeysOfAProviderBeforeTheNextProvider() throws {
        let store = InMemorySecretStore([.groq: "g1", .gemini: "m1"])
        try store.set("g2", for: .groq, slot: 2)
        try store.set("m2", for: .gemini, slot: 2)
        var settings = AppSettings()
        settings.chain = [.groq, .gemini]
        let steps = ChainFactory.chain(settings: settings, secrets: store, providers: ChainFactory.providers()).steps
        #expect(steps.map { "\($0.provider.id.rawValue)#\($0.keySlot)" } == ["groq#1", "groq#2", "gemini#1", "gemini#2", "gemini#1", "gemini#2"])
        #expect(steps.map(\.key) == ["g1", "g2", "m1", "m2", "m1", "m2"])
        // Основная модель Gemini — с обоими ключами, затем запасная.
        #expect(steps[2].model == settings.modelIDs.effective(.gemini) && steps[4].model == settings.modelIDs.geminiBackup)
    }

    @Test(arguments: [false, true])
    func rateLimitedKeyHandsOverToTheNextKeyOfTheSameProvider(hedged: Bool) async {
        let health = ProviderHealth()
        let chain = ProviderChain(steps: [step(.groq, slot: 1, .fail(limit)), step(.groq, slot: 2, .reply(["ответ"])),
                                          step(.cerebras, slot: 1, .reply(["другой провайдер"]))],
                                  health: health, hedgeAfter: hedged ? 5 : nil)
        let events = await run(chain)
        #expect(text(events) == "ответ")
        #expect(events.contains(.keyFailed(.groq, slot: 1, limit)))
        #expect(events.contains(.finished(.groq, model: "groq-model")))
        #expect(!events.contains(.attempt(.cerebras, model: "cerebras-model")))
        // Лимит — у ключа 1, а не у модели: следующий запрос начнется с ключа 2.
        #expect(health.isCoolingDown(.groq, "groq-model", slot: 1))
        #expect(!health.isCoolingDown(.groq, "groq-model", slot: 2))
        #expect(chain.orderedUsableSteps().map(\.keySlot) == [2, 1, 1])
        #expect(chain.orderedUsableSteps().map(\.provider.id) == [.groq, .cerebras, .groq])
    }

    @Test func invalidKeySkipsOnlyThatKey() async {
        let invalid = LLMError.http(status: 401, message: "bad key")
        let chain = ProviderChain(steps: [step(.groq, slot: 1, .fail(invalid)), step(.groq, slot: 2, .reply(["ok"]))])
        let events = await run(chain)
        #expect(text(events) == "ok")
        #expect(events.contains(.keyFailed(.groq, slot: 1, invalid)))
        #expect(events.contains(.attempt(.groq, model: "groq-model")))
    }

    @Test func slowModelCoolsDownForEveryKey() {
        let health = ProviderHealth()
        health.reportFailure(.gemini, "m", slot: 1, .firstTokenTimeout)
        #expect(health.isCoolingDown(.gemini, "m", slot: 1) && health.isCoolingDown(.gemini, "m", slot: 2))
        health.reset()
        health.reportFailure(.groq, "g", slot: 2, .http(status: 429, message: ""))
        #expect(health.isCoolingDown(.groq, "g", slot: 2) && !health.isCoolingDown(.groq, "g", slot: 1))
        health.reportSuccess(.groq, "g", slot: 2)
        #expect(!health.isCoolingDown(.groq, "g", slot: 2))
    }

    @Test func allKeysExhaustedNamesEachKeyInTheReason() async {
        let chain = ProviderChain(steps: [step(.groq, slot: 1, .fail(limit)), step(.groq, slot: 2, .fail(limit))])
        let events = await run(chain)
        let reason = events.compactMap { if case .exhausted(let r) = $0 { r } else { nil } }.first ?? ""
        #expect(reason.contains("Groq groq-model") && reason.contains("Groq (ключ 2) groq-model"))
        #expect(!reason.contains("key-"))   // значения ключей в причину не попадают
    }
}
