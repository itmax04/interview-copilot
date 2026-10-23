import AppKit
import CopilotCore
import Foundation

/// Ответ на ход: база → режим → генерация со стримингом; сильная модель вручную (R-08…R-13, S-01…S-05, S-11).
@MainActor
final class AnswerController {
    private let model: AppModel
    private let bank: BankController
    private let panel: PanelModel
    private let providers: [ProviderID: LLMProvider]
    private var generation: Task<Void, Never>?
    private(set) var lastQuestion: Turn?
    private var lastMatch: BankMatch?
    /// Последние реплики собеседника для промпта (R-11: до 6).
    var transcript: () -> [String] = { [] }
    /// Учёт токенов и запросов (P-10).
    var onUsage: ((ProviderID, String, TokenUsage) -> Void)?
    /// Провайдер ответил ошибкой (для строки статуса «Gemini: limit»).
    var onProviderError: ((ProviderID, LLMError) -> Void)?
    /// Готовый ответ для истории сессии (P-10).
    var onAnswer: ((AnswerRecord) -> Void)?

    struct AnswerRecord {
        var turn: Turn
        var source: String          // bank / провайдер
        var model: String?
        var cardID: String?
        var text: String
        var firstTokenMs: Double?
        var cardShownMs: Double?
        var usage: TokenUsage?
    }

    init(model: AppModel, bank: BankController, panel: PanelModel,
         providers: [ProviderID: LLMProvider] = ChainFactory.providers()) {
        self.model = model
        self.bank = bank
        self.panel = panel
        self.providers = providers
        panel.onCopy = { [weak self] in self?.copyAnswer() }
        panel.onStrongModel = { [weak self] in self?.askStrongModel() }
        refreshStrongModelAvailability()
    }

    static func now() -> Double { TurnController.now() }

    func refreshStrongModelAvailability() {
        let s = model.settings
        // Только наличие ключа, без чтения значения: чтение Связки ключей может ждать подтверждения и не должно идти на главном потоке.
        let available = model.hasKey[s.strongProvider] == true
            && !(s.paidProvidersSuspended && ChainFactory.isPaid(s.strongProvider, settings: s))
        panel.strongModelAvailable = available
        panel.strongModelName = s.strongProvider.displayName
        panel.strongModelHint = available ? "Отправить вопрос в \(s.strongProvider.displayName) (\(s.hotkey(.strongModel).displayString))"
            : "Нет ключа \(s.strongProvider == .anthropic ? "Anthropic" : s.strongProvider.displayName)"
    }

    /// Новый ход: отменяет незавершённую генерацию прошлого (R-10).
    func handle(_ turn: Turn) {
        generation?.cancel()
        lastQuestion = turn
        panel.question = turn.text
        // COPILOT-04 R-01: ответ на этот текст уже готовится (или запрос ещё собирается — чтение ключей) —
        // ход забирает его, без нового запроса. Если опережающий запрос решит, что нужна карточка базы, ход пойдёт обычным путём.
        if let d = draft, d.text == turn.text, !d.declined {
            adopt(d, turn: turn)
            return
        }
        cancelDraft()
        answerNormally(turn)
    }

    private func answerNormally(_ turn: Turn) {
        let settings = model.settings
        generation = Task { [weak self] in
            guard let self else { return }
            // «Без профиля» (R-40): база не ищется, модель отвечает сама.
            guard settings.useProfile else {
                self.lastMatch = nil
                self.route(turn, match: BankMatch(matched: nil, top: []), settings: settings)
                return
            }
            guard let match = await self.bank.match(turn.text, threshold: settings.bankThreshold) else {
                // Базы нет (нет модели эмбеддингов) — генерация без карточек, если можно.
                self.route(turn, match: BankMatch(matched: nil, top: []), settings: settings)
                return
            }
            guard !Task.isCancelled else { return }
            self.lastMatch = match
            Log.metrics.notice("bank_match turn=\(turn.id) matched=\(match.matched != nil) score=\(match.top.first?.score ?? 0, format: .fixed(precision: 3)) ms_from_speech_end=\(Int(Self.now() - turn.speechEndedAt))")
            self.route(turn, match: match, settings: settings)
        }
    }

    /// Решение — по наличию ключей (без чтения значений): карточка базы не должна ждать Связку ключей (AC-02).
    private func modelsAvailable(_ settings: AppSettings) -> Bool {
        settings.chain.contains { p in
            model.hasKey[p] == true && !(settings.paidProvidersSuspended && ChainFactory.isPaid(p, settings: settings))
        }
    }

