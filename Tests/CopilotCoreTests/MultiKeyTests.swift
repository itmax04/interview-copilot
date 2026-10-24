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
        for slot in 2...KeySlots.max { try store.set("x\(slot)", for: .cerebras, slot: slot) }
        #expect(store.freeExtraSlot(.cerebras) == nil)
        #expect(!store.contains(.gemini) && store.accounts().contains("groq#3"))
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
