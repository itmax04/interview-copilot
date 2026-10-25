import CopilotCore
import Foundation
import Observation

/// Импорт файла вопросов и подготовка (COPILOT-08 R-07, R-08) — в фоне, с прогрессом и отменой; цепочка моделей из настроек.
@MainActor
@Observable
final class QuestionPreparer {
    private let bank: BankController
    private let model: AppModel
    private let providers = ChainFactory.providers()
    private var task: Task<Void, Never>?

    private(set) var running = false
    private(set) var progress: (done: Int, total: Int) = (0, 0)
    private(set) var message: String?
    private(set) var failed = false
    /// Разобранные из файла вопросы — на проверку перед добавлением.
    var pendingImport: [ImportedQuestion]?

    init(bank: BankController, model: AppModel) {
        self.bank = bank
        self.model = model
    }

    private func chain() async -> ProviderChain {
        let settings = model.settings, secrets = model.secrets, providers = self.providers
        return await Task.detached { ChainFactory.chain(settings: settings, secrets: secrets, providers: providers) }.value
    }

    func cancel() {
        task?.cancel()
        task = nil
        running = false
        message = "Остановлено. Готовое сохранено."
        failed = false
    }

    // MARK: Импорт

    /// Файл → вопросы: правила; не подошли — модель, по частям. Результат — `pendingImport` для проверки.
    func importFile(_ url: URL) {
        guard !running else { return }
        let text: String
        do { text = try DocumentText.extract(from: url) } catch {
            fail((error as? DocumentTextError)?.description ?? error.localizedDescription)
            return
        }
        let byRules = QuestionImport.parseByRules(text)
        if !byRules.isEmpty {
            pendingImport = byRules
            succeed(L("В файле найдено вопросов: %lld. Проверьте и добавьте.", byRules.count))
            Log.app.info("questions import rules=\(byRules.count)")
            return
        }
        start(total: QuestionImport.chunks(text).count, label: "Разбираю файл моделью") { [weak self] in
            guard let self else { return }
            var found: [ImportedQuestion] = []
            let chain = await self.chain()
            for part in QuestionImport.chunks(text) {
                if Task.isCancelled { return }
                switch await ChainText.collect(chain, QuestionImport.llmRequest(part)) {
                case .success(let answer): found += QuestionImport.parseLLM(answer)
                case .failure(let e): self.fail(e.description); return
                }
                self.step()
            }
            Log.app.info("questions import llm=\(found.count)")
            if found.isEmpty { self.fail("Вопросов в файле не найдено. Добавьте их в таблицу вручную.") } else {
                self.pendingImport = found
                self.succeed(L("Модель нашла вопросов: %lld. Проверьте и добавьте.", found.count))
            }
        }
    }

    func acceptImport(_ items: [ImportedQuestion]) {
        pendingImport = nil
        guard !items.isEmpty else { return }
        bank.saveCards(QuestionImport.merge(items, into: bank.cards))
        succeed(L("Добавлено вопросов: %lld. Нажмите «Подготовить», чтобы добавить формулировки и черновики.", items.count))
    }

    // MARK: Подготовка

    var pendingWork: Int {
        QuestionPreparation.batches(QuestionPreparation.needsPhrasings(bank.cards), size: QuestionPreparation.phrasingBatch).count
            + QuestionPreparation.batches(QuestionPreparation.needsDraft(bank.cards), size: QuestionPreparation.draftBatch).count
    }

    /// Формулировки для неподготовленных и черновики для вопросов без ответа. Каждая пачка сохраняется сразу:
    /// остановка или ошибка не теряют готового.
    func prepare() {
        guard !running else { return }
        let phrasing = QuestionPreparation.batches(QuestionPreparation.needsPhrasings(bank.cards).map(\.id), size: QuestionPreparation.phrasingBatch)
        let drafting = QuestionPreparation.batches(QuestionPreparation.needsDraft(bank.cards).map(\.id), size: QuestionPreparation.draftBatch)
        guard !phrasing.isEmpty || !drafting.isEmpty else { succeed("Всё уже подготовлено."); return }
        let settings = model.settings
        start(total: phrasing.count + drafting.count, label: "Готовлю формулировки и черновики") { [weak self] in
            guard let self else { return }
            let chain = await self.chain()
            for ids in phrasing {
                if Task.isCancelled { return }
                let cards = self.bank.cards.filter { ids.contains($0.id) }
                switch await ChainText.collect(chain, QuestionPreparation.phrasingsRequest(cards)) {
                case .success(let text):
                    self.bank.saveCards(QuestionPreparation.applyPhrasings(text, to: self.bank.cards, requested: ids))
                case .failure(let e): self.fail(e.description); return
                }
                self.step()
            }
            for ids in drafting {
                if Task.isCancelled { return }
                var items: [(card: BankCard, materials: [MaterialHit])] = []
                for card in self.bank.cards where ids.contains(card.id) && !card.hasAnswer {
                    items.append((card, await self.bank.materials(for: card.questions.first ?? "")))
                }
                if !items.isEmpty {
                    let request = QuestionPreparation.draftsRequest(items, profile: self.bank.profile,
                                                                    generalInstructions: self.bank.generalInstructions,
                                                                    redactPII: settings.piiFilterEnabled)
                    switch await ChainText.collect(chain, request) {
                    case .success(let text): self.bank.saveCards(QuestionPreparation.applyDrafts(text, to: self.bank.cards))
                    case .failure(let e): self.fail(e.description); return
                    }
                }
                self.step()
            }
            let drafts = self.bank.cards.filter { $0.status == .draft }.count
            self.succeed(drafts > 0 ? L("Готово. Черновиков на проверку: %lld — подтвердите или поправьте.", drafts) : L("Готово."))
            Log.app.info("questions prepared batches=\(phrasing.count + drafting.count)")
        }
    }

    // MARK: Внутреннее

    private func start(total: Int, label: String, _ work: @escaping @MainActor () async -> Void) {
        running = true
        failed = false
        progress = (0, total)
        message = label + "…"
        task = Task { [weak self] in
            await work()
            self?.running = false
            self?.task = nil
        }
    }

    private func step() {
        progress.done += 1
        message = L("Готово %lld из %lld частей…", progress.done, progress.total)
    }

    private func succeed(_ text: String) {
        message = text
        failed = false
    }

    private func fail(_ text: String) {
        message = text
        failed = true
        running = false
    }
}