    private func hintRequest(question: String, base: BankCard?, top: [CardScore], settings: AppSettings) -> LLMRequest {
        PromptBuilder.hintRequest(question: question, transcript: transcript(), cards: top, baseCard: base,
                                  profile: settings.useProfile ? bank.profile : nil, redactPII: settings.piiFilterEnabled,
                                  answerLanguage: PromptBuilder.answerLanguage(setting: settings.language.whisperCode, question: question))
    }

    private func route(_ turn: Turn, match: BankMatch, settings: AppSettings) {
        let modelsAvailable = modelsAvailable(settings)
        switch AnswerRouter.decide(mode: settings.mode, match: match, modelsAvailable: modelsAvailable, useProfile: settings.useProfile) {
        case .bankCard(let card):
            showCard(card, turn: turn)
        case .noMatch(let top):
            showNoMatch(top, turn: turn, reason: modelsAvailable || (settings.mode == .bankOnly && settings.useProfile) ? nil : "Модели недоступны: нет ключей")
        case .generate(let base, let top):
            let request = hintRequest(question: turn.text, base: base, top: top, settings: settings)
            let secrets = model.secrets
            let providers = self.providers
            generation = Task { [weak self] in
                // Ключи читаются не на главном потоке.
                let chain = await Task.detached { ChainFactory.chain(settings: settings, secrets: secrets, providers: providers) }.value
                guard let self, !Task.isCancelled, self.lastQuestion?.id == turn.id else { return }
                self.generate(turn: turn, chain: chain, request: request, fallbackTop: top)
            }
        }
    }

    // MARK: Карточка из базы (S-01)

    private func showCard(_ card: CardScore, turn: Turn) {
        let shownMs = Self.now() - turn.speechEndedAt
        panel.answerSource = "Bank · \(card.card.id) · \(Int((card.score * 100).rounded()))%"
        panel.answerText = card.card.answer
        panel.answerTags = card.card.isSTAR ? ["S", "T", "A", "R"] : []
        panel.badge = "Bank"
        panel.latency = shownMs / 1000
        panel.suggestions = []
        panel.state = .answer
        // AC-02: turn_end → card_shown.
        Log.metrics.notice("card_shown turn=\(turn.id) card=\(card.card.id, privacy: .public) at_ms=\(Int(Self.now())) ms_from_speech_end=\(Int(shownMs)) ms_from_turn_end=\(Int(Self.now() - turn.firedAt))")
        onAnswer?(AnswerRecord(turn: turn, source: "bank", model: nil, cardID: card.card.id, text: card.card.answer,
                               firstTokenMs: nil, cardShownMs: shownMs, usage: nil))
    }

    // MARK: Нет в базе (S-02)

    private func showNoMatch(_ top: [CardScore], turn: Turn, reason: String?) {
        panel.answerSource = reason ?? "Нет в базе"
        panel.answerText = ""
        panel.answerTags = []
        panel.badge = "Bank"
        panel.latency = (Self.now() - turn.speechEndedAt) / 1000
        panel.suggestions = top.map { (id: $0.card.id, score: $0.score) }
        panel.state = .noMatch
        Log.metrics.notice("no_match turn=\(turn.id) ms_from_speech_end=\(Int(Self.now() - turn.speechEndedAt))")
        onAnswer?(AnswerRecord(turn: turn, source: "bank", model: nil, cardID: nil, text: "", firstTokenMs: nil, cardShownMs: nil, usage: nil))
    }

    // MARK: Генерация (S-03, S-04, R-10)

    private func generate(turn: Turn, chain: ProviderChain, request: LLMRequest, fallbackTop: [CardScore],
                          strong: Bool = false) {
        let consume = makeConsumer(turn: turn, purpose: request.purpose, fallbackTop: fallbackTop, strong: strong)
        generation = Task { [weak self] in
            for await event in chain.run(request) {
                if Task.isCancelled { return }
                self?.account(event)
                consume(event)
            }
        }
    }

    /// Расход и ошибки ключей учитываются там, где идёт запрос: и для ответа, и для опережающего запроса,
    /// который так и не понадобился (R-20, COPILOT-04 R-01).
    private func account(_ event: ChainEvent) {
        switch event {
        case .providerFailed(let p, let error):
            if error.isInvalidKey { model.markInvalidKey(p, error) }
            onProviderError?(p, error)
        case .usage(let p, let m, let u):
            onUsage?(p, m, u)
        default:
            break
        }
    }

