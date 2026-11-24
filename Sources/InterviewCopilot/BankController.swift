import AppKit
import CopilotCore
import CopilotEmbeddings
import Foundation
import Observation
import Synchronization

/// The operation owns the result until the main actor accepts it. Cancelled or superseded
/// operations can release their native model without waiting for the main actor during shutdown.
private final class EmbeddingModelLoad: Operation, @unchecked Sendable {
    typealias Prepared = (embedder: any TextEmbedder, builder: BankIndexBuilder)
    private let prepare: @Sendable () throws -> Prepared
    private let result = Mutex<Result<Prepared, Error>?>(nil)
    @MainActor var retryIfFailed = false

    init(prepare: @escaping @Sendable () throws -> Prepared) { self.prepare = prepare }

    override func main() {
        guard !isCancelled else { return }
        let prepared = Result(catching: prepare)
        result.withLock { if !isCancelled { $0 = prepared } }
    }

    override func cancel() {
        super.cancel()
        result.withLock { $0 = nil }
    }

    func takeResult() -> Result<Prepared, Error>? {
        result.withLock { stored in
            defer { stored = nil }
            return stored
        }
    }
}

/// Профили и база вопросов в приложении (COPILOT-08 R-01): перенос старой папки `profile/`, активный профиль, загрузка,
/// наблюдение за `questions.yaml` с перечитыванием и пересчётом эмбеддингов в фоне (S-10), поиск по ходу (R-07).
@MainActor
@Observable
final class BankController {
    private(set) var profile = Profile(name: ProfileLibrary.defaultName)
    private(set) var cards: [BankCard] = []
    private(set) var error: String?
    /// `questions.yaml` активного профиля существует, но не разбирается: запись из приложения затёрла бы файл, который
    /// ещё можно исправить вручную (COPILOT-13 M3). Сбрасывается удачным разбором.
    private(set) var questionsUnreadable = false
    private(set) var status = "База не загружена"

    let library: ProfileLibrary
    private let makeEmbedder: @Sendable (String) throws -> any TextEmbedder
    private let cacheDirectory: URL
    private let modelQueue = OperationQueue()
    private var modelLoad: EmbeddingModelLoad?

    init(library: ProfileLibrary = ProfileLibrary(), cacheDirectory: URL = AppPaths.cache,
         makeEmbedder: @escaping @Sendable (String) throws -> any TextEmbedder = { file in
             try LlamaEmbedder(modelPath: AppPaths.model(file).path, prefix: EmbeddingModels.spec(for: file).prefix)
         }) {
        self.library = library
        self.cacheDirectory = cacheDirectory
        self.makeEmbedder = makeEmbedder
        modelQueue.maxConcurrentOperationCount = 1
        modelQueue.qualityOfService = .utility
    }

    private(set) var profiles: [ProfileInfo] = []
    private(set) var activeID: String? {
        didSet { if oldValue != activeID { profileRevision += 1 } }
    }
    private(set) var profileRevision = 0
    /// Общие инструкции владельца — для всех профилей и «Без профиля» (R-04).
    private(set) var generalInstructions = ""
    /// Активный профиль сменился (сохранить в настройки).
    var onActiveProfileChange: ((String) -> Void)?

    /// Материалы активного профиля и их индекс (R-06).
    private(set) var materials: [MaterialFile] = []
    private(set) var materialTexts: [String] = []
    private(set) var materialIndex = MaterialIndex.empty
    private(set) var materialStatus = ""
    private var embedder: TextEmbedder?
    private var materialGeneration = 0
    private var materialTask: Task<Result<MaterialIndex, Error>, Never>?
    /// Фоновые построения индексов, держащие эмбеддер: `shutdown()` ждёт их, чтобы модель не освобождалась под ними (L2).
    private let buildGroup = DispatchGroup()

    private var index: BankIndex?
    private var builder: BankIndexBuilder?
    private var watcher: FileWatcher?
    private var embedderModel: String?
    /// Номер пересчёта индекса: результат более раннего пересчёта не должен заменить более поздний (COPILOT-13).
    private var indexGeneration = 0
    var onChange: (() -> Void)?

