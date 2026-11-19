import CopilotCore
import Foundation
import Observation

/// Импорт файла вопросов и подготовка (COPILOT-08 R-07, R-08) — в фоне, с прогрессом и отменой; цепочка моделей из настроек.
@MainActor
@Observable
final class QuestionPreparer {
    private let bank: BankController
    private let model: AppModel
    private let extract: @Sendable (URL) throws -> String
    private let providers = ChainFactory.providers()
    private var task: Task<Void, Never>?
    /// Номер запущенной работы. Остановленная или прежняя работа ещё доходит до ближайшего `await` и не должна менять
    /// состояние: раньше после «Остановить» сообщение «Остановлено. Готовое сохранено.» сразу сменялось ошибкой
    /// «Модели недоступны: нет ответа» — прерванный запрос возвращался как неудачный (COPILOT-13).
    private var generation = 0

    private(set) var running = false
    private(set) var progress: (done: Int, total: Int) = (0, 0)
    private(set) var message: String?
    private(set) var failed = false
    /// Разобранные из файла вопросы — на проверку перед добавлением.
    private var importProfileRevision: Int?
    private var importedQuestions: [ImportedQuestion]?
    var pendingImport: [ImportedQuestion]? {
        get { bank.profileRevision == importProfileRevision ? importedQuestions : nil }
        set { importedQuestions = newValue }
    }

    init(bank: BankController, model: AppModel, extract: @escaping @Sendable (URL) throws -> String = DocumentText.extract) {
        self.bank = bank
        self.model = model
        self.extract = extract
    }

    private func chain() async -> ProviderChain {
        let settings = model.settings, secrets = model.secrets, providers = self.providers
        return await Task.detached { ChainFactory.chain(settings: settings, secrets: secrets, providers: providers) }.value
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        running = false
        message = "Остановлено. Готовое сохранено."
        failed = false
    }

    // MARK: Импорт

    private enum ParsedImport {
        case questions([ImportedQuestion])
        case chunks([String])
    }

    // PDFKit works on a document local to this task. AppKit document import for Word and RTF stays on the main actor.
    @concurrent private static func readPDF(_ url: URL, extract: @Sendable (URL) throws -> String) async throws -> String {
        try Task.checkCancellation()
        return try extract(url)
    }

    @concurrent private static func parseImport(_ text: String) async throws -> ParsedImport {
        try Task.checkCancellation()
        let questions = QuestionImport.parseByRules(text)
        return questions.isEmpty ? .chunks(QuestionImport.chunks(text)) : .questions(questions)
    }

    @concurrent private static func parseModelResponse(_ text: String) async -> [ImportedQuestion] {
        QuestionImport.parseLLM(text)
    }

    /// Файл → вопросы: правила; не подошли — модель, по частям. Результат — `pendingImport` для проверки.
    func importFile(_ url: URL) {
        guard !running else { return }
        let revision = bank.profileRevision
        importProfileRevision = revision
        pendingImport = nil
        start(total: 1, label: L("Читаю файл")) { [weak self] run in
            guard let self, self.isCurrent(run), self.sameImportProfile(revision) else { return }
            let parsed: ParsedImport
            do {
                let text = url.pathExtension.lowercased() == "pdf" ? try await Self.readPDF(url, extract: self.extract) : try self.extract(url)
                guard self.isCurrent(run), self.sameImportProfile(revision) else { return }
                parsed = try await Self.parseImport(text)
            } catch {
                guard self.isCurrent(run), self.sameImportProfile(revision) else { return }
                self.fail((error as? DocumentTextError)?.description ?? error.localizedDescription)
                return
            }
            guard self.isCurrent(run), self.sameImportProfile(revision) else { return }
            switch parsed {
            case .questions(let questions):
                self.pendingImport = questions
                self.succeed(L("В файле найдено вопросов: %lld. Проверьте и добавьте.", questions.count))
                Log.app.info("questions import rules=\(questions.count)")
            case .chunks(let chunks):
                await self.importWithModel(chunks, run: run, revision: revision)
            }
        }
    }