    /// Вывод ответа в панель (S-03, S-04, R-10). `speculative` — ответ начат опережающим запросом (метрика COPILOT-04).
    private func makeConsumer(turn: Turn, purpose: LLMPurpose, fallbackTop: [CardScore], strong: Bool,
                              speculative: Bool = false) -> @MainActor (ChainEvent) -> Void {
        let previous = (panel.state, panel.answerSource, panel.answerText, panel.answerTags, panel.badge)
        panel.state = .thinking
        panel.suggestions = []
        var text = ""
        var provider: ProviderID?
        var actualModel: String?
        var firstMs: Double?
        var usage: TokenUsage?
        return { [weak self] event in
            guard let self else { return }
            switch event {
            case .attempt(let p, let m):
                provider = p
                actualModel = m
            case .model(let p, let m):
                provider = p
                actualModel = m
            case .firstToken:
                // Для опережающего запроса — момент показа: токены могли прийти раньше хода.
                let ms = Self.now() - turn.speechEndedAt
                firstMs = ms
                // AC-03: turn_end → first_token.
                Log.metrics.notice("first_token turn=\(turn.id) kind=\(purpose.rawValue, privacy: .public) provider=\(provider?.rawValue ?? "?", privacy: .public) at_ms=\(Int(Self.now())) ms_from_speech_end=\(Int(ms)) ms_from_turn_end=\(Int(Self.now() - turn.firedAt)) speculative=\(speculative ? 1 : 0)")
            case .text(let t):
                text += t
                // «—» — не вопрос: панель не меняется (R-11). Ждём, пока станет ясно.
                if PromptBuilder.isNoAnswer(text) || (text.count <= 2 && "—–-".contains(text.trimmingCharacters(in: .whitespaces))) { return }
                self.panel.state = .answer
                self.panel.answerSource = "\(Self.label(provider, actualModel)) · \(strong ? "strong" : "generated")"
                self.panel.answerText = text
                self.panel.answerTags = []
                self.panel.badge = Self.label(provider, actualModel)
                if let firstMs { self.panel.latency = firstMs / 1000 }
            case .restart:
                text = ""
            case .providerFailed:
                break // учтено в `account`
            case .usage(_, _, let u):
                usage = u // учтено в `account`
            case .finished:
                if PromptBuilder.isNoAnswer(text) {
                    (self.panel.state, self.panel.answerSource, self.panel.answerText, self.panel.answerTags, self.panel.badge) = previous
                    Log.metrics.notice("not_a_question turn=\(turn.id)")
                } else {
                    self.onAnswer?(AnswerRecord(turn: turn, source: provider?.rawValue ?? "?", model: actualModel, cardID: nil,
                                                text: text, firstTokenMs: firstMs, cardShownMs: nil, usage: usage))
                }
            case .exhausted(let reason):
                // S-04: понятная ошибка и поведение S-02.
                self.showNoMatch(fallbackTop, turn: turn, reason: "Модели недоступны: \(reason)")
            }
        }
    }

    // MARK: Опережающий запрос (COPILOT-04 R-01)

    /// Ответ модели, начатый до хода. События копятся, пока ход с тем же текстом не заберёт их (`attach`).
    @MainActor
    private final class Draft {
        let text: String
        let startedAt: Double
        var match = BankMatch(matched: nil, top: [])
        var fallbackTop: [CardScore] = []
        /// Решено генерировать и запрос к модели запущен (карточка базы опережающего запроса не требует).
        var generating = false
        /// Генерация не нужна (карточка базы или нет моделей) — ход отвечает обычным путём.
        var declined = false
        /// Ход, забравший запрос до решения: если запрос откажется, ход уйдёт обычным путём.
        var adoptedTurn: Turn?
        var task: Task<Void, Never>?
        private var buffered: [ChainEvent] = []
        private var consumer: (@MainActor (ChainEvent) -> Void)?

        init(text: String, startedAt: Double) {
            self.text = text
            self.startedAt = startedAt
        }

        var adopted: Bool { consumer != nil }

        func deliver(_ event: ChainEvent) {
            if let consumer { consumer(event) } else { buffered.append(event) }
        }

        func attach(_ consumer: @escaping @MainActor (ChainEvent) -> Void) {
            self.consumer = consumer
            let pending = buffered
            buffered = []
            pending.forEach(consumer)
        }
    }

    private var draft: Draft?

