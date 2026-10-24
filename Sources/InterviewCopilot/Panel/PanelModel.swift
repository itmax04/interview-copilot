import CopilotCore
import Foundation
import Observation

/// Состояние плавающей панели — R-16.
@MainActor
@Observable
final class PanelModel {
    enum State: Equatable {
        case idle            // «Выберите источник»
        case listening
        case paused
        case thinking
        case answer
        case noMatch
        case error(String)
        case noPermission
        case downloading(Double)
        /// Сессии нет — приложение не слушает (COPILOT-09 R-02).
        case noSession
    }

    struct Line: Identifiable, Equatable {
        let id: Int
        let text: String
        /// Отфильтровано (COPILOT-05 R-06): «язык de» — серым, по клику — ответ.
        var filtered: String? = nil
    }

    var state: State = .idle
    var sourceName: String?
    /// Бейдж модели или «Bank».
    var badge: String?
    /// Задержка последнего ответа, с.
    var latency: Double?
    /// Последние реплики собеседника (не больше 3) и текущая частичная.
    var lines: [Line] = []
    var partial: String?
    /// Последний вопрос (ход).
    var question: String?

    // Ответ (P-08 заполняет карточку).
    var answerSource: String?
    var answerText: String = ""
    var answerTags: [String] = []
    var suggestions: [(id: String, score: Double)] = []
    var strongModelAvailable = false
    var strongModelName = "Claude"
    var strongModelHint = "Нет ключа Anthropic"

    // Внешний вид (R-16, R-18 Panel).
    var fontSize: Double = 14
    var hotkeys: [HotkeyAction: HotkeyBinding] = [:]

    func hotkey(_ action: HotkeyAction) -> String {
        (hotkeys[action] ?? HotkeyBinding.defaults[action]!).displayString
    }

    func setTranscript(_ finals: [ListeningController.TranscriptLine], partial: String?) {
        lines = finals.suffix(3).map { Line(id: $0.id, text: $0.text, filtered: $0.filtered) }
        self.partial = partial
    }

    /// Действия кнопок панели — подключает AppDelegate.
    var onCopy: (() -> Void)?
    /// Самопроверка: идёт запись ответа владельца (⌃⌥A, COPILOT-06).
    var ownerAnswering = false
    /// Источник — «Микрофон Mac»: в подвале подсказка «⌃⌥A я отвечаю» (COPILOT-07).
    var selfTest = false

    // Сессия (COPILOT-09 R-02, R-05).
    var sessionActive = false
    /// «12:47» — время сессии.
    var sessionTimer: String?
    /// «Осталось 5 минут по плану» и т. п.
    var planNotice: String?
    /// Похоже, начался звонок в этом приложении — предложить сессию.
    var callDetected: String?
    var onCreateSession: (() -> Void)?
    var onEndSession: (() -> Void)?
    var onStartDetectedCall: (() -> Void)?
    var onDismissDetectedCall: (() -> Void)?
    /// Клик по серой строке — ответить на неё (COPILOT-05 S-08).
    var onAnswerFiltered: ((String) -> Void)?
    var onStrongModel: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onRetry: (() -> Void)?
    var onOpenPermissions: (() -> Void)?
}
