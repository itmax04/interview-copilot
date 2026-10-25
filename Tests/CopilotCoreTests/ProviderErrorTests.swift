import Foundation
import Testing
@testable import CopilotCore

@Suite("Тексты ошибок провайдеров: без идентификаторов аккаунта и ключей — COPILOT-12")
struct ProviderErrorTests {
    @Test func groqOrganizationIdIsHidden() {
        let body = #"{"error":{"message":"Rate limit reached for model `openai/gpt-oss-120b` in organization `org_01abcdefghijkl` service tier `on_demand`"}}"#
        let message = SSE.errorMessage(body, key: "gsk_test_value_0000")
        #expect(message.contains("org_[id]") && !message.contains("org_01abcdefghijkl"))
        #expect(message.hasPrefix("Rate limit reached"))
    }

    @Test func keyLikeStringsAreHiddenEvenIfNotTheRequestKey() {
        let body = #"{"message":"invalid header gsk_ABCDEFGHIJKLMNOPQRST for sk-0123456789abcdef"}"#
        let message = SSE.errorMessage(body, key: "other-key-123456")
        #expect(!message.contains("gsk_ABCDEFGHIJKLMNOPQRST") && !message.contains("sk-0123456789abcdef"))
        #expect(message.contains("[key]"))
    }

    @Test func plainTextBodiesAreShownAndHtmlIsNot() {
        #expect(SSE.errorMessage("upstream connect error", key: "") == "upstream connect error")
        #expect(SSE.errorMessage("<html><body>502 Bad Gateway</body></html>", key: "").isEmpty)
        #expect(SSE.errorMessage(String(repeating: "x", count: 500), key: "").count == 200)
    }

    @Test func groqReasoningHeadroomIsSmallerForHints() throws {
        let p = OpenAICompatibleProvider(.groq)
        let hint = LLMRequest(system: "s", messages: [LLMMessage(role: .user, text: "q")], maxTokens: 400, purpose: .hint)
        let shot = LLMRequest(system: "s", messages: [LLMMessage(role: .user, text: "q")], maxTokens: 400, purpose: .screenshot)
        func budget(_ r: LLMRequest) throws -> Int? {
            let body = try JSONSerialization.jsonObject(with: try p.makeRequest(r, model: "openai/gpt-oss-120b", key: "k").httpBody!) as? [String: Any]
            return body?["max_completion_tokens"] as? Int
        }
        #expect(try budget(hint) == 912)
        #expect(try budget(shot) == 1424)
    }
}