    /// Начать отвечать на законченную реплику до истечения паузы T. Повтор с тем же текстом ничего не делает,
    /// новый текст (собеседник продолжил) отменяет прежний запрос.
    func prefetch(_ text: String) {
        let settings = model.settings
        guard settings.speculativeAnswers, draft?.text != text else { return }
        cancelDraft()
        let d = Draft(text: text, startedAt: Self.now())
        draft = d
        let secrets = model.secrets
        let providers = self.providers
        d.task = Task { [weak self] in
            guard let self else { return }
            if settings.useProfile, let match = await self.bank.match(text, threshold: settings.bankThreshold) { d.match = match }
            guard !Task.isCancelled, self.draft === d || d.adopted else { return }
            if d.adoptedTurn != nil, settings.useProfile { self.lastMatch = d.match }
            guard case .generate(let base, let top) = AnswerRouter.decide(mode: settings.mode, match: d.match,
                                                                           modelsAvailable: self.modelsAvailable(settings),
                                                                           useProfile: settings.useProfile) else {
                d.declined = true
                if let turn = d.adoptedTurn, self.lastQuestion?.id == turn.id { self.answerNormally(turn) }
                return
            }
            let request = self.hintRequest(question: text, base: base, top: top, settings: settings)
            d.fallbackTop = top
            let chain = await Task.detached { ChainFactory.chain(settings: settings, secrets: secrets, providers: providers) }.value
            guard !Task.isCancelled, self.draft === d || d.adopted else { return }
            d.generating = true
            for await event in chain.run(request) {
                if Task.isCancelled { return }
                self.account(event)
                d.deliver(event)
            }
        }
    }

    /// Отменить опережающий запрос, который ход не забрал (пауза, новый текст, другой ход).
    func cancelDraft() {
        guard let d = draft else { return }
        draft = nil
        guard !d.adopted else { return }
        d.task?.cancel()
        Log.metrics.notice("draft_cancelled lead_ms=\(Int(Self.now() - d.startedAt)) generating=\(d.generating)")
    }

    private func adopt(_ d: Draft, turn: Turn) {
        draft = nil
        d.adoptedTurn = turn
        if model.settings.useProfile { lastMatch = d.match } else { lastMatch = nil }
        Log.metrics.notice("draft_used turn=\(turn.id) started_ms_from_speech_end=\(Int(d.startedAt - turn.speechEndedAt)) lead_ms=\(Int(turn.firedAt - d.startedAt)) generating=\(d.generating)")
        generation = d.task
        d.attach(makeConsumer(turn: turn, purpose: .hint, fallbackTop: d.fallbackTop, strong: false, speculative: true))
    }

    static func label(_ p: ProviderID?, _ model: String?) -> String {
        guard let p else { return "Model" }
        // Метка показывает фактическую модель (S-04): «Gemini», а для запасной модели — с её именем.
        if let model, p == .gemini, model != AppSettings().modelIDs.gemini { return "Gemini (\(model))" }
        if let model, p == .anthropic, model.contains("sonnet-5-5") == false { return "Claude (\(model))" }
        return p.displayName
    }

    // MARK: Сильная модель вручную (S-05, R-13)

    func askStrongModel() {
        let settings = model.settings
        guard let turn = lastQuestion else { return }
        let secrets = model.secrets
        let providers = self.providers
        Task { [weak self] in
            let chain = await Task.detached {
                ChainFactory.strong(settings: settings, secrets: secrets, providers: providers, fallbackToGemini: false)
            }.value
            self?.askStrongModel(turn: turn, settings: settings, chain: chain)
        }
    }

    private func askStrongModel(turn: Turn, settings: AppSettings, chain: ProviderChain?) {
        guard let chain else {
            panel.answerSource = panel.strongModelHint
            return
        }
        generation?.cancel()
        let request = PromptBuilder.strongRequest(question: turn.text, transcript: transcript(), cards: settings.useProfile ? lastMatch?.top ?? [] : [],
                                                  baseCard: settings.useProfile ? lastMatch?.matched?.card : nil,
                                                  profile: settings.useProfile ? bank.profile : nil,
                                                  redactPII: settings.piiFilterEnabled,
                                                  answerLanguage: PromptBuilder.answerLanguage(setting: settings.language.whisperCode, question: turn.text))
        // Задержка для сильной модели считаем от нажатия.
        let manual = Turn(id: turn.id, text: turn.text, speechEndedAt: Self.now(), firedAt: Self.now(), forced: true)
        generate(turn: manual, chain: chain, request: request, fallbackTop: lastMatch?.top ?? [], strong: true)
    }

    /// Ответ по скриншоту (P-09) использует тот же вывод.
    func showGenerated(chain: ProviderChain, request: LLMRequest, label turn: Turn) {
        generation?.cancel()
        generate(turn: turn, chain: chain, request: request, fallbackTop: [], strong: true)
    }

    func cancel() {
        generation?.cancel()
        cancelDraft()
    }

    private func copyAnswer() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(panel.answerText, forType: .string)
    }
}