    private func importWithModel(_ chunks: [String], run: Int, revision: Int) async {
        progress = (0, chunks.count)
        message = L("Разбираю файл моделью…")
        var found: [ImportedQuestion] = []
        let chain = await chain()
        for part in chunks {
            guard isCurrent(run), sameImportProfile(revision) else { return }
            let result = await ChainText.collect(chain, QuestionImport.llmRequest(part))
            guard isCurrent(run), sameImportProfile(revision) else { return }
            switch result {
            case .success(let answer):
                let questions = await Self.parseModelResponse(answer)
                guard isCurrent(run), sameImportProfile(revision) else { return }
                found += questions
            case .failure(let error): fail(error.description); return
            }
            step()
        }
        guard isCurrent(run), sameImportProfile(revision) else { return }
        Log.app.info("questions import llm=\(found.count)")
        if found.isEmpty { fail("Вопросов в файле не найдено. Добавьте их в таблицу вручную.") } else {
            pendingImport = found
            succeed(L("Модель нашла вопросов: %lld. Проверьте и добавьте.", found.count))
        }
    }

    func acceptImport(_ items: [ImportedQuestion]) {
        guard !items.isEmpty, sameImportProfile(importProfileRevision), pendingImport != nil else { pendingImport = nil; return }
        guard save(QuestionImport.merge(items, into: bank.cards)) else { return }
        pendingImport = nil
        succeed(L("Добавлено вопросов: %lld. Нажмите «Подготовить», чтобы добавить формулировки и черновики.", items.count))
    }

    private func sameImportProfile(_ revision: Int?) -> Bool {
        guard bank.profileRevision != revision else { return true }
        fail(L("Профиль сменили — импорт остановлен."))
        return false
    }

    private func save(_ cards: [BankCard]) -> Bool {
        guard bank.saveCards(cards) else {
            fail(bank.error ?? L("Не удалось сохранить вопросы"))
            return false
        }
        return true
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
        // Подготовка относится к профилю, с которого начата. Номера карточек (q-1, q-2…) в профилях совпадают: после смены
        // профиля формулировки и черновики чужих вопросов записались бы в карточки нового профиля (COPILOT-13).
        let profileID = bank.activeID
        start(total: phrasing.count + drafting.count, label: "Готовлю формулировки и черновики") { [weak self] run in
            guard let self else { return }
            let chain = await self.chain()
            for ids in phrasing {
                guard self.isCurrent(run), self.sameProfile(profileID) else { return }
                let cards = self.bank.cards.filter { ids.contains($0.id) }
                let result = await ChainText.collect(chain, QuestionPreparation.phrasingsRequest(cards))
                guard self.isCurrent(run), self.sameProfile(profileID) else { return }
                switch result {
                case .success(let text):
                    guard self.save(QuestionPreparation.applyPhrasings(text, to: self.bank.cards, requested: ids)) else { return }
                case .failure(let e): self.fail(e.description); return
                }
                self.step()
            }
            for ids in drafting {
                guard self.isCurrent(run), self.sameProfile(profileID) else { return }
                var items: [(card: BankCard, materials: [MaterialHit])] = []
                for card in self.bank.cards where ids.contains(card.id) && !card.hasAnswer {
                    items.append((card, await self.bank.materials(for: card.questions.first ?? "")))
                }
                guard self.isCurrent(run), self.sameProfile(profileID) else { return }
                if !items.isEmpty {
                    let request = QuestionPreparation.draftsRequest(items, profile: self.bank.profile,
                                                                    generalInstructions: self.bank.generalInstructions,
                                                                    redactPII: settings.piiFilterEnabled)
                    let result = await ChainText.collect(chain, request)
                    guard self.isCurrent(run), self.sameProfile(profileID) else { return }
                    switch result {
                    case .success(let text):
                        guard self.save(QuestionPreparation.applyDrafts(text, to: self.bank.cards, requested: items.map { $0.card.id })) else { return }
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

    private func start(total: Int, label: String, _ work: @escaping @MainActor (Int) async -> Void) {
        generation += 1
        let run = generation
        running = true
        failed = false
        progress = (0, total)
        message = label + "…"
        task = Task { [weak self] in
            await work(run)
            // Прежняя работа, закончившись позже, не сбрасывает состояние новой.
            guard let self, self.generation == run else { return }
            self.running = false
            self.task = nil
        }
    }

    /// Работа `run` — всё ещё текущая: её не остановили и после неё не начали другую.
    private func isCurrent(_ run: Int) -> Bool { generation == run && !Task.isCancelled }

    /// Активный профиль — тот, с которого начата подготовка; иначе она останавливается с сообщением.
    private func sameProfile(_ id: String?) -> Bool {
        guard bank.activeID != id else { return true }
        fail(L("Профиль сменили — подготовка остановлена. Готовое сохранено в прежнем профиле."))
        Log.app.info("questions preparation stopped: profile changed")
        return false
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
