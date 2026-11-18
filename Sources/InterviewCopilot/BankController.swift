import AppKit
import CopilotCore
import CopilotEmbeddings
import Foundation
import Observation

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

    let library = ProfileLibrary()
    private(set) var profiles: [ProfileInfo] = []
    private(set) var activeID: String?
    /// Общие инструкции владельца — для всех профилей и «Без профиля» (R-04).
    private(set) var generalInstructions = ""
    /// Активный профиль сменился (сохранить в настройки).
    var onActiveProfileChange: ((String) -> Void)?

    /// Материалы активного профиля и их индекс (R-06).
    private(set) var materials: [MaterialFile] = []
    private(set) var materialIndex = MaterialIndex.empty
    private(set) var materialStatus = ""
    private var embedder: TextEmbedder?
    private var materialTask: Task<Void, Never>?
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
        materialTask?.cancel()
        materialTask = nil
        // Построения уже отменены или скоро закончатся; ждём недолго, чтобы не повесить выход.
        _ = buildGroup.wait(timeout: .now() + 3)
        builder = nil
        index = nil
        embedder = nil   // тот же эмбеддер держал и индекс материалов: без этого модель жила до выхода
    }

    private func loadEmbedder(_ file: String) {
        // Та же модель грузится повторно, только если прошлая попытка не удалась: файл могли докачать уже после запуска.
        guard embedderModel != file || builder == nil else { return }
        // Смена модели: индекс и индекс материалов построены другой моделью, их векторы несравнимы с запросами новой;
        // незавершённое построение прежней модели не должно перезаписать статус и индекс (L1).
        if embedderModel != file {
            index = nil
            indexGeneration += 1
            materialIndex = .empty
        }
        embedderModel = file
        let path = AppPaths.model(file).path
        guard FileManager.default.fileExists(atPath: path) else {
            status = L("Нет модели эмбеддингов: %@ (scripts/fetch-models.sh)", "\(file)")
            builder = nil
            embedder = nil
            return
        }
        let spec = EmbeddingModels.spec(for: file)
        do {
            let embedder = try LlamaEmbedder(modelPath: path, prefix: spec.prefix)
            builder = BankIndexBuilder(embedder: embedder, cacheDirectory: AppPaths.cache)
            self.embedder = embedder
        } catch {
            status = L("Ошибка модели эмбеддингов: %@", "\(error)")
            builder = nil
            embedder = nil
        }
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
        embeddingModelChanged(file)
        if builder != nil { Log.app.info("embedding model loaded after download") }
    }

    // MARK: Материалы (R-06)

    /// Перечитать список и перестроить индекс в фоне (новые фрагменты считаются, старые — из кэша профиля).
    func reloadMaterials() {
        materialTask?.cancel()
        guard let id = activeID else { materials = []; materialIndex = .empty; return }
        materials = library.listMaterials(id)
        guard let embedder else {
            materialStatus = materials.isEmpty ? "" : "Нет модели эмбеддингов — поиск по материалам выключен"
            materialIndex = .empty
            return
        }
        if materials.isEmpty { materialIndex = .empty; materialStatus = ""; onChange?(); return }
        let files = library.materialTexts(id)
        let builder = MaterialIndexBuilder(embedder: embedder, cacheURL: library.materialsCacheURL(id))
        materialStatus = "Индексирую материалы…"
        onChange?()
        let started = Date()
        let report: @Sendable (Int, Int) -> Void = { [weak self] done, total in
            guard total > 0 else { return }
            Task { @MainActor in self?.materialProgress(done, of: total, profile: id) }
        }
        let group = buildGroup
        materialTask = Task { [weak self] in
            // Отмена `materialTask` сама до отдельной задачи не доходит: раньше прежняя индексация досчитывала
            // все фрагменты и занимала эмбеддер, хотя её результат уже никому не был нужен (COPILOT-13).
            group.enter()
            let work = Task.detached(priority: .utility) { () -> Result<MaterialIndex, Error> in
                defer { group.leave() }
                return Result { try builder.build(files, progress: report, isCancelled: { Task.isCancelled }) }
            }
            let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard let self, !Task.isCancelled, self.activeID == id else { return }
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

    private func materialProgress(_ done: Int, of total: Int, profile id: String) {
        guard activeID == id, materialTask != nil else { return }
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
        guard let builder else { return }
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
