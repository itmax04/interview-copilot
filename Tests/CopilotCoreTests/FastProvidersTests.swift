import Foundation
import Testing
@testable import CopilotCore

@Suite("Groq, Cerebras и параллельный запуск — R-36")
struct FastProvidersTests {
    private let request = LLMRequest(system: "s", messages: [LLMMessage(role: .user, text: "q")], maxTokens: 400, purpose: .hint)

    private func step(_ id: ProviderID, _ b: MockProvider.Behavior) -> ProviderChain.Step {
        ProviderChain.Step(provider: MockProvider(id: id, behavior: b), model: "\(id.rawValue)-model", key: "key")
    }

    private func run(_ chain: ProviderChain) async -> (events: [ChainEvent], seconds: Double) {
        let started = Date()
        var out: [ChainEvent] = []
        for await e in chain.run(request) { out.append(e) }
        return (out, Date().timeIntervalSince(started))
    }

    private func text(_ events: [ChainEvent]) -> String {
        var s = ""
        for e in events {
            if case .text(let t) = e { s += t }
            if case .restart = e { s = "" }
        }
        return s
    }

    @Test func silentModelIsOvertakenWithoutWaitingForTimeout() async {
        let chain = ProviderChain(steps: [step(.gemini, .hang), step(.groq, .reply(["При", "вет"]))],
                                  firstTokenTimeout: 4, hedgeAfter: 0.2)
        let (events, seconds) = await run(chain)
        #expect(text(events) == "Привет")
        #expect(events.contains(.attempt(.groq, model: "groq-model")))
        #expect(events.contains(.finished(.groq, model: "groq-model")))
        #expect(!events.contains { if case .exhausted = $0 { true } else { false } })
        #expect(seconds < 2) // не ждём 4 с таймаута Gemini
    }

    @Test func fastFirstModelAnswersAlone() async {
        let chain = ProviderChain(steps: [step(.groq, .reply(["ok"])), step(.gemini, .reply(["другой"]))], hedgeAfter: 1)
        let (events, _) = await run(chain)
        #expect(text(events) == "ok")
        #expect(!events.contains(.attempt(.gemini, model: "gemini-model")))
    }

    @Test func firstTextWinsAndLoserTextIsHidden() async {
        let chain = ProviderChain(steps: [step(.gemini, .reply(["медленно"], delay: 0.6)), step(.groq, .reply(["быстро"]))],
                                  hedgeAfter: 0.1)
        let (events, _) = await run(chain)
        #expect(text(events) == "быстро")
        #expect(!events.contains(.text("медленно")))
    }

    @Test func errorStartsNextImmediately() async {
        let chain = ProviderChain(steps: [step(.groq, .fail(.http(status: 503, message: "busy"))), step(.cerebras, .reply(["ok"]))],
                                  hedgeAfter: 5)
        let (events, seconds) = await run(chain)
        #expect(text(events) == "ok")
        #expect(events.contains(.providerFailed(.groq, .http(status: 503, message: "busy"))))
        #expect(seconds < 1)
    }

    @Test func brokenWinnerRestartsWithNextProvider() async {
        let chain = ProviderChain(steps: [step(.groq, .failAfter(["обо"], .network("reset"))), step(.gemini, .reply(["целый ответ"]))],
                                  hedgeAfter: 1)
        let (events, _) = await run(chain)
        #expect(text(events) == "целый ответ")
        #expect(events.contains(.restart(.gemini)))
    }

    @Test func allFailedIsExhaustedWithReasons() async {
        let chain = ProviderChain(steps: [step(.groq, .fail(.http(status: 429, message: ""))), step(.gemini, .fail(.firstTokenTimeout))],
                                  hedgeAfter: 0.5)
        let (events, _) = await run(chain)
        guard case .exhausted(let reason)? = events.last else { Issue.record("ожидался exhausted"); return }
        #expect(reason.contains("Groq") && reason.contains("Gemini"))
    }

    @Test func nonFallbackFailureStillEndsWithExhausted() async {
        // COPILOT-07: ошибка без перехода (отмена со стороны URLSession) не должна оставлять панель в «Готовлю подсказку…».
        let chain = ProviderChain(steps: [step(.groq, .fail(.cancelled)), step(.gemini, .reply(["ok"]))], hedgeAfter: 1)
        let (events, _) = await run(chain)
        guard case .exhausted? = events.last else { Issue.record("ожидался exhausted, получено \(events)"); return }
        #expect(!events.contains(.text("ok")))
    }

    @Test func groqRequestUsesLowReasoningWithoutReasoningText() async throws {
        let rec = RequestRecorder()
        let p = OpenAICompatibleProvider(.groq, transport: FixtureTransport(fixture: "deepseek-ok.sse", recorder: rec))
        var text = ""
        for try await e in p.stream(request, model: "openai/gpt-oss-120b", key: "g-test") { if case .text(let t) = e { text += t } }
        #expect(text == "• Seven years in iOS")
        let req = try #require(rec.requests.first)
        #expect(req.url?.absoluteString == "https://api.groq.com/openai/v1/chat/completions")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer g-test")
        let body = try #require(JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any])
        #expect(body["reasoning_effort"] as? String == "low")
        #expect(body["include_reasoning"] as? Bool == false)
        #expect(body["max_completion_tokens"] as? Int == 400 + 1024)
        #expect(body["stream_options"] == nil)
    }

    @Test func cerebrasRequestAndImagesFallBack() async throws {
        let rec = RequestRecorder()
        let p = OpenAICompatibleProvider(.cerebras, transport: FixtureTransport(fixture: "deepseek-ok.sse", recorder: rec))
        for try await _ in p.stream(request, model: "gpt-oss-120b", key: "c-test") {}
        let req = try #require(rec.requests.first)
        #expect(req.url?.absoluteString == "https://api.cerebras.ai/v1/chat/completions")
        let body = try #require(JSONSerialization.jsonObject(with: req.httpBody!) as? [String: Any])
        #expect(body["include_reasoning"] == nil)
        let screenshot = LLMRequest(system: "s", messages: [LLMMessage(role: .user, text: "q", images: [Data([1])])],
                                    maxTokens: 10, purpose: .screenshot)
        await #expect(throws: LLMError.self) { for try await _ in p.stream(screenshot, model: "gpt-oss-120b", key: "c") {} }
    }

    @Test func savedChainGetsFastProvidersFirstAndTheyAreFree() throws {
        var old = AppSettings()
        old.schemaVersion = 5
        old.chain = [.gemini, .deepseek, .anthropic]
        let s = old.migrated().normalized()
        #expect(s.chain == [.groq, .cerebras, .gemini, .deepseek, .anthropic, .custom])   // свой API — в конце (COPILOT-04 R-06)
        #expect(!ChainFactory.isPaid(.groq, settings: s))
        #expect(!ChainFactory.isPaid(.cerebras, settings: s))
        #expect(s.modelIDs.effective(.groq) == "openai/gpt-oss-120b")
        let decoded = try JSONDecoder().decode(ModelIDs.self, from: Data(#"{"gemini":"g"}"#.utf8))
        #expect(decoded.groq == "openai/gpt-oss-120b" && decoded.cerebras == "gpt-oss-120b")
    }
}
