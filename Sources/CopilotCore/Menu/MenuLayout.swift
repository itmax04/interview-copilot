import Foundation

/// Глобальная горячая клавиша ⌃⌥ + клавиша (R-17, допущение A-3).
public struct Shortcut: Sendable, Equatable {
    public enum Key: Sendable, Equatable {
        case character(Character)
        case returnKey
    }

    public var key: Key
    /// true — ⌃⌥ (глобальные клавиши помощника), false — ⌘ (стандартные пункты меню).
    public var controlOption: Bool

    public static func ctrlOpt(_ c: Character) -> Shortcut { Shortcut(key: .character(c), controlOption: true) }
    public static let ctrlOptReturn = Shortcut(key: .returnKey, controlOption: true)
    public static func command(_ c: Character) -> Shortcut { Shortcut(key: .character(c), controlOption: false) }
}

/// Действие пункта меню; обрабатывается в приложении.
public enum MenuAction: String, Sendable, Equatable {
    case listeningSource, togglePause
    case mode, models, language
    case profile, questionBank, editProfile, practice, aiInterview
    case answerNow, screenshot, togglePanel, sessionHistory
    /// Сессия (COPILOT-09 R-01, R-02): мастер «Создать сессию…» и «Завершить сессию».
    case newSession, endSession
    /// Самопроверка «Микрофон Mac»: «сейчас отвечаю я» (COPILOT-06, пункт меню — COPILOT-07).
    case ownerAnswer
    case status
    case settings, quit
}

/// Описание пункта меню без зависимости от AppKit — R-15, проверяется тестами (AC-11).
public struct MenuItemSpec: Sendable, Equatable {
    public var action: MenuAction
    public var title: String
    /// Имя SF Symbol для иконки слева.
    public var symbol: String
    public var shortcut: Shortcut?
    /// Глобальная горячая клавиша помощника (R-17), если у пункта она есть; показывается как сочетание меню.
    public var hotkey: HotkeyBinding?
    public var hasSubmenu: Bool
    public var enabled: Bool
    /// Цветная точка статуса вместо иконки (первая строка).
    public var statusDot: StatusDot?
    /// Пометка справа, например «soon».
    public var badge: String?

    public init(_ action: MenuAction, _ title: String, symbol: String, shortcut: Shortcut? = nil, hotkey: HotkeyBinding? = nil,
                submenu: Bool = false, enabled: Bool = true, statusDot: StatusDot? = nil, badge: String? = nil) {
        self.action = action
        self.title = title
        self.symbol = symbol
        self.shortcut = shortcut
        self.hotkey = hotkey
        self.hasSubmenu = submenu
        self.enabled = enabled
        self.statusDot = statusDot
        self.badge = badge
    }
}

/// Данные, из которых строится меню.
public struct MenuState: Sendable, Equatable {
    public var listening: ListeningStatus
    public var mode: AnswerMode
    public var chain: [ProviderID]
    public var language: RecognitionLanguage
    public var profileName: String
    /// false — «Без профиля» (R-40): заголовок пункта Profile показывает это вместо названия профиля.
    public var useProfile: Bool
    public var bankCardCount: Int
    public var strongModelName: String
    public var statusLine: String
    public var hotkeys: [HotkeyAction: HotkeyBinding]
    public var panelVisible: Bool
    /// Ошибка разбора questions.yaml (S-10): показывается вместо числа карточек, прежняя база продолжает работать.
    public var bankError: String?
    /// Источник — «Микрофон Mac» (самопроверка): в меню есть «Сейчас отвечаю я» (COPILOT-07).
    public var selfTest = false
    /// Идёт запись ответа владельца (⌃⌥A).
    public var ownerAnswering = false
    /// Профили для подменю Profile и активный (COPILOT-08 R-01).
    public var profiles: [ProfileInfo] = []
    public var activeProfileID: String?
    /// Идёт сессия и её время (COPILOT-09).
    public var sessionActive = false
    public var sessionTimer: String?

    public init(listening: ListeningStatus = .idle, mode: AnswerMode = .bankAndHint,
                chain: [ProviderID] = [.gemini, .deepseek, .anthropic], language: RecognitionLanguage = .auto,
                profileName: String = "Example", useProfile: Bool = true, bankCardCount: Int = 0, strongModelName: String = "Claude",
                statusLine: String = "Сегодня: $0.00 · Gemini: 0 запр.",
                hotkeys: [HotkeyAction: HotkeyBinding] = [:], panelVisible: Bool = false) {
        self.listening = listening
        self.mode = mode
        self.chain = chain
        self.language = language
        self.profileName = profileName
        self.useProfile = useProfile
        self.bankCardCount = bankCardCount
        self.strongModelName = strongModelName
        self.statusLine = statusLine
        self.hotkeys = hotkeys
        self.panelVisible = panelVisible
    }

    public func hotkey(_ action: HotkeyAction) -> HotkeyBinding {
        hotkeys[action] ?? HotkeyBinding.defaults[action]!
    }
}

