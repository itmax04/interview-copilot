import AppKit
import CopilotCore
import CopilotEmbeddings
import Foundation
import Observation

/// Профиль и база вопросов в приложении: копирование примера при первом запуске (R-21), загрузка, наблюдение
/// за `questions.yaml` с перечитыванием и пересчётом эмбеддингов в фоне (S-10), поиск по ходу (R-07).
@MainActor
@Observable
final class BankController {
    private(set) var profile = Profile(name: "Profile")
    private(set) var cards: [BankCard] = []
    private(set) var error: String?
    private(set) var status = "База не загружена"

    private var index: BankIndex?
    private var builder: BankIndexBuilder?
    private var watcher: FileWatcher?
    private var embedderModel: String?
    var onChange: (() -> Void)?

    var questionsURL: URL { AppPaths.profile.appendingPathComponent("questions.yaml") }

    /// Пример профиля внутри .app (scripts/build-app.sh) или рядом с исходниками при запуске из SwiftPM.
    static var exampleProfileURL: URL? {
        if let url = Bundle.main.url(forResource: "profile.example", withExtension: nil) { return url }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../profile.example").standardized
        return FileManager.default.fileExists(atPath: repo.path) ? repo : nil
    }

    func start(embeddingModel: String) {
        do {
            let copied = try ProfileStore.ensureProfile(at: AppPaths.profile, example: Self.exampleProfileURL)
            if !copied.isEmpty { Log.app.info("profile created from example: \(copied.count) files") }
        } catch {
            self.error = "Профиль: \(error.localizedDescription)"
        }
        profile = ProfileStore.load(from: AppPaths.profile)
        loadEmbedder(embeddingModel)
        reload()
        watcher = FileWatcher(url: questionsURL) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        watcher?.start()
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
        profile = ProfileStore.load(from: AppPaths.profile)
        let parsed: [BankCard]
        do {
            parsed = try QuestionBankParser.load(questionsURL)
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
        Task.detached(priority: .utility) { [builder, parsed] in
            let started = Date()
            let result = Result { try builder.build(parsed) }
            await MainActor.run { [weak self] in
                guard let self else { return }
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

    /// Поиск по базе (R-07). Эмбеддинг хода считается в фоне.
    func match(_ text: String, threshold: Double) async -> BankMatch? {
        guard let builder, let index else { return nil }
        return await Task.detached(priority: .userInitiated) {
            guard let v = try? builder.embedQuery(text) else { return nil as BankMatch? }
            return index.match(v, threshold: threshold)
        }.value
    }

    func openQuestions() {
        NSWorkspace.shared.open(questionsURL)
    }

    func openProfileFolder() {
        NSWorkspace.shared.open(AppPaths.profile)
    }
}