    var questionsURL: URL? { activeID.map { library.questionsURL($0) } }
    var activeDirectory: URL? { activeID.map { library.directory($0) } }

    /// Пример профиля внутри .app (scripts/build-app.sh) или рядом с исходниками при запуске из SwiftPM.
    /// С COPILOT-08 не копируется владельцу: по нему узнаётся неизменённый старый профиль, который удаляется (Q12).
    static var exampleProfileURL: URL? {
        if let url = Bundle.main.url(forResource: "profile.example", withExtension: nil) { return url }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../profile.example").standardized
        return FileManager.default.fileExists(atPath: repo.path) ? repo : nil
    }

    func start(embeddingModel: String, activeProfileID: String?) {
        var failure: String?
        do {
            switch try library.migrateLegacy(AppPaths.profile, example: Self.exampleProfileURL) {
            case .none: break
            case .removedExample: Log.app.info("legacy example profile removed")
            case .moved: Log.app.info("legacy profile moved to profiles/")
            }
            if library.list().isEmpty { try library.create(name: ProfileLibrary.defaultName) }
        } catch {
            failure = L("Профиль: %@", "\(error.localizedDescription)")
        }
        generalInstructions = ProfileLibrary.readGeneralInstructions()
        profiles = library.list()
        activeID = profiles.first { $0.id == activeProfileID }?.id ?? profiles.first?.id
        loadEmbedder(embeddingModel)
        reload()
        reloadMaterials()
        armWatcher()
        report(failure)
    }

    /// Ошибка операции (запись, переименование, удаление) показывается и после перечитывания базы:
    /// `reload()` при удачном разборе сбрасывает `error`, и раньше сообщение пропадало, не успев появиться (COPILOT-13).
    private func report(_ failure: String?) {
        guard let failure else { return }
        error = failure
        onChange?()
    }

    private func armWatcher() {
        watcher?.stop()
        guard let url = questionsURL else { watcher = nil; return }
        watcher = FileWatcher(url: url) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        watcher?.start()
    }

    // MARK: Профили (COPILOT-08 R-01, R-03)

    func select(_ id: String) {
        guard id != activeID, profiles.contains(where: { $0.id == id }) else { return }
        activeID = id
        index = nil   // карточки прежнего профиля не должны находиться, пока строится новый индекс
        indexGeneration += 1   // и пересчёт, начатый для прежнего профиля, уже не нужен (в т. ч. при возврате A → B → A)
        // Если questions.yaml нового профиля не разбирается, `reload()` оставляет прежние карточки (S-10) — но это
        // карточки другого профиля: таблица показала бы их, а сохранение записало бы в чужой файл (COPILOT-13).
        cards = []
        materialIndex = .empty
        reload()
        reloadMaterials()
        armWatcher()
        onActiveProfileChange?(id)
    }

    @discardableResult
    func createProfile(name: String) -> ProfileInfo? {
        do {
            let info = try library.create(name: name)
            profiles = library.list()
            select(info.id)
            return info
        } catch {
            self.error = L("Профиль: %@", "\(error.localizedDescription)")
            onChange?()
            return nil
        }
    }

    func renameActive(to name: String) {
        guard let id = activeID else { return }
        var failure: String?
        do { try library.rename(id, to: name) } catch { failure = L("Профиль: %@", "\(error.localizedDescription)") }
        profiles = library.list()
        reload()
        report(failure)
    }

    /// Удаление активного профиля; последний профиль не удаляется — вместо него создаётся пустой.
    func deleteActive() {
        guard let id = activeID else { return }
        var failure: String?
        do {
            try library.delete(id)
            if library.list().isEmpty { try library.create(name: ProfileLibrary.defaultName) }
        } catch {
            failure = L("Профиль: %@", "\(error.localizedDescription)")
        }
        profiles = library.list()
        activeID = nil
        if let first = profiles.first { select(first.id) } else { onChange?() }
        report(failure)
    }

