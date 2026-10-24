import CopilotCore
import CopilotEmbeddings
import Foundation
import ImageIO

/// Живая проверка провайдеров из самого приложения (P-07): ключи читаются из Связки ключей процессом приложения,
/// в лог пишутся только ID моделей, задержки и число токенов — не ключи и не тексты (R-23, R-24).
/// Запуск: `open dist/InterviewCopilot.app --args --smoke-llm` или прямой запуск бинаря с этим флагом.
enum SmokeTest {
    /// `--smoke-screenshot <png>`: фикстура задачи → сильная модель или Gemini (S-06), в лог — модель, задержка, длина ответа
    /// и наличие разделов (код, сложность), без текста ответа.
    static func screenshot(path: String) -> Int32 {
        let settings = SettingsStore().load()
        let secrets = KeychainStore()
        let done = DispatchSemaphore(value: 0)
        let result = ResultBox()
        Task.detached {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let src = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
                  let jpeg = try? ScreenshotService.encode(image) else {
                print("screenshot: cannot read \(path)")
                done.signal()
                return
            }
            guard let chain = ChainFactory.strong(settings: settings, secrets: secrets, providers: ChainFactory.providers(),
                                                  fallbackToGemini: true) else {
                print("screenshot: NOT RUN — нет ключей")
                done.signal()
                return
            }
            let start = Date()
            var text = ""
            var log: [String] = []
            for await e in chain.run(PromptBuilder.screenshotRequest(image: jpeg, language: "ru")) {
                switch e {
                case .attempt(let p, let m): log.append("try \(p.rawValue)/\(m)")
                case .providerFailed(let p, let err): log.append("fail \(p.rawValue): \(err.description)")
                case .firstToken(let p, let ms): log.append(String(format: "first \(p.rawValue) %.0fms", ms))
                case .text(let t): text += t
                case .restart: text = ""
                case .finished(let p, let m): log.append("done \(p.rawValue)/\(m)"); result.ok = true
                case .exhausted(let r): log.append("exhausted: \(r)")
                default: break
                }
            }
            let hasCode = text.contains("```")
            let mentionsComplexity = text.range(of: "O\\(", options: .regularExpression) != nil
            print(String(format: "screenshot: jpeg=%d bytes total_ms=%.0f chars=%d code_block=%@ big_o=%@ | %@", jpeg.count,
                         Date().timeIntervalSince(start) * 1000, text.count, hasCode ? "yes" : "no", mentionsComplexity ? "yes" : "no",
                         log.joined(separator: " → ")))
            done.signal()
        }
        done.wait()
        return result.ok ? 0 : 1
    }

    /// `--smoke-memory [N]`: синтетические сценарии памяти и правил промпта (COPILOT-07) через цепочку из настроек,
    /// каждый N раз (по умолчанию 3). Печатаются провайдер, PASS/FAIL и первая строка ответа (данные синтетические).
    static func memory(runs: Int) -> Int32 {
        let settings = SettingsStore().load()
        let secrets = KeychainStore()
        let done = DispatchSemaphore(value: 0)
        let result = ResultBox()
        Task.detached {
            let chain = ChainFactory.chain(settings: settings, secrets: secrets, providers: ChainFactory.providers())
            var passed = 0, total = 0
            let only = ProcessInfo.processInfo.environment["INTERVIEWCOPILOT_SMOKE_ONLY"]
            for scenario in PromptScenarios.all where only.map({ scenario.name.contains($0) }) ?? true {
                for run in 1...runs {
                    var text = ""
                    var provider = "?"
                    var failure = ""
                    for await e in chain.run(PromptScenarios.request(scenario)) {
                        switch e {
                        case .finished(let p, let m): provider = "\(p.rawValue)/\(m)"
                        case .text(let t): text += t
                        case .restart: text = ""
                        case .exhausted(let r): failure = r
                        default: break
                        }
                    }
                    total += 1
                    try? await Task.sleep(for: .seconds(2))   // бесплатные лимиты: ~30 запросов в минуту
                    let verdict = failure.isEmpty ? scenario.check(text) : "нет ответа: \(failure)"
                    if verdict == nil { passed += 1 }
                    print("\(verdict == nil ? "PASS" : "FAIL") [\(scenario.name) #\(run)] \(provider) | "
                          + (verdict ?? PromptScenarios.firstLine(text)))
                    // Данные синтетические: полный ответ при FAIL — для разбора (INTERVIEWCOPILOT_SMOKE_FULL=1).
                    if verdict != nil, ProcessInfo.processInfo.environment["INTERVIEWCOPILOT_SMOKE_FULL"] != nil { print(text) }
                }
            }
            print("memory smoke: \(passed)/\(total)")
            result.ok = passed == total
            done.signal()
        }
        done.wait()
        return result.ok ? 0 : 1
    }

