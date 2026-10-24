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
    private(set) var status = "База не загружена"

    let library = ProfileLibrary()
    private(set) var profiles: [ProfileInfo] = []
    private(set) var activeID: String?
    /// Общие инструкции владельца — для всех профилей и «Без профиля» (R-04).
    private(set) var generalInstructions = ""
    /// Активный профиль сменился (сохранить в настройки).
    var onActiveProfileChange: ((String) -> Void)?

    private var index: BankIndex?
    private var builder: BankIndexBuilder?
    private var watcher: FileWatcher?
    private var embedderModel: String?
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
        do {
            switch try library.migrateLegacy(AppPaths.profile, example: Self.exampleProfileURL) {
            case .none: break
            case .removedExample: Log.app.info("legacy example profile removed")
            case .moved: Log.app.info("legacy profile moved to profiles/")
            }
            if library.list().isEmpty { try library.create(name: ProfileLibrary.defaultName) }
        } catch {
            self.error = "Профиль: \(error.localizedDescription)"
        }
        generalInstructions = ProfileLibrary.readGeneralInstructions()
        profiles = library.list()
        activeID = profiles.first { $0.id == activeProfileID }?.id ?? profiles.first?.id
        loadEmbedder(embeddingModel)
        reload()
        armWatcher()
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
        reload()
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
            self.error = "Профиль: \(error.localizedDescription)"
            onChange?()
            return nil
        }
    }

    func renameActive(to name: String) {
        guard let id = activeID else { return }
        do { try library.rename(id, to: name) } catch { self.error = "Профиль: \(error.localizedDescription)" }
        profiles = library.list()
        reload()
    }

    /// Удаление активного профиля; последний профиль не удаляется — вместо него создаётся пустой.
    func deleteActive() {
        guard let id = activeID else { return }
        do {
            try library.delete(id)
            if library.list().isEmpty { try library.create(name: ProfileLibrary.defaultName) }
        } catch {
            self.error = "Профиль: \(error.localizedDescription)"
        }
        profiles = library.list()
        activeID = nil
        if let first = profiles.first { select(first.id) } else { onChange?() }
    }

    func text(_ doc: ProfileDocument) -> String {
        guard let id = activeID else { return "" }
        return library.read(doc, of: id)
    }

    func save(_ text: String, _ doc: ProfileDocument) {
        guard let id = activeID else { return }
        do { try library.write(text, doc, of: id) } catch { self.error = "Профиль: \(error.localizedDescription)" }
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
        do { try ProfileLibrary.writeGeneralInstructions(text) } catch { self.error = "Инструкции: \(error.localizedDescription)" }
        generalInstructions = text
    }

    /// Освобождение моделей до выхода (ggml-metal падает, если ресурсы живы во время статических деструкторов).
    func shutdown() {
        watcher?.stop()
        builder = nil
        index = nil
    }

    private func loadEmbedder(_ file: String) {
        guard embedderModel != file else { return }
        embedderModel = file
        let path = AppPaths.model(file).path
        guard FileManager.default.fileExists(atPath: path) else {
            status = "Нет модели эмбеддингов: \(file) (scripts/fetch-models.sh)"
            builder = nil
            return
        }
        let spec = EmbeddingModels.spec(for: file)
        do {
            let embedder = try LlamaEmbedder(modelPath: path, prefix: spec.prefix)
            builder = BankIndexBuilder(embedder: embedder, cacheDirectory: AppPaths.cache)
        } catch {
            status = "Ошибка модели эмбеддингов: \(error)"
            builder = nil
        }
    }

    func embeddingModelChanged(_ file: String) {
        loadEmbedder(file)
        reload()
    }

    /// Перечитать базу. При ошибке остаётся прежняя рабочая версия (S-10).
    func reload() {
        guard let id = activeID, let questionsURL else {
            cards = []
            onChange?()
            return
        }
        profile = library.load(id)
        let parsed: [BankCard]
        do {
            parsed = FileManager.default.fileExists(atPath: questionsURL.path) ? try QuestionBankParser.load(questionsURL) : []
            error = nil
        } catch let e as QuestionBankError {
            error = e.description
            Log.app.error("question bank parse error line=\(e.line ?? 0)")
            onChange?()
            return
        } catch {
            self.error = "Question bank: \(error.localizedDescription)"
            onChange?()
            return
        }
        cards = parsed
        onChange?()
        guard let builder else { return }
        status = "Пересчитываю эмбеддинги…"
        Task.detached(priority: .utility) { [builder, parsed, id] in
            let started = Date()
            let result = Result { try builder.build(parsed) }
            await MainActor.run { [weak self] in
                // Профиль успели сменить — индекс прежнего не нужен.
                guard let self, self.activeID == id else { return }
                switch result {
                case .success(let index):
                    self.index = index
                    self.status = "База: \(parsed.count) карточек"
                    Log.app.info("bank index built cards=\(parsed.count) ms=\(Int(Date().timeIntervalSince(started) * 1000))")
                case .failure(let error):
                    self.status = "Ошибка индекса: \(error)"
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

    /// Поиск по базе (R-07). Эмбеддинг хода считается в фоне.
    func match(_ text: String, threshold: Double) async -> BankMatch? {
        guard let builder, let index else { return nil }
        return await Task.detached(priority: .userInitiated) {
            guard let v = try? builder.embedQuery(text) else { return nil as BankMatch? }
            return index.match(v, threshold: threshold)
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