    /// `profileID` — профиль, для которого открыт редактор: после смены профиля окно ещё успевает вызвать `onDisappear`
    /// старого редактора, и текст прежнего профиля записывался в новый (COPILOT-13).
    func text(_ doc: ProfileDocument, profileID: String? = nil) -> String {
        guard let id = profileID ?? activeID else { return "" }
        return library.read(doc, of: id)
    }

    func save(_ text: String, _ doc: ProfileDocument, profileID: String? = nil) {
        guard let id = profileID ?? activeID else { return }
        // Профиль, удалённый, пока редактор был открыт, не воскрешается записью файла в его папку.
        guard profiles.contains(where: { $0.id == id }) else { return }
        do { try library.write(text, doc, of: id) } catch { self.error = L("Профиль: %@", "\(error.localizedDescription)") }
        // Запись в неактивный профиль (редактор закрывается после смены профиля) не трогает загруженный профиль и индексы.
        guard id == activeID else { return }
        profile = library.load(id)
        if doc != .instructions { onChange?() }
    }

    /// Файл → текст раздела (R-02). Ошибку (скан, формат) — текстом для окна профиля.
    func importFile(_ url: URL, as doc: ProfileDocument) -> Result<String, Error> {
        guard let id = activeID else { return .failure(DocumentTextError.unreadable(url.lastPathComponent)) }
        let result = Result { try library.importFile(url, as: doc, into: id) }
        if case .success = result {
            profile = library.load(id)
            Log.app.info("profile document imported: \(doc.rawValue, privacy: .public) ext=\(url.pathExtension.lowercased(), privacy: .public)")
            onChange?()
        }
        return result
    }

    func saveGeneralInstructions(_ text: String) {
        do { try ProfileLibrary.writeGeneralInstructions(text) } catch { self.error = L("Инструкции: %@", "\(error.localizedDescription)") }
        generalInstructions = text
    }

    /// Освобождение моделей до выхода (ggml-metal падает, если ресурсы живы во время статических деструкторов).
    func shutdown() {
        watcher?.stop()
        modelLoad?.cancel()
        modelLoad = nil
        modelQueue.waitUntilAllOperationsAreFinished()
        indexGeneration += 1
        materialGeneration += 1
        materialTask?.cancel()
        materialTask = nil
        // Построения уже отменены или скоро закончатся; ждём недолго, чтобы не повесить выход.
        _ = buildGroup.wait(timeout: .now() + 3)
        builder = nil
        index = nil
        embedder = nil   // тот же эмбеддер держал и индекс материалов: без этого модель жила до выхода
    }

    private func loadEmbedder(_ file: String) {
        guard embedderModel != file || (builder == nil && modelLoad == nil) else { return }
        modelLoad?.cancel()
        embedderModel = file
        indexGeneration += 1
        index = nil
        builder = nil
        embedder = nil
        materialIndex = .empty
        status = L("Загружаю модель…")

        let load = EmbeddingModelLoad { [makeEmbedder, cacheDirectory] in
            let embedder = try makeEmbedder(file)
            let builder = BankIndexBuilder(embedder: embedder, cacheDirectory: cacheDirectory)
            return (embedder, builder)
        }
        modelLoad = load
        load.completionBlock = { [weak self, weak load] in
            Task { @MainActor [weak self, weak load] in
                guard let self, let load, self.modelLoad === load, let result = load.takeResult() else { return }
                self.modelLoad = nil
                switch result {
                case .success(let prepared):
                    self.embedder = prepared.embedder
                    self.builder = prepared.builder
                    self.buildBankIndex()
                case .failure where load.retryIfFailed:
                    self.loadEmbedder(file)
                    return
                case .failure(EmbedderError.modelNotFound):
                    self.status = L("Нет модели эмбеддингов: %@ (scripts/fetch-models.sh)", file)
                case .failure(let error):
                    self.status = L("Ошибка модели эмбеддингов: %@", "\(error)")
                }
                self.reloadMaterials()
                self.onChange?()
            }
        }
        modelQueue.addOperation(load)
    }

    func embeddingModelChanged(_ file: String) {
        loadEmbedder(file)
        reload()
        reloadMaterials()
    }

