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
    case profile, questionBank, editProfile, practice
    case answerNow, screenshot, togglePanel, sessionHistory
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
    public var bankCardCount: Int
    public var strongModelName: String
    public var statusLine: String
    public var hotkeys: [HotkeyAction: HotkeyBinding]
    public var panelVisible: Bool

    public init(listening: ListeningStatus = .idle, mode: AnswerMode = .bankAndHint,
                chain: [ProviderID] = [.gemini, .deepseek, .anthropic], language: RecognitionLanguage = .auto,
                profileName: String = "Example", bankCardCount: Int = 0, strongModelName: String = "Claude",
                statusLine: String = "Today: $0.00 · Gemini: 0 req",
                hotkeys: [HotkeyAction: HotkeyBinding] = [:], panelVisible: Bool = false) {
        self.listening = listening
        self.mode = mode
        self.chain = chain
        self.language = language
        self.profileName = profileName
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
    /// Секции меню сверху вниз; между секциями — разделители. Состав и порядок — R-15.
    public static func sections(for s: MenuState) -> [[MenuItemSpec]] {
        let listeningTitle: String
        let paused: Bool
        switch s.listening {
        case .listening(let app): listeningTitle = "Listening — \(app)"; paused = false
        case .paused(let app): listeningTitle = "Paused — \(app)"; paused = true
        case .noPermission: listeningTitle = "No screen recording permission"; paused = false
        case .idle: listeningTitle = "Listening — choose source"; paused = false
        }
        let chainTitle = s.chain.map(\.displayName).joined(separator: " → ")
        return [
            [
                // Без разрешения — пункт без подменю: клик открывает окно разрешений (AC-13).
                MenuItemSpec(.listeningSource, listeningTitle, symbol: "circle.fill",
                             submenu: s.listening != .noPermission, statusDot: s.listening.dot),
                MenuItemSpec(.togglePause, paused ? "Resume listening" : "Pause listening",
                             symbol: paused ? "play.fill" : "pause.fill", hotkey: s.hotkey(.togglePause)),
            ],
            [
                MenuItemSpec(.mode, "Mode: \(s.mode.title)", symbol: "brain", submenu: true),
                MenuItemSpec(.models, "Models: \(chainTitle)", symbol: "cylinder", submenu: true),
                MenuItemSpec(.language, "Language: \(s.language.menuTitle)", symbol: "globe", submenu: true),
            ],
            [
                MenuItemSpec(.profile, "Profile: \(s.profileName)", symbol: "person", submenu: true),
                MenuItemSpec(.questionBank, "Question bank (\(s.bankCardCount) cards)…", symbol: "book"),
                MenuItemSpec(.editProfile, "Edit resume & stories…", symbol: "doc.text"),
                MenuItemSpec(.practice, "Practice mode…", symbol: "scope", enabled: false, badge: "soon"),
            ],
            [
                MenuItemSpec(.answerNow, "Answer now", symbol: "bolt", hotkey: s.hotkey(.answerNow)),
                MenuItemSpec(.screenshot, "Screenshot → \(s.strongModelName)", symbol: "camera", hotkey: s.hotkey(.screenshot)),
                MenuItemSpec(.togglePanel, s.panelVisible ? "Hide panel" : "Show panel", symbol: "macwindow",
                             hotkey: s.hotkey(.togglePanel)),
                MenuItemSpec(.sessionHistory, "Session history…", symbol: "clock"),
            ],
            [
                MenuItemSpec(.status, s.statusLine, symbol: "chart.bar", enabled: false),
            ],
            [
                MenuItemSpec(.settings, "Settings…", symbol: "gearshape", shortcut: .command(",")),
                MenuItemSpec(.quit, "Quit", symbol: "power", shortcut: .command("q")),
            ],
        ]
    }
}
