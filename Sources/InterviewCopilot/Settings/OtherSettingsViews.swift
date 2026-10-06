import CopilotCore
import SwiftUI

/// Models — ID моделей, порядок цепочки, таймаут первого токена (R-09, R-18).
struct ModelsSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("ID моделей") {
                TextField("Gemini", text: $model.settings.modelIDs.gemini)
                TextField("DeepSeek", text: $model.settings.modelIDs.deepseek)
                TextField("Anthropic", text: $model.settings.modelIDs.anthropic)
            }
            Section("Цепочка автоперехода") {
                ForEach(Array(model.settings.chain.enumerated()), id: \.element) { index, provider in
                    HStack {
                        Text("\(index + 1). \(provider.displayName)")
                        Spacer()
                        Button { move(index, by: -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless)
                            .disabled(index == 0)
                            .accessibilityLabel("Выше")
                        Button { move(index, by: 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless)
                            .disabled(index == model.settings.chain.count - 1)
                            .accessibilityLabel("Ниже")
                    }
                }
                Picker("Сильная модель (⌃⌥C, скриншот)", selection: $model.settings.strongProvider) {
                    ForEach(ProviderID.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            Section {
                Stepper(value: $model.settings.firstTokenTimeout, in: AppSettings.firstTokenTimeoutRange, step: 0.5) {
                    Text("Таймаут первого токена: \(model.settings.firstTokenTimeout, specifier: "%.1f") с")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func move(_ index: Int, by delta: Int) {
        var chain = model.settings.chain
        let target = index + delta
        guard chain.indices.contains(target) else { return }
        chain.swapAt(index, target)
        model.settings.chain = chain
    }
}

/// Audio — источник, язык, порог паузы T (R-01, R-03, R-05).
struct AudioSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Picker("Источник звука", selection: sourceBinding) {
                Text("Auto (Zoom → Chrome → Telegram)").tag(0)
                Text("Весь системный звук").tag(1)
                if case .app(_, let name) = model.settings.audioSource { Text(name).tag(2) }
            }
            Picker("Язык", selection: $model.settings.language) {
                ForEach(RecognitionLanguage.allCases, id: \.self) { Text($0.menuTitle).tag($0) }
            }
            VStack(alignment: .leading) {
                Text("Пауза конца вопроса T: \(model.settings.pauseThresholdMs) мс")
                Slider(value: pauseBinding, in: Double(AppSettings.pauseThresholdRange.lowerBound)...Double(AppSettings.pauseThresholdRange.upperBound), step: 50)
            }
        }
        .formStyle(.grouped)
    }

    private var sourceBinding: Binding<Int> {
        Binding {
            switch model.settings.audioSource {
            case .auto: 0
            case .allSystem: 1
            case .app: 2
            }
        } set: { tag in
            switch tag {
            case 0: model.settings.audioSource = .auto
            case 1: model.settings.audioSource = .allSystem
            default: break
            }
        }
    }

    private var pauseBinding: Binding<Double> {
        Binding { Double(model.settings.pauseThresholdMs) } set: { model.settings.pauseThresholdMs = Int($0) }
    }
}

/// Bank — порог совпадения (R-07).
struct BankSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            VStack(alignment: .leading) {
                Text("Порог совпадения с карточкой: \(Int((model.settings.bankThreshold * 100).rounded()))%")
                Slider(value: $model.settings.bankThreshold, in: AppSettings.bankThresholdRange, step: 0.01)
            }
            Text("Ниже порога показывается «Нет в базе» и три ближайшие карточки.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

/// Privacy — фильтр личных данных и срок хранения истории (R-12, R-19).
struct PrivacySettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Toggle("Удалять email, телефоны и ссылки из профиля перед отправкой в модель", isOn: $model.settings.piiFilterEnabled)
            Stepper(value: $model.settings.historyRetentionDays, in: AppSettings.retentionRange) {
                Text("Хранить историю сессий: \(model.settings.historyRetentionDays) дн.")
            }
        }
        .formStyle(.grouped)
    }
}

/// Panel — непрозрачность, шрифт, ширина (R-16).
struct PanelSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            VStack(alignment: .leading) {
                Text("Непрозрачность: \(Int((model.settings.panelOpacity * 100).rounded()))%")
                Slider(value: $model.settings.panelOpacity, in: AppSettings.panelOpacityRange, step: 0.01)
            }
            Picker("Размер шрифта", selection: $model.settings.panelFontSize) {
                ForEach(PanelFontSize.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading) {
                Text("Ширина панели: \(Int(model.settings.panelWidth)) pt")
                Slider(value: $model.settings.panelWidth, in: AppSettings.panelWidthRange, step: 10)
            }
        }
        .formStyle(.grouped)
    }
}

/// Hotkeys — R-17. Регистрация и переназначение подключаются на P-05.
struct HotkeysSettingsView: View {
    private let rows: [(String, String)] = [
        ("Ответить сейчас", "⌃⌥↩"),
        ("Скриншот → сильная модель", "⌃⌥S"),
        ("Показать / скрыть панель", "⌃⌥H"),
        ("Пауза", "⌃⌥P"),
        ("Сильная модель", "⌃⌥C"),
    ]

    var body: some View {
        Form {
            ForEach(rows, id: \.0) { row in
                LabeledContent(row.0) { Text(row.1).monospaced() }
            }
        }
        .formStyle(.grouped)
    }
}

/// Budget — месячный лимит на платных провайдеров (R-18, R-20).
struct BudgetSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            LabeledContent("Месячный лимит, $") {
                TextField("", value: $model.settings.monthlyBudgetUSD, format: .number.precision(.fractionLength(2)))
                    .frame(width: 90)
                    .multilineTextAlignment(.trailing)
            }
            if model.settings.paidProvidersSuspended {
                HStack {
                    Text("Лимит достигнут: платные провайдеры выключены.")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Включить снова") { model.settings.paidProvidersSuspended = false }
                }
            }
            Text("Gemini Free продолжает работать после достижения лимита.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