    /// Модели докачаны мастером первого запуска: если эмбеддер при старте не загрузился (файла ещё не было),
    /// загрузить его сейчас. Раньше база и поиск по материалам не работали до перезапуска приложения (COPILOT-13).
    func retryEmbedderIfMissing() {
        guard builder == nil, let file = embedderModel else { return }
        // A missing-file result may already be on its way to the main actor when the download finishes.
        if let modelLoad { modelLoad.retryIfFailed = true } else { loadEmbedder(file) }
    }

    // MARK: Материалы (R-06)

    /// Перечитать список и перестроить индекс в фоне (новые фрагменты считаются, старые — из кэша профиля).
    func reloadMaterials() {
        materialTask?.cancel()
        materialTask = nil
        materialGeneration += 1
        let generation = materialGeneration
        guard let id = activeID else { materials = []; materialTexts = []; materialIndex = .empty; return }
        materials = library.listMaterials(id)
        let files = library.materialTexts(id)
        materialTexts = files.map(\.text)
        guard let embedder else {
            materialStatus = materials.isEmpty ? "" : (modelLoad != nil ? L("Загружаю модель…") : "Нет модели эмбеддингов — поиск по материалам выключен")
            materialIndex = .empty
            return
        }
        if materials.isEmpty { materialIndex = .empty; materialStatus = ""; onChange?(); return }
        let cacheURL = library.materialsCacheURL(id)
        materialStatus = "Индексирую материалы…"
        onChange?()
        let started = Date()
        let report: @Sendable (Int, Int) -> Void = { [weak self] done, total in
            guard total > 0 else { return }
            Task { @MainActor in self?.materialProgress(done, of: total, generation: generation) }
        }
        let group = buildGroup
        group.enter()
        let work = Task.detached(priority: .utility) { () -> Result<MaterialIndex, Error> in
            defer { group.leave() }
            return Result {
                try Task.checkCancellation()
                let builder = MaterialIndexBuilder(embedder: embedder, cacheURL: cacheURL)
                return try builder.build(files, progress: report, isCancelled: { Task.isCancelled })
            }
        }
        materialTask = work
        Task { [weak self] in
            let result = await work.value
            guard let self, self.materialGeneration == generation else { return }
            self.materialTask = nil
            switch result {
            case .success(let index):
                self.materialIndex = index
                self.materialStatus = L("Материалы: %@ файл(ов), %@ фрагментов — готово", "\(self.materials.count)", "\(index.entries.count)")
                Log.app.info("materials index built files=\(self.materials.count) chunks=\(index.entries.count) ms=\(Int(Date().timeIntervalSince(started) * 1000))")
            case .failure(let error):
                if !(error is CancellationError) { self.materialStatus = L("Ошибка индекса материалов: %@", "\(error)") }
            }
            self.onChange?()
        }
    }

    private func materialProgress(_ done: Int, of total: Int, generation: Int) {
        guard materialGeneration == generation, materialTask != nil else { return }
        materialStatus = L("Индексирую материалы: %@ из %@ новых фрагментов", "\(done)", "\(total)")
    }

