import AppKit
import CopilotCore
import SwiftUI

/// Окно настроек с вкладками R-18.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let model: AppModel
    private let hotkeyFailures: () -> [HotkeyAction: String]
    private let stylePreviewContext: () -> StylePreview.Context?

    init(model: AppModel, hotkeyFailures: @escaping () -> [HotkeyAction: String] = { [:] },
         stylePreviewContext: @escaping () -> StylePreview.Context? = { nil }) {
        self.model = model
        self.hotkeyFailures = hotkeyFailures
        self.stylePreviewContext = stylePreviewContext
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(model: model, hotkeyFailures: hotkeyFailures,
                                                                   stylePreviewContext: stylePreviewContext))
            let w = NSWindow(contentViewController: hosting)
            w.title = "Interview Copilot Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        model.refreshKeys()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case keys = "Keys"
    case models = "Models"
    case audio = "Audio"
    case bank = "Bank"
    case privacy = "Privacy"
    case panel = "Panel"
    case hotkeys = "Hotkeys"
    case budget = "Budget"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .keys: "key"
        case .models: "cylinder"
        case .audio: "waveform"
        case .bank: "book"
        case .privacy: "hand.raised"
        case .panel: "macwindow"
        case .hotkeys: "keyboard"
        case .budget: "dollarsign.circle"
        }
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    let hotkeyFailures: () -> [HotkeyAction: String]
    var stylePreviewContext: () -> StylePreview.Context? = { nil }

    var body: some View {
        TabView {
            KeysSettingsView(model: model).tabItem { Label(SettingsTab.keys.rawValue, systemImage: SettingsTab.keys.symbol) }
            ModelsSettingsView(model: model, stylePreviewContext: stylePreviewContext).tabItem { Label(SettingsTab.models.rawValue, systemImage: SettingsTab.models.symbol) }
            AudioSettingsView(model: model).tabItem { Label(SettingsTab.audio.rawValue, systemImage: SettingsTab.audio.symbol) }
            BankSettingsView(model: model).tabItem { Label(SettingsTab.bank.rawValue, systemImage: SettingsTab.bank.symbol) }
            PrivacySettingsView(model: model).tabItem { Label(SettingsTab.privacy.rawValue, systemImage: SettingsTab.privacy.symbol) }
            PanelSettingsView(model: model).tabItem { Label(SettingsTab.panel.rawValue, systemImage: SettingsTab.panel.symbol) }
            HotkeysSettingsView(model: model, failures: hotkeyFailures).tabItem { Label(SettingsTab.hotkeys.rawValue, systemImage: SettingsTab.hotkeys.symbol) }
            BudgetSettingsView(model: model).tabItem { Label(SettingsTab.budget.rawValue, systemImage: SettingsTab.budget.symbol) }
        }
        .padding(20)
        .frame(width: 600, height: 460)
    }
}
