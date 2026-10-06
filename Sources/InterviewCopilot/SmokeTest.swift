import CopilotCore
import Foundation

/// Живая проверка провайдеров из самого приложения (P-07): ключи читаются из Связки ключей процессом приложения,
/// в лог пишутся только ID моделей, задержки и число токенов — не ключи и не тексты (R-23, R-24).
/// Запуск: `open dist/InterviewCopilot.app --args --smoke-llm` или прямой запуск бинаря с этим флагом.
enum SmokeTest {
    static func run() -> Int32 {
        let settings = SettingsStore().load()
        let secrets = KeychainStore()
        let done = DispatchSemaphore(value: 0)
        let result = ResultBox()
        Task.detached {
            var ok = true
            for provider in ProviderID.allCases {
                guard let key = try? secrets.get(provider), !key.isEmpty else {
                    print("\(provider.rawValue): NOT RUN — нет ключа")
                    continue
                }
                let override = ProcessInfo.processInfo.environment["INTERVIEWCOPILOT_SMOKE_\(provider.rawValue.uppercased())_MODEL"]
                let configured = override ?? settings.modelIDs.effective(provider)
                let check = await KeyVerifier().verify(provider, key: key)
                switch check {
                case .ok(let models):
                    let present = models.contains(configured)
                    let related = models.filter { $0.contains("flash") || $0.contains("sonnet") || $0.contains("haiku") || $0.contains("deepseek") }
                    print("\(provider.rawValue): models=\(models.count) configured=\(configured) present=\(present) related=\(related.prefix(12).joined(separator: ","))")
                    if !present { ok = false }
                default:
                    print("\(provider.rawValue): key check \(check.summary)")
                    ok = false
                    continue
                }
                let request = PromptBuilder.hintRequest(question: "Почему вы хотите работать в нашей компании?", transcript: [],
                                                        cards: [], baseCard: nil, profile: Profile(name: "smoke", resume: "iOS developer, 7 years."),
                                                        redactPII: true)
                let env = ProcessInfo.processInfo.environment
                let llm: LLMProvider = provider == .gemini && env["INTERVIEWCOPILOT_SMOKE_GEMINI_THINKING"] != nil
                    ? GeminiProvider(hintThinkingLevel: env["INTERVIEWCOPILOT_SMOKE_GEMINI_THINKING"] == "none" ? nil : env["INTERVIEWCOPILOT_SMOKE_GEMINI_THINKING"])
                    : ChainFactory.providers()[provider]!
                let chain = ProviderChain(steps: [ProviderChain.Step(provider: llm, model: configured, key: key)],
                                          firstTokenTimeout: Double(ProcessInfo.processInfo.environment["INTERVIEWCOPILOT_SMOKE_TIMEOUT"] ?? "") ?? settings.firstTokenTimeout)
                let start = Date()
                var first: Double?
                var chars = 0
                var usage: TokenUsage?
                var failure: String?
                var model = configured
                for await e in chain.run(request) {
                    switch e {
                    case .firstToken(_, let ms): first = ms
                    case .text(let t): chars += t.count
                    case .usage(_, _, let u): usage = u
                    case .model(_, let m): model = m
                    case .providerFailed(_, let err): failure = err.description
                    default: break
                    }
                }
                let total = Date().timeIntervalSince(start) * 1000
                if let failure, chars == 0 {
                    print("\(provider.rawValue): stream FAIL \(failure)")
                    ok = false
                } else {
                    print(String(format: "%@: stream OK model=%@ first_token_ms=%.0f total_ms=%.0f chars=%d tokens_in=%d tokens_out=%d",
                                 provider.rawValue, model, first ?? -1, total, chars, usage?.input ?? 0, usage?.output ?? 0))
                }
            }
            // Цепочка из настроек целиком (R-09): фактический провайдер и модель.
            let chain = ChainFactory.chain(settings: settings, secrets: secrets, providers: ChainFactory.providers())
            let request = PromptBuilder.hintRequest(question: "Tell me about a time you failed.", transcript: [], cards: [], baseCard: nil,
                                                    profile: Profile(name: "smoke", resume: "iOS developer, 7 years."), redactPII: true)
            var log: [String] = []
            var finished = false
            for await e in chain.run(request) {
                switch e {
                case .attempt(let p, let m): log.append("try \(p.rawValue)/\(m)")
                case .providerFailed(let p, let err): log.append("fail \(p.rawValue): \(err.description)")
                case .firstToken(let p, let ms): log.append(String(format: "first \(p.rawValue) %.0fms", ms))
                case .finished(let p, let m): log.append("done \(p.rawValue)/\(m)"); finished = true
                case .exhausted(let reason): log.append("exhausted: \(reason)")
                default: break
                }
            }
            print("chain: " + log.joined(separator: " → "))
            result.ok = ok && finished
            done.signal()
        }
        done.wait()
        return result.ok ? 0 : 1
    }

    final class ResultBox: @unchecked Sendable { var ok = false }
}
