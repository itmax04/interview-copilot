import AppKit
import CopilotCore

/// Иконка в строке меню и меню по `docs/design/menu-v2.webp` — R-15.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let onAction: (MenuAction) -> Void
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
        if let shortcut = spec.shortcut {
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
            add("Auto", checked: true)
            sub.addItem(.separator())
            add("All system audio")
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

    @objc private func itemSelected(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = MenuAction(rawValue: raw) else { return }
        onAction(action)
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
