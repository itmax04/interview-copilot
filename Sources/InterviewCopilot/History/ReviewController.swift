import CopilotCore
import Foundation
import Observation

/// Разбор после End — COPILOT-09 R-13 (Q15): в фоне, порциями (бесплатные лимиты), с сохранением после каждого шага.
/// Ошибка оставляет готовые комментарии и расшифровку; «Повторить» продолжает с места.
@MainActor
@Observable
final class ReviewController {
    /// Растет при каждом изменении сохраненного разбора — окно перечитывает запись.
    private(set) var version = 0
    /// Сессии, которые разбираются сейчас, и вопросы «Спросить ИИ» в работе.
    private(set) var running: Set<String> = []
    private(set) var asking: Set<String> = []
    /// Ошибка последнего вопроса — показывается под полем и не сохраняется в разбор.
    private(set) var askError: [String: String] = [:]

    private let store: SessionStore
    private let model: AppModel
    private let bank: BankController
    private let providers: [ProviderID: LLMProvider]

    init(store: SessionStore, model: AppModel, bank: BankController, providers: [ProviderID: LLMProvider] = ChainFactory.providers()) {
        self.store = store
        self.model = model
        self.bank = bank
        self.providers = providers
    }

    private func chain(for record: SessionRecord) async -> ProviderChain {
        var settings = model.settings
        if let c = record.config { settings.chain = c.chain(from: settings.chain) }
        let secrets = model.secrets, providers = providers
        return await Task.detached { ChainFactory.chain(settings: settings, secrets: secrets, providers: providers) }.value
    }

    /// Профиль сессии — для «как сказать лучше» по вашим фактам; обычный звонок — без резюме.
    private func profile(for record: SessionRecord) -> Profile? {
        guard record.config?.type != .regular, model.settings.useProfile else { return nil }
        let id = record.config?.profileID ?? bank.activeID
        guard let id, bank.profiles.contains(where: { $0.id == id }) else { return nil }
        return record.config.map { $0.applyingJob(to: bank.library.load(id)) } ?? bank.library.load(id)
    }

    private func update(_ id: String, _ change: (inout SessionReview) -> Void) -> SessionRecord? {
        guard var record = store.load(id) else { return nil }
        var review = record.review ?? SessionReview()
        change(&review)
        review.updatedAt = Date()
        record.review = review
        do { try store.save(record) } catch {
            Log.app.error("review save failed: \(error.localizedDescription, privacy: .public)")
        }
        version += 1
        return record
    }

    /// Разобрать сессию (после End или «Сделать разбор» / «Повторить» в окне).
    func start(_ id: String) {
        guard !running.contains(id), let record = store.load(id), record.canBeReviewed else { return }
        running.insert(id)
        let redact = model.settings.piiFilterEnabled
        let type = record.config?.type ?? .interview
        let profile = profile(for: record)
        Task {
            defer { running.remove(id); version += 1 }
            let chain = await chain(for: record)
            let total = record.reviewableExchanges.count
            var current = update(id) { $0.status = .running(done: $0.comments.count, total: total) } ?? record
            let started = Date()
            for batch in ReviewPrompt.pendingBatches(current) {
                let request = ReviewPrompt.commentsRequest(batch, type: type, profile: profile, redactPII: redact)
                switch await ChainText.collect(chain, request) {
                case .success(let text):
                    let comments = ReviewPrompt.parseComments(text, requested: batch.map(\.id))
                    guard !comments.isEmpty else {
                        _ = update(id) { $0.status = .failed("Модель ответила не в формате разбора — повторите") }
                        Log.app.error("review comments unparsable")
                        return
                    }
                    current = update(id) { r in
                        r.comments.append(contentsOf: comments)
                        r.status = .running(done: r.comments.count, total: total)
                    } ?? current
                case .failure(let e):
                    _ = update(id) { $0.status = .failed(e.description) }
                    return
                }
            }
            if current.review?.summary == nil {
                switch await ChainText.collect(chain, ReviewPrompt.summaryRequest(current, redactPII: redact)) {
                case .success(let text):
                    guard let summary = ReviewPrompt.parseSummary(text) else {
                        _ = update(id) { $0.status = .failed("Сводка не в формате — повторите") }
                        return
                    }
                    _ = update(id) { $0.summary = summary }
                case .failure(let e):
                    _ = update(id) { $0.status = .failed(e.description) }
                    return
                }
            }
            _ = update(id) { $0.status = .done }
            Log.app.info("review done comments=\(total) seconds=\(Int(Date().timeIntervalSince(started)))")
        }
    }

    /// «Спросить ИИ» о сессии; ответ сохраняется в разборе.
    func ask(_ id: String, question: String) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !asking.contains(id), let record = store.load(id) else { return }
        asking.insert(id)
        let redact = model.settings.piiFilterEnabled
        Task {
            defer { asking.remove(id); version += 1 }
            let chain = await chain(for: record)
            askError[id] = nil
            switch await ChainText.collect(chain, ReviewPrompt.askRequest(record, question: q, redactPII: redact)) {
            case .success(let text):
                let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = update(id) { r in
                    r.chat.append(ReviewQA(id: (r.chat.last?.id ?? 0) + 1, question: q, answer: answer))
                }
            case .failure(let e):
                askError[id] = e.description
            }
        }
    }
}