    /// Добавить файлы; ошибки (скан, формат) — по именам файлов.
    func addMaterials(_ urls: [URL]) -> [String] {
        guard let id = activeID else { return [] }
        var errors: [String] = []
        for url in urls {
            do { try library.addMaterial(url, into: id) } catch {
                errors.append((error as? DocumentTextError)?.description ?? "\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        Log.app.info("materials added=\(urls.count - errors.count) failed=\(errors.count)")
        reloadMaterials()
        return errors
    }

    func removeMaterial(_ name: String) {
        guard let id = activeID else { return }
        do { try library.removeMaterial(name, from: id) } catch { self.error = L("Материалы: %@", "\(error.localizedDescription)") }
        reloadMaterials()
    }

    // MARK: Вопросы (R-07)

    /// Сохранить вопросы активного профиля (таблица, импорт, подготовка) и перечитать базу.
    @discardableResult
    func saveCards(_ new: [BankCard]) -> Bool {
        guard let url = questionsURL else { return false }
        guard !questionsUnreadable else {
            report(L("Вопросы: файл questions.yaml не читается — исправьте его, затем повторите"))
            return false
        }
        var failure: String?
        do {
            try Data(QuestionBankWriter.yaml(new).utf8).write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            failure = L("Вопросы: %@", "\(error.localizedDescription)")
        }
        reload()
        report(failure)
        return failure == nil && !questionsUnreadable
    }

    /// Удалить все вопросы профиля сразу (COPILOT-11). Резюме, инструкции и материалы остаются.
    func deleteAllCards() {
        saveCards([])
    }

    /// Фрагменты материалов для вопроса (черновик ответа при подготовке).
    func materials(for question: String) async -> [MaterialHit] {
        await lookup(question, threshold: 1).materials
    }

    func materialText(_ name: String) -> String {
        guard let id = activeID else { return "" }
        return library.readMaterial(name, of: id)
    }

    /// Перечитать базу. При ошибке остаётся прежняя рабочая версия (S-10).
    func reload() {
        guard let id = activeID, let questionsURL else {
            questionsUnreadable = false
            cards = []
            onChange?()
            return
        }
        profile = library.load(id)
        let parsed: [BankCard]
        do {
            parsed = FileManager.default.fileExists(atPath: questionsURL.path) ? try QuestionBankParser.load(questionsURL) : []
            error = nil
            questionsUnreadable = false
        } catch let e as QuestionBankError {
            questionsUnreadable = true
            error = e.description
            Log.app.error("question bank parse error line=\(e.line ?? 0)")
            onChange?()
            return
        } catch {
            questionsUnreadable = true
            self.error = L("База вопросов: %@", error.localizedDescription)
            onChange?()
            return
        }
        cards = parsed
        onChange?()
        buildBankIndex()
    }

    private func buildBankIndex() {
        guard let builder, let id = activeID else { return }
        let parsed = cards
        status = "Пересчитываю эмбеддинги…"
        indexGeneration += 1
        let generation = indexGeneration
        let group = buildGroup
        group.enter()
        Task.detached(priority: .utility) { [builder, parsed, id] in
            let started = Date()
            // Вопросы без ответа в поиск не идут: опереться не на что (R-07); они ждут черновика.
            let result = Result { try builder.build(parsed.filter(\.hasAnswer)) }
            group.leave()
            await MainActor.run { [weak self] in
                // Профиль успели сменить или базу перечитали ещё раз — этот индекс устарел. Пересчёты заканчиваются
                // не по порядку: без номера удалённые карточки могли вернуться в поиск (COPILOT-13).
                guard let self, self.activeID == id, self.indexGeneration == generation else { return }
                switch result {
                case .success(let index):
                    self.index = index
                    self.status = L("База: %@ карточек", "\(parsed.count)")
                    Log.app.info("bank index built cards=\(parsed.count) ms=\(Int(Date().timeIntervalSince(started) * 1000))")
                case .failure(let error):
                    self.status = L("Ошибка индекса: %@", "\(error)")
                }
                self.onChange?()
            }
        }
    }

    /// Эмбеддинг произвольного текста той же моделью (bge-m3) — поиск по истории интервью (COPILOT-06).
    var embedFunction: (@Sendable (String) -> [Float]?)? {
        guard let builder else { return nil }
        return { text in try? builder.embedQuery(text) }
    }

    /// Поиск по базе (R-07) и по материалам (COPILOT-08 R-06) — один эмбеддинг хода, в фоне.
    /// `match` — nil, если базы нет (нет модели или индекс ещё строится).
    func lookup(_ text: String, threshold: Double) async -> (match: BankMatch?, materials: [MaterialHit]) {
        guard let builder else { return (nil, []) }
        let index = self.index
        let materials = materialIndex
        return await Task.detached(priority: .userInitiated) {
            guard let v = try? builder.embedQuery(text) else { return (nil as BankMatch?, [MaterialHit]()) }
            return (index?.match(v, threshold: threshold), materials.search(v))
        }.value
    }

    func openQuestions() {
        guard let url = questionsURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openProfileFolder() {
        guard let dir = activeDirectory else { return }
        NSWorkspace.shared.open(dir)
    }
}
