import CopilotCore
import Foundation
import Observation

/// Состояние живого оверлея — R-16, COPILOT-09 R-07…R-11, R-17.
@MainActor
@Observable
final class PanelModel {
    /// Общее состояние слушания. Ответы — отдельно, в `history` (они живут и после конца сессии).
    enum State: Equatable {
        case idle            // «Выберите источник»
        case listening
        case paused
        case error(String)
        case noPermission
        case downloading(Double)
        /// Сессии нет — приложение не слушает (COPILOT-09 R-02).
        case noSession
    }

    /// Распознавание вопроса (R-08, решение владельца Q4): видно, что делает автоматика.
    enum Detection: Equatable {
        case idle
        /// Собеседник замолчал — ждём конца вопроса, опережающий запрос уже идёт.
        case checking
        case detected
        /// Модель решила, что это не вопрос — ответить можно вручную.
        case notQuestion
    }

    /// Режим поля чата (R-10).
    enum ChatMode: String, CaseIterable {
        case question = "Вопрос"
        case refine = "Уточнить ответ"
        case session = "На всю сессию"
    }

    struct Line: Identifiable, Equatable {
        let id: Int
        let text: String
        /// Отфильтровано (COPILOT-05 R-06): «язык de» — серым, по клику — ответ.
        var filtered: String? = nil
    }

    var state: State = .idle
    var sourceName: String?
    var detection: Detection = .idle
    /// Расшифровка собеседника (последние 6) и текущая частичная.
    var lines: [Line] = []
    var partial: String?
    var transcriptExpanded = false

    /// Ответы сессии с историей ←/→ (R-09).
    var history = AnswerHistory()
    var strongModelAvailable = false
    var strongModelName = "Claude"
    var strongModelHint = "Нет ключа Anthropic"

    // Внешний вид (R-16, R-18 Panel, COPILOT-09 R-11).
    var baseFontSize: Double = 14
    var zoom: Double = 1
    var fontSize: Double { (baseFontSize * zoom).rounded() }
    var hotkeys: [HotkeyAction: HotkeyBinding] = [:]
    var collapsed = false

    /// Подсказка клавиши: в сессии — ⌘-схема (Q10), вне сессии — ⌃⌥.
    func hotkey(_ action: HotkeyAction) -> String {
        if sessionActive, let b = HotkeyBinding.sessionDefaults[action] { return b.displayString }
        return (hotkeys[action] ?? HotkeyBinding.defaults[action]!).displayString
    }

    func setTranscript(_ finals: [ListeningController.TranscriptLine], partial: String?) {
        lines = finals.suffix(6).map { Line(id: $0.id, text: $0.text, filtered: $0.filtered) }
        self.partial = partial
    }

    // Самопроверка (COPILOT-06/07).
    var ownerAnswering = false
    var selfTest = false

    // Сессия (COPILOT-09 R-02, R-05).
    var sessionActive = false
    var sessionTimer: String?
    var planNotice: String?
    var callDetected: String?
    var autoGenerate = true
    /// Указания на сессию, добавленные из чата (видны значками, снимаются кликом).
    var sessionNotes: [String] = []

    // Звук (R-08): уровни для индикаторов и «не слышу звонок».
    var micLevel: Float = -120
    var callLevel: Float = -120
    /// Секунд без сигнала звонка во время сессии; nil — сигнал есть или проверка неуместна.
    var callSilentSeconds: Int?

    // Чат (R-10).
    var chatOpen = false
    var chatMode: ChatMode = .question
    var chatText = ""

    // Приватность (R-17).
    var hiddenFromCapture = false
    var visibilityResult: String?
    var checkingVisibility = false
    /// Метка для проверки видимости: на долю секунды оверлей заливается контрольным цветом.
    var visibilityProbe = false

    // Действия — подключает AppDelegate.
    var onCopy: (() -> Void)?
    var onAnswerFiltered: ((String) -> Void)?
    var onStrongModel: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onRetry: (() -> Void)?
    var onOpenPermissions: (() -> Void)?
    var onCreateSession: (() -> Void)?
    var onEndSession: (() -> Void)?
    var onStartDetectedCall: (() -> Void)?
    var onDismissDetectedCall: (() -> Void)?
    var onAnswerNow: (() -> Void)?
    var onScreenshot: (() -> Void)?
    var onToggleChat: (() -> Void)?
    var onChatSubmit: ((String, ChatMode) -> Void)?
    var onQuickRefine: ((String) -> Void)?
    var onClearTranscript: (() -> Void)?
    var onRetryAnswer: ((Int) -> Void)?
    var onRemoveSessionNote: ((Int) -> Void)?
    var onToggleAuto: (() -> Void)?
    var onSelectLanguage: ((RecognitionLanguage) -> Void)?
    var language: RecognitionLanguage = .auto
    var onZoom: ((Int) -> Void)?
    var onNextScreen: (() -> Void)?
    var onToggleCollapse: (() -> Void)?
    var onTogglePrivate: (() -> Void)?
    var onCheckVisibility: (() -> Void)?
    var onOwnerAnswer: (() -> Void)?

    func selectPrevious() { history.selectPrevious() }
    func selectNext() { history.selectNext() }
}
