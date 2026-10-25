import Foundation
import Testing
@testable import CopilotCore

/// Провайдер с поведением по номеру вызова и счётчиком: показывает, сколько запросов ушло и кому.
final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.withLock { count } }
    func hit() -> Int { lock.withLock { count += 1; return count } }
}

struct ScriptedProvider: LLMProvider {
    let id: ProviderID
    let log = CallLog()
    var acceptsImages = true
    let script: @Sendable (Int) -> MockProvider.Behavior

    func stream(_ request: LLMRequest, model: String, key: String) -> AsyncThrowingStream<LLMEvent, Error> {
        MockProvider(id: id, behavior: script(log.hit())).stream(request, model: model, key: key)
    }
}

@Suite("Цепочка не сдается: последний шанс, параллельный запрос, снимки — COPILOT-11")
struct ChainResilienceTests {
    private let request = LLMRequest(system: "s", messages: [LLMMessage(role: .user, text: "q")], maxTokens: 400, purpose: .hint)
    /// Лимит токенов в минуту у Groq: ключ освободится через 3 с (минимум, который запоминает ProviderHealth).
    private let minuteLimit = LLMError.http(status: 429, message: RetryHint.tag(3) + "Rate limit reached on tokens per minute")

    private func step(_ p: ScriptedProvider, slot: Int = 1, model: String? = nil) -> ProviderChain.Step {
        ProviderChain.Step(provider: p, model: model ?? "\(p.id.rawValue)-model", key: "key-\(slot)", keySlot: slot)
    }

