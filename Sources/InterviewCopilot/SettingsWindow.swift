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
                                                                   stylePreviewContext: stylePreviewContext).localizedRoot())
            let w = NSWindow(contentViewController: hosting)
            UILanguage.shared.setTitle("Настройки Interview Copilot", of: w)
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
    case general = "General"
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
        case .general: "gearshape"
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
    /// P17: названия разделов по-русски.
    var title: String {
        switch self {
        case .general: "Основное"
        case .keys: "Ключи моделей"
        case .models: "Модели и ответы"
        case .audio: "Звук и распознавание"
        case .bank: "База вопросов"
        case .privacy: "Приватность"
        case .panel: "Оверлей"
        case .hotkeys: "Горячие клавиши"
        case .budget: "Бюджет"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Тема оформления и язык интерфейса — меняются сразу."
        case .keys: "Для старта достаточно одного бесплатного ключа Groq. Можно добавить еще ключи: кончился лимит у одного — ответ идет со следующего."
        case .models: "Порядок моделей, запасные, стиль ответа по умолчанию и таймауты."
        case .audio: "Источник звука, язык, распознавание, фильтры речи и ваш голос."
        case .bank: "Порог совпадения с вашими ответами и модель поиска."
        case .privacy: "Фильтр личных данных и срок хранения истории на этом Mac."
        case .panel: "Прозрачность, размер текста и ширина оверлея."
        case .hotkeys: "⌃⌥ работают всегда; ⌘-клавиши — только во время сессии."
        case .budget: "Расход платных моделей и лимит на месяц."
        }
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    let hotkeyFailures: () -> [HotkeyAction: String]
    var stylePreviewContext: () -> StylePreview.Context? = { nil }
    @State private var tab: SettingsTab

    init(model: AppModel, hotkeyFailures: @escaping () -> [HotkeyAction: String],
         stylePreviewContext: @escaping () -> StylePreview.Context? = { nil }, tab: SettingsTab? = nil) {
        self.model = model
        self.hotkeyFailures = hotkeyFailures
        self.stylePreviewContext = stylePreviewContext
        _tab = State(initialValue: tab ?? Self.lastTab)
    }

    /// Последний открытый раздел: окно перестраивается при смене языка, раздел остается тем же.
    @MainActor static var lastTab: SettingsTab = .general

    /// P17: слева разделы, справа страница с заголовком; содержимое страниц — прежние формы настроек.
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(SettingsTab.allCases) { t in
                    ICSidebarRow(title: t.title, icon: t.symbol, selected: tab == t) { tab = t; Self.lastTab = t }
                }
                Spacer()
            }
            .padding(14)
            .frame(width: 262)
            .background(IC.sidebar.opacity(0.6))
            Rectangle().fill(IC.line).frame(width: 1)
            VStack(alignment: .leading, spacing: 8) {
                Text(tab.title).font(.system(size: 26, weight: .bold)).padding(.horizontal, 28).padding(.top, 24)
                Text(tab.subtitle).font(.system(size: 13)).foregroundStyle(IC.secondary).padding(.horizontal, 28)
                page.padding(.horizontal, 12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(IC.background)
            }

    @ViewBuilder private var page: some View {
        switch tab {
        case .general: GeneralSettingsView(model: model)
        case .keys: KeysSettingsView(model: model)
        case .models: ModelsSettingsView(model: model, stylePreviewContext: stylePreviewContext)
        case .audio: AudioSettingsView(model: model)
        case .bank: BankSettingsView(model: model)
        case .privacy: PrivacySettingsView(model: model)
        case .panel: PanelSettingsView(model: model)
        case .hotkeys: HotkeysSettingsView(model: model, failures: hotkeyFailures)
        case .budget: BudgetSettingsView(model: model)
        }
    }
}
