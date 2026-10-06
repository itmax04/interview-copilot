import AppKit
import SwiftUI

/// Окно настроек с вкладками R-18. Содержимое вкладок — P-02.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let w = NSWindow(contentViewController: hosting)
            w.title = "Interview Copilot Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 560, height: 420))
            w.center()
            window = w
        }
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
    var body: some View {
        TabView {
            ForEach(SettingsTab.allCases) { tab in
                Text(tab.rawValue)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tabItem { Label(tab.rawValue, systemImage: tab.symbol) }
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 420)
    }
}