    private func run(_ chain: ProviderChain, _ request: LLMRequest? = nil) async -> [ChainEvent] {
        var out: [ChainEvent] = []
        for await e in chain.run(request ?? self.request) { out.append(e) }
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

    private func exhausted(_ events: [ChainEvent]) -> Bool {
        events.contains { if case .exhausted = $0 { true } else { false } }
    }

    @Test(arguments: [nil, 0.3] as [Double?])
    func allKeysLimitedThenAnswerAfterReset(hedgeAfter: Double?) async {
        // Все три ключа получили 429 на минутный лимит. Раньше — «Модели недоступны», теперь — ждем сброс и отвечаем.
        let providers = (1...3).map { _ in ScriptedProvider(id: .groq) { n in n == 1 ? .fail(minuteLimit) : .reply(["ответ"]) } }
        let steps = providers.enumerated().map { step($1, slot: $0 + 1) }
        let started = Date()
        let events = await run(ProviderChain(steps: steps, firstTokenTimeout: 1, health: ProviderHealth(), hedgeAfter: hedgeAfter))
        #expect(text(events) == "ответ" && !exhausted(events))
        #expect(providers.map(\.log.calls).reduce(0, +) == 4)   // три отказа и один повтор после сброса лимита
        #expect(Date().timeIntervalSince(started) < 8)
    }

    @Test func dailyLimitIsNotWaitedFor() async {
        // Дневной лимит — часы: ждать нечего, ошибка сразу, без второго круга.
        let day = LLMError.http(status: 429, message: "on requests per day (RPD). Please try again in 2h3m1s.")
        let groq = ScriptedProvider(id: .groq) { _ in .fail(day) }
        let started = Date()
        let events = await run(ProviderChain(steps: [step(groq)], health: ProviderHealth()))
        #expect(exhausted(events) && groq.log.calls == 1)
        #expect(Date().timeIntervalSince(started) < 2)
    }

    @Test(arguments: [nil, 0.1] as [Double?])
    func slowModelIsGivenTimeWhenNothingElseIsLeft(hedgeAfter: Double?) async {
        // Gemini отвечает за 0,5 с при таймауте 0,2 с: в первом круге «таймаут», в последнем шансе — ответ.
        let gemini = ScriptedProvider(id: .gemini) { _ in .reply(["медленный ответ"], delay: 0.5) }
        let events = await run(ProviderChain(steps: [step(gemini)], firstTokenTimeout: 0.2, health: ProviderHealth(), hedgeAfter: hedgeAfter))
        #expect(text(events) == "медленный ответ" && !exhausted(events))
        #expect(gemini.log.calls == 2)
    }

    @Test func withoutHealthTheChainStillGivesUpAtOnce() async {
        // Без `health` (сильная модель, проверки) поведение прежнее: один круг и «Модели недоступны».
        let groq = ScriptedProvider(id: .groq) { _ in .fail(minuteLimit) }
        let events = await run(ProviderChain(steps: [step(groq)]))
        #expect(exhausted(events) && groq.log.calls == 1)
    }

    @Test func parallelRequestGoesToAnotherProviderNotToTheNextKey() async {
        // Groq молчит дольше hedgeAfter. Параллельный запрос — к Cerebras, а не ко второму ключу Groq: второй ключ
        // не быстрее первого и тратит свой минутный лимит токенов.
        let groq1 = ScriptedProvider(id: .groq) { _ in .reply(["медленно"], delay: 1.0) }
        let groq2 = ScriptedProvider(id: .groq) { _ in .reply(["второй ключ"]) }
        let cerebras = ScriptedProvider(id: .cerebras) { _ in .reply(["быстро"]) }
        let events = await run(ProviderChain(steps: [step(groq1), step(groq2, slot: 2), step(cerebras)],
                                             firstTokenTimeout: 4, health: ProviderHealth(), hedgeAfter: 0.2))
        #expect(text(events) == "быстро")
        #expect(groq2.log.calls == 0 && cerebras.log.calls == 1)
    }

    @Test func screenshotSkipsProvidersWithoutImages() async {
        let groq = ScriptedProvider(id: .groq, acceptsImages: false) { _ in .reply(["текст"]) }
        let gemini = ScriptedProvider(id: .gemini) { _ in .reply(["по снимку"]) }
        let shot = LLMRequest(system: "s", messages: [LLMMessage(role: .user, text: "q", images: [Data([1, 2, 3])])],
                              maxTokens: 400, purpose: .screenshot)
        let withImage = await run(ProviderChain(steps: [step(groq), step(gemini)]), shot)
        #expect(text(withImage) == "по снимку" && groq.log.calls == 0)
        // Обычный вопрос — Groq первым, как и было.
        let plain = await run(ProviderChain(steps: [step(groq), step(gemini)]))
        #expect(text(plain) == "текст" && groq.log.calls == 1)
        // Нет ни одного провайдера со снимками — запрос уходит как есть (ошибка понятная), а не «нет ключей».
        let onlyText = await run(ProviderChain(steps: [step(groq)]), shot)
        #expect(text(onlyText) == "текст" && groq.log.calls == 2)
    }

    @Test func stepFloorKeepsAMarginallySlowModelInTheFirstPass() async {
        // Первый токен за 0,5 с при общем таймауте 0,2 с: у шага своя нижняя граница 1 с — ответ в первом круге, без «остывания».
        let gemini = ScriptedProvider(id: .gemini) { _ in .reply(["успела"], delay: 0.5) }
        var geminiStep = step(gemini)
        geminiStep.minFirstTokenTimeout = 1
        let health = ProviderHealth()
        let events = await run(ProviderChain(steps: [geminiStep], firstTokenTimeout: 0.2, health: health))
        #expect(text(events) == "успела" && gemini.log.calls == 1)
        #expect(!health.isCoolingDown(.gemini, "gemini-model"))
    }

    @Test func factoryGivesGeminiAPatientFirstTokenFloor() {
        let chain = ChainFactory.chain(settings: AppSettings(), secrets: InMemorySecretStore([.groq: "g", .gemini: "m"]),
                                       providers: ChainFactory.providers())
        let gemini = chain.steps.filter { $0.provider.id == .gemini }
        #expect(gemini.count == 2 && gemini.allSatisfy { $0.minFirstTokenTimeout == 7 })
        #expect(chain.steps.filter { $0.provider.id == .groq }.allSatisfy { $0.minFirstTokenTimeout == 0 })
    }

    @Test func keyReadyInReportsOnlyKeyLimits() {
        let health = ProviderHealth()
        let now = Date(timeIntervalSince1970: 1_792_500_000)
        health.reportFailure(.groq, "m", slot: 1, .http(status: 429, message: RetryHint.tag(12) + "x"), now: now)
        health.reportFailure(.gemini, "g", slot: 1, .firstTokenTimeout, now: now)
        #expect(Int(health.keyReadyIn(.groq, "m", slot: 1, now: now)) == 12)
        #expect(health.keyReadyIn(.groq, "m", slot: 2, now: now) == 0)
        // Медленную модель ждать нечем — только пробовать терпеливее.
        #expect(health.keyReadyIn(.gemini, "g", slot: 1, now: now) == 0)
        #expect(health.keyReadyIn(.groq, "m", slot: 1, now: now.addingTimeInterval(13)) == 0)
    }
}
