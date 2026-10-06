import AppKit
import CopilotCore

/// Иконка в строке меню и меню по `docs/design/menu-v2.webp` — R-15.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let onAction: (MenuAction) -> Void
    /// Текущая настройка источника и запущенные приложения — для подменю «Listening» (R-01).
    var sourceMenuData: () -> (AudioSourceSetting, [RunningAppInfo]) = { (.auto, []) }
    var onSelectSource: (AudioSourceSetting) -> Void = { _ in }
    var state = MenuState() {
        didSet { rebuild() }
    }

    init(onAction: @escaping (MenuAction) -> Void) {
        self.onAction = onAction
        super.init()
        if let button = statusItem.button {
            button.image = ParrotIcon.menuBarTemplate()
            button.setAccessibilityLabel("Interview Copilot")
        }
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        rebuild()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()
        for (index, section) in MenuLayout.sections(for: state).enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for spec in section { menu.addItem(makeItem(spec)) }
        }
    }

    private func makeItem(_ spec: MenuItemSpec) -> NSMenuItem {
        let item = NSMenuItem(title: spec.title, action: #selector(itemSelected(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = spec.action.rawValue
        item.isEnabled = spec.enabled
        if let dot = spec.statusDot {
            item.image = Self.dotImage(dot)
        } else {
            let image = NSImage(systemSymbolName: spec.symbol, accessibilityDescription: nil)
            image?.isTemplate = true
            item.image = image
        }
        if let hotkey = spec.hotkey, let key = hotkey.menuKeyEquivalent {
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = Self.cocoaModifiers(hotkey.modifiers)
        } else if let shortcut = spec.shortcut {
            switch shortcut.key {
            case .character(let c): item.keyEquivalent = String(c)
            case .returnKey: item.keyEquivalent = "\r"
            }
            item.keyEquivalentModifierMask = shortcut.controlOption ? [.control, .option] : [.command]
        }
        if let badge = spec.badge {
            item.badge = NSMenuItemBadge(string: badge)
        }
        if spec.hasSubmenu {
            item.submenu = submenu(for: spec.action)
        }
        return item
    }

    /// Подменю; пункты подключаются к настройкам на P-08.
    private func submenu(for action: MenuAction) -> NSMenu {
        let sub = NSMenu()
        func add(_ title: String, checked: Bool = false) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.state = checked ? .on : .off
            sub.addItem(item)
        }
        switch action {
        case .listeningSource:
            let (setting, running) = sourceMenuData()
            sub.addItem(sourceItem("Auto (Zoom → Chrome → Telegram)", .auto, checked: setting == .auto))
            if !running.isEmpty { sub.addItem(.separator()) }
            var shown = Set<String>()
            for app in running.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
            where shown.insert(app.bundleID).inserted {
                let value = AudioSourceSetting.app(bundleID: app.bundleID, name: app.name)
                let checked: Bool = if case .app(let id, _) = setting { id == app.bundleID } else { false }
                sub.addItem(sourceItem(app.name, value, checked: checked))
            }
            sub.addItem(.separator())
            sub.addItem(sourceItem("All system audio", .allSystem, checked: setting == .allSystem))
        case .mode:
            for mode in AnswerMode.allCases { add(mode.title, checked: mode == state.mode) }
        case .models:
            add(state.chain.map(\.displayName).joined(separator: " → "), checked: true)
        case .language:
            for lang in RecognitionLanguage.allCases { add(lang.menuTitle, checked: lang == state.language) }
        case .profile:
            add(state.profileName, checked: true)
            sub.addItem(.separator())
            add("Open profile folder")
        default:
            break
        }
        return sub
    }

    private final class SourceBox: NSObject {
        let value: AudioSourceSetting
        init(_ value: AudioSourceSetting) { self.value = value }
    }

    private func sourceItem(_ title: String, _ value: AudioSourceSetting, checked: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(sourceSelected(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = SourceBox(value)
        item.state = checked ? .on : .off
        return item
    }

    @objc private func sourceSelected(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? SourceBox else { return }
        onSelectSource(box.value)
    }

    @objc private func itemSelected(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = MenuAction(rawValue: raw) else { return }
        onAction(action)
    }

    static func cocoaModifiers(_ carbon: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbon & 0x1000 != 0 { flags.insert(.control) }  // controlKey
        if carbon & 0x0800 != 0 { flags.insert(.option) }   // optionKey
        if carbon & 0x0200 != 0 { flags.insert(.shift) }    // shiftKey
        if carbon & 0x0100 != 0 { flags.insert(.command) }  // cmdKey
        return flags
    }

    private static func dotImage(_ dot: StatusDot) -> NSImage {
        let color: NSColor = switch dot {
        case .green: .systemGreen
        case .gray: .systemGray
        case .red: .systemRed
        }
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
