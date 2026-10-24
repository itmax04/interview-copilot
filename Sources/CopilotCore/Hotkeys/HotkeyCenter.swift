import Carbon.HIToolbox
import Foundation

/// Действия с глобальными горячими клавишами — R-17.
public enum HotkeyAction: String, Codable, CaseIterable, Sendable {
    case answerNow, screenshot, togglePanel, togglePause, strongModel
    /// Самопроверка «Микрофон Mac»: речь — ответ владельца, а не вопрос (COPILOT-06). Новые действия — только в конец:
    /// номер действия — его индекс в `allCases`.
    case ownerAnswer
    /// «Создать сессию…» (COPILOT-09 R-01).
    case newSession
    /// Оверлей (COPILOT-09 R-07, R-09, R-10): чат, очистить расшифровку, предыдущий / следующий ответ.
    case chat, clearTranscript, previousAnswer, nextAnswer

    public var title: String {
        switch self {
        case .answerNow: "Ответить сейчас"
        case .screenshot: "Скриншот → сильная модель"
        case .togglePanel: "Показать / скрыть панель"
        case .togglePause: "Пауза"
        case .strongModel: "Сильная модель"
        case .ownerAnswer: "Сейчас отвечаю я (самопроверка)"
        case .newSession: "Создать сессию"
        case .chat: "Чат: вопрос или уточнение"
        case .clearTranscript: "Очистить расшифровку"
        case .previousAnswer: "Предыдущий ответ"
        case .nextAnswer: "Следующий ответ"
        }
    }
}