public enum MenuLayout {
    /// Пункт подменю Profile и заголовок, когда профиль не используется (R-40).
    public static var noProfileTitle: String { L10n.t("Без профиля") }
    /// Секции меню сверху вниз; между секциями — разделители. Состав и порядок — R-15.
    public static func sections(for s: MenuState) -> [[MenuItemSpec]] {
        let listeningTitle: String
        let paused: Bool
        switch s.listening {
        case .listening(let app): listeningTitle = L10n.f("Слушаю — %@", app); paused = false
        case .paused(let app): listeningTitle = L10n.f("Пауза — %@", app); paused = true
        case .noPermission: listeningTitle = L10n.t("Нет разрешения на запись экрана"); paused = false
        case .idle: listeningTitle = L10n.t("Слушаю — выберите источник"); paused = false
        case .noSession: listeningTitle = L10n.t("Нет сессии — не слушаю"); paused = false
        }
        let chainTitle = s.chain.map(\.displayName).joined(separator: " → ")
        var actions = [
            MenuItemSpec(.answerNow, L10n.t("Ответить сейчас"), symbol: "bolt", hotkey: s.hotkey(.answerNow)),
            MenuItemSpec(.screenshot, L10n.f("Скриншот → %@", s.strongModelName), symbol: "camera", hotkey: s.hotkey(.screenshot)),
            MenuItemSpec(.togglePanel, s.panelVisible ? L10n.t("Скрыть оверлей") : L10n.t("Показать оверлей"), symbol: "macwindow",
                         hotkey: s.hotkey(.togglePanel)),
            MenuItemSpec(.sessionHistory, L10n.t("История сессий…"), symbol: "clock"),
        ]
        if s.selfTest {
            // Живой тест COPILOT-06: горячую клавишу ⌃⌥A не нашли — ответы не записались. Пункт виден в самопроверке.
            actions.insert(MenuItemSpec(.ownerAnswer, s.ownerAnswering ? L10n.t("Закончить мой ответ") : L10n.t("Сейчас отвечаю я"),
                                        symbol: s.ownerAnswering ? "stop.circle" : "mic", hotkey: s.hotkey(.ownerAnswer)), at: 1)
        }
        // COPILOT-09 R-02: без сессии приложение не слушает — первым пунктом меню идёт сессия.
        let session = s.sessionActive
            ? MenuItemSpec(.endSession, L10n.t("Завершить сессию") + (s.sessionTimer.map { " · \($0)" } ?? ""), symbol: "stop.circle")
            : MenuItemSpec(.newSession, L10n.t("Создать сессию…"), symbol: "play.circle", hotkey: s.hotkey(.newSession))
        return [
            [
                session,
                // Без разрешения — пункт без подменю: клик открывает окно разрешений (AC-13).
                MenuItemSpec(.listeningSource, listeningTitle, symbol: "circle.fill",
                             submenu: s.listening != .noPermission, statusDot: s.listening.dot),
                MenuItemSpec(.togglePause, paused ? L10n.t("Продолжить слушать") : L10n.t("Пауза"),
                             symbol: paused ? "play.fill" : "pause.fill", hotkey: s.hotkey(.togglePause)),
            ],
            [
                MenuItemSpec(.mode, L10n.f("Режим: %@", s.mode.title), symbol: "brain", submenu: true),
                MenuItemSpec(.models, L10n.f("Модели: %@", chainTitle), symbol: "cylinder", submenu: true),
                MenuItemSpec(.language, L10n.f("Язык звонка: %@", s.language.menuTitle), symbol: "globe", submenu: true),
            ],
            [
                MenuItemSpec(.profile, L10n.f("Профиль: %@", s.useProfile ? s.profileName : MenuLayout.noProfileTitle), symbol: "person", submenu: true),
                MenuItemSpec(.questionBank, s.bankError ?? L10n.f("База вопросов (%lld карточек)…", s.bankCardCount),
                             symbol: s.bankError == nil ? "book" : "exclamationmark.triangle"),
                // COPILOT-08 R-03: окно «Профиль» — резюме, факты, вакансия, инструкции, файлы.
                MenuItemSpec(.editProfile, L10n.t("Профиль: резюме, инструкции…"), symbol: "doc.text"),
                MenuItemSpec(.practice, L10n.t("Тестовый звонок…"), symbol: "phone"),
                MenuItemSpec(.aiInterview, L10n.t("ИИ-собеседование…"), symbol: "person.wave.2"),
            ],
            actions,
            [
                MenuItemSpec(.status, s.statusLine, symbol: "chart.bar", enabled: false),
            ],
            [
                MenuItemSpec(.settings, L10n.t("Настройки…"), symbol: "gearshape", shortcut: .command(",")),
                MenuItemSpec(.quit, L10n.t("Выйти"), symbol: "power", shortcut: .command("q")),
            ],
        ]
    }
}