    /// `--smoke-prepare`: подготовка вопросов на настоящих моделях (COPILOT-08 R-08, R-09) — формулировки uk/ru/en,
    /// черновики по инструкции, ответ владельца не меняется, перефразированный вопрос на другом языке находит карточку (bge-m3).
    static func prepare() -> Int32 {
        let settings = SettingsStore().load()
        let secrets = KeychainStore()
        let done = DispatchSemaphore(value: 0)
        let result = ResultBox()
        Task.detached {
            var ok = true
            func check(_ pass: Bool, _ what: String) { print("\(pass ? "PASS" : "FAIL") \(what)"); if !pass { ok = false } }
            let chain = ChainFactory.chain(settings: settings, secrets: secrets, providers: ChainFactory.providers())
            let own = "Я iOS-розробник 7 років, останні 5 — у ФінБанку."
            var cards = [BankCard(id: "q-1", questions: ["Розкажіть про себе"], answer: own),
                         BankCard(id: "q-2", questions: ["Чому ви хочете змінити роботу?"], answer: ""),
                         BankCard(id: "q-3", questions: ["Як ви обробляєте помилки в мережевому шарі?"], answer: "")]
            switch await ChainText.collect(chain, QuestionPreparation.phrasingsRequest(cards)) {
            case .success(let text):
                let items = JSONExtract.array(text) ?? []
                let langsOK = cards.allSatisfy { c in
                    let item = items.first { ($0["id"] as? String) == c.id }
                    return ["uk", "ru", "en"].allSatisfy { ((item?[$0] as? [String]) ?? []).count >= 2 }
                }
                check(langsOK, "формулировки: у каждого вопроса ≥2 на uk, ru и en")
                cards = QuestionPreparation.applyPhrasings(text, to: cards, requested: cards.map(\.id))
                print("  q-2: " + cards[1].questions.joined(separator: " | "))
            case .failure(let e): check(false, "формулировки: \(e)")
            }
            var profile = PromptScenarios.sampleProfile
            profile.instructions = "Відповідай двома-трьома реченнями, без списків."
            let items = cards.filter { !$0.hasAnswer }.map { (card: $0, materials: [MaterialHit]()) }
            try? await Task.sleep(for: .seconds(2))
            switch await ChainText.collect(chain, QuestionPreparation.draftsRequest(items, profile: profile, generalInstructions: "",
                                                                                    redactPII: true)) {
            case .success(let text):
                cards = QuestionPreparation.applyDrafts(text, to: cards)
                check(cards[1].status == .draft && cards[2].status == .draft, "черновики: оба вопроса без ответа получили черновик")
                check(cards[0].answer == own && cards[0].status == .own, "ваш ответ не изменён")
                check(cards.dropFirst().allSatisfy { PromptScenarios.bullets($0.answer) == 0 }, "черновики: без списков по инструкции")
                print("  q-3: " + cards[2].answer.replacingOccurrences(of: "\n", with: " "))
            case .failure(let e): check(false, "черновики: \(e)")
            }
            let spec = EmbeddingModels.spec(for: settings.embeddingModel)
            if let embedder = try? LlamaEmbedder(modelPath: AppPaths.model(spec.file).path, prefix: spec.prefix),
               let index = try? BankIndexBuilder(embedder: embedder, cacheDirectory: nil).build(cards) {
                let builder = BankIndexBuilder(embedder: embedder, cacheDirectory: nil)
                for (q, id) in [("Tell me a bit about yourself", "q-1"), ("Почему вы решили уйти с текущего места?", "q-2"),
                                ("How do you deal with failed network requests?", "q-3")] {
                    let m = (try? builder.embedQuery(q)).map { index.match($0, threshold: settings.bankThreshold) }
                    check(m?.matched?.card.id == id, String(format: "поиск: «%@» → %@ (%.2f)", q, m?.matched?.card.id ?? "—", m?.top.first?.score ?? 0))
                }
            } else {
                print("NOT RUN поиск: нет модели bge-m3")
            }
            result.ok = ok
            done.signal()
        }
        done.wait()
        return result.ok ? 0 : 1
    }

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
