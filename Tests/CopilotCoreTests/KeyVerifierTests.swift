import Foundation
import Testing
@testable import CopilotCore

@Suite("KeyVerifier — R-18 «Проверить», R-23")
struct KeyVerifierTests {
    let key = "test-key-123"

    @Test func geminiOkParsesModelNamesAndUsesHeader() async throws {
        let t = MockTransport(status: 200, json: #"{"models":[{"name":"models/gemini-3.8-flash"},{"name":"models/gemini-3.8-pro"}]}"#)
        let r = await KeyVerifier(transport: t).verify(.gemini, key: key)
        #expect(r == .ok(models: ["gemini-3.8-flash", "gemini-3.8-pro"]))
        let req = try #require(t.requests.first)
        #expect(req.url?.absoluteString.hasPrefix("https://generativelanguage.googleapis.com/v1beta/models") == true)
        #expect(req.value(forHTTPHeaderField: "x-goog-api-key") == key)
        #expect(req.url?.absoluteString.contains(key) == false) // ключ не в URL
    }

    @Test func deepseekOk() async throws {
        let t = MockTransport(status: 200, json: #"{"object":"list","data":[{"id":"deepseek-flash","object":"model"}]}"#)
        let r = await KeyVerifier(transport: t).verify(.deepseek, key: key)
        #expect(r == .ok(models: ["deepseek-flash"]))
        let req = try #require(t.requests.first)
        #expect(req.url?.absoluteString == "https://api.deepseek.com/models")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer \(key)")
    }

    @Test func anthropicOkAndHeaders() async throws {
        let t = MockTransport(status: 200, json: #"{"data":[{"id":"claude-sonnet-5-5","type":"model"},{"id":"claude-haiku-4-5","type":"model"}],"has_more":false}"#)
        let r = await KeyVerifier(transport: t).verify(.anthropic, key: key)
        #expect(r == .ok(models: ["claude-sonnet-5-5", "claude-haiku-4-5"]))
        let req = try #require(t.requests.first)
        #expect(req.url?.host == "api.anthropic.com")
        #expect(req.value(forHTTPHeaderField: "x-api-key") == key)
        #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    }

    @Test(arguments: [400, 401, 403])
    func invalidKeyStatuses(status: Int) async {
        // Сообщение провайдера, в которое попал ключ, должно прийти без ключа.
        let t = MockTransport(status: status, json: #"{"error":{"message":"API key not valid: test-key-123"}}"#)
        let r = await KeyVerifier(transport: t).verify(.gemini, key: key)
        guard case .invalidKey(let s, let message) = r else { Issue.record("ожидался invalidKey, получено \(r)"); return }
        #expect(s == status)
        #expect(!message.contains(key))
        #expect(!r.summary.contains(key))
    }

    @Test func rateLimitIsNotInvalidKey() async {
        let r = await KeyVerifier(transport: MockTransport(status: 429, json: "{}")).verify(.gemini, key: key)
        guard case .failed = r else { Issue.record("ожидался failed, получено \(r)"); return }
    }

    @Test func networkError() async {
        let t = MockTransport { _ in throw URLError(.notConnectedToInternet) }
        let r = await KeyVerifier(transport: t).verify(.deepseek, key: key)
        guard case .failed = r else { Issue.record("ожидался failed"); return }
    }

    @Test func emptyKeyMakesNoRequest() async {
        let t = MockTransport(status: 200, json: "{}")
        let r = await KeyVerifier(transport: t).verify(.anthropic, key: "  ")
        #expect(r == .failed(message: "нет ключа"))
        #expect(t.requests.isEmpty)
    }
}
