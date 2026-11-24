import Foundation

/// Опережающий ответ только по повторно распознанному тексту (COPILOT-15 R-08).
///
/// Когда фраза закончилась и пауза T приближается, звук вопроса «на сейчас» уходит на повторное распознавание;
/// его текст — текст черновика. Ход с тем же итоговым повторным распознаванием (кэш по списку фраз) совпадёт
/// с черновиком и заберёт его (`AnswerController.handle`); если собеседник продолжил — черновик отменяется.
@MainActor
public final class DraftGate {
    /// Фразы → текст (nil — не вышло: черновика не будет).
    private let redecode: @MainActor ([Int]) async -> String?
    private let onDraft: (String) -> Void
    private let onCancel: () -> Void
    private var requested: [Int]?
    private var token = 0
    private var started = false

    public init(redecode: @escaping @MainActor ([Int]) async -> String?,
                onDraft: @escaping (String) -> Void,
                onCancel: @escaping () -> Void) {
        self.redecode = redecode
        self.onDraft = onDraft
        self.onCancel = onCancel
    }

    /// Черновик по накопленным фразам. Тот же список фраз второй раз не запрашивается.
    public func offer(utterances: [Int]) {
        guard !utterances.isEmpty, utterances != requested else { return }
        // Список изменился (собеседник продолжил) — прежний черновик и его запрос больше не нужны.
        if started { onCancel() }
        started = false
        requested = utterances
        token += 1
        let mine = token
        let redecode = redecode
        Task { @MainActor [weak self] in
            let text = await redecode(utterances)
            guard let self, self.token == mine, let text, !text.isEmpty else { return }
            self.started = true
            self.onDraft(text)
        }
    }

    /// Собеседник продолжил, пауза, Clear: незавершённый запрос отбрасывается, начатый черновик отменяется.
    public func cancel() {
        token += 1
        requested = nil
        if started { onCancel() }
        started = false
    }

    /// Ход наступил: поздний результат запроса не стартует черновик; начатый черновик остаётся — его заберёт ход.
    public func turnFired() {
        token += 1
        requested = nil
        started = false
    }
}