/// Сочетание клавиш в терминах Carbon (`kVK_*`, `controlKey|optionKey|…`).
public struct HotkeyBinding: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let ctrlOpt = UInt32(controlKey | optionKey)

    /// По умолчанию ⌃⌥ (допущение A-3).
    public static let defaults: [HotkeyAction: HotkeyBinding] = [
        .answerNow: HotkeyBinding(keyCode: UInt32(kVK_Return), modifiers: ctrlOpt),
        .screenshot: HotkeyBinding(keyCode: UInt32(kVK_ANSI_S), modifiers: ctrlOpt),
        .togglePanel: HotkeyBinding(keyCode: UInt32(kVK_ANSI_H), modifiers: ctrlOpt),
        .togglePause: HotkeyBinding(keyCode: UInt32(kVK_ANSI_P), modifiers: ctrlOpt),
        .strongModel: HotkeyBinding(keyCode: UInt32(kVK_ANSI_C), modifiers: ctrlOpt),
        .ownerAnswer: HotkeyBinding(keyCode: UInt32(kVK_ANSI_A), modifiers: ctrlOpt),
        .newSession: HotkeyBinding(keyCode: UInt32(kVK_ANSI_N), modifiers: ctrlOpt),
        .chat: HotkeyBinding(keyCode: UInt32(kVK_Space), modifiers: ctrlOpt),
        .clearTranscript: HotkeyBinding(keyCode: UInt32(kVK_Delete), modifiers: ctrlOpt),
        .previousAnswer: HotkeyBinding(keyCode: UInt32(kVK_LeftArrow), modifiers: ctrlOpt),
        .nextAnswer: HotkeyBinding(keyCode: UInt32(kVK_RightArrow), modifiers: ctrlOpt),
    ]

    public static let cmd = UInt32(cmdKey)
    public static let cmdShift = UInt32(cmdKey | shiftKey)

    /// Схема ParakeetAI — только во время сессии (решение владельца Q10): вне сессии ⌘-сочетания не перехватываются.
    /// ⌃⌥-сочетания действуют всегда.
    public static let sessionDefaults: [HotkeyAction: HotkeyBinding] = [
        .answerNow: HotkeyBinding(keyCode: UInt32(kVK_Return), modifiers: cmd),
        .screenshot: HotkeyBinding(keyCode: UInt32(kVK_Return), modifiers: cmdShift),
        .chat: HotkeyBinding(keyCode: UInt32(kVK_Space), modifiers: cmdShift),
        .clearTranscript: HotkeyBinding(keyCode: UInt32(kVK_Delete), modifiers: cmdShift),
        .previousAnswer: HotkeyBinding(keyCode: UInt32(kVK_LeftArrow), modifiers: cmd),
        .nextAnswer: HotkeyBinding(keyCode: UInt32(kVK_RightArrow), modifiers: cmd),
    ]

    static let keyNames: [UInt32: String] = {
        var m: [UInt32: String] = [
            UInt32(kVK_Return): "↩", UInt32(kVK_Space): "Space", UInt32(kVK_Tab): "⇥", UInt32(kVK_Escape): "⎋",
            UInt32(kVK_Delete): "⌫", UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
            UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
        ]
        let letters: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"), (kVK_ANSI_E, "E"),
            (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"), (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"),
            (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"), (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"),
            (kVK_ANSI_P, "P"), (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
            (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"), (kVK_ANSI_Y, "Y"),
            (kVK_ANSI_Z, "Z"), (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"),
            (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"), (kVK_ANSI_8, "8"),
            (kVK_ANSI_9, "9"),
        ]
        for (code, name) in letters { m[UInt32(code)] = name }
        return m
    }()

    public var keyName: String { Self.keyNames[keyCode] ?? "#\(keyCode)" }

    /// Буква/символ для `NSMenuItem.keyEquivalent` (нижний регистр, «\r» для ↩), если есть.
    public var menuKeyEquivalent: String? {
        if keyCode == UInt32(kVK_Return) { return "\r" }
        guard let name = Self.keyNames[keyCode], name.count == 1, name.first!.isLetter || name.first!.isNumber else { return nil }
        return name.lowercased()
    }

    public var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + keyName
    }

    /// Без модификаторов глобальную клавишу назначать нельзя — сломает обычный ввод.
    public var isValidGlobal: Bool { modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 }
}

/// Регистрация глобальных горячих клавиш через Carbon `RegisterEventHotKey` (ADR-0001 п. 9, без сторонних пакетов).
/// Работает, когда активно любое приложение (AC-09); прав Accessibility не требует.
@MainActor
public final class HotkeyCenter {
    public private(set) var failures: [HotkeyAction: String] = [:]
    private var refs: [HotkeyAction: EventHotKeyRef] = [:]
    /// ⌘-сочетания сессии — отдельные регистрации (номера с `sessionBase`).
    private var sessionRefs: [HotkeyAction: EventHotKeyRef] = [:]
    static let sessionBase: UInt32 = 100
    private var handlerRef: EventHandlerRef?
    private let onPress: (HotkeyAction) -> Void
    private static let signature: OSType = 0x4943_4F50 // 'ICOP'

    public init(onPress: @escaping (HotkeyAction) -> Void) {
        self.onPress = onPress
        installHandler()
    }

    /// Перерегистрирует все сочетания; возвращает действия, которые зарегистрировать не удалось (занято).
    @discardableResult
    public func register(_ bindings: [HotkeyAction: HotkeyBinding]) -> [HotkeyAction: String] {
        unregisterAll()
        failures = [:]
        for action in HotkeyAction.allCases {
            guard let b = bindings[action] ?? HotkeyBinding.defaults[action] else { continue }
            guard b.isValidGlobal else {
                failures[action] = "нужен модификатор ⌃, ⌥ или ⌘"
                continue
            }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(HotkeyAction.allCases.firstIndex(of: action)! + 1))
            let status = RegisterEventHotKey(b.keyCode, b.modifiers, id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs[action] = ref
            } else {
                failures[action] = status == OSStatus(eventHotKeyExistsErr) ? "сочетание занято другим приложением" : "ошибка \(status)"
                Log.app.error("hotkey \(action.rawValue, privacy: .public) \(b.displayString, privacy: .public) failed: \(status)")
            }
        }
        return failures
    }

    public func unregisterAll() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
    }

    /// Включить ⌘-схему на время сессии; занятое другим приложением сочетание пропускается (⌃⌥ остаётся).
    @discardableResult
    public func registerSession(_ bindings: [HotkeyAction: HotkeyBinding] = HotkeyBinding.sessionDefaults) -> [HotkeyAction] {
        unregisterSession()
        var failed: [HotkeyAction] = []
        for (action, b) in bindings {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature,
                                   id: Self.sessionBase + UInt32(HotkeyAction.allCases.firstIndex(of: action)! + 1))
            if RegisterEventHotKey(b.keyCode, b.modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                sessionRefs[action] = ref
            } else {
                failed.append(action)
                Log.app.error("session hotkey \(action.rawValue, privacy: .public) \(b.displayString, privacy: .public) failed")
            }
        }
        return failed
    }

    public func unregisterSession() {
        for ref in sessionRefs.values { UnregisterEventHotKey(ref) }
        sessionRefs.removeAll()
    }

    public var sessionActive: Bool { !sessionRefs.isEmpty }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == HotkeyCenter.signature else { return OSStatus(eventNotHandledErr) }
            let index = Int(id.id > HotkeyCenter.sessionBase ? id.id - HotkeyCenter.sessionBase : id.id) - 1
            guard HotkeyAction.allCases.indices.contains(index) else { return OSStatus(eventNotHandledErr) }
            let action = HotkeyAction.allCases[index]
            let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { center.onPress(action) }
            return noErr
        }, 1, &spec, me, &handlerRef)
    }
}
