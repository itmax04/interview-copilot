import CopilotCore
import SwiftUI

/// Models — ID моделей, порядок цепочки, таймаут первого токена (R-09, R-18).
struct ModelsSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                ForEach(ProviderID.allCases, id: \.self) { p in
                    if let warning = model.modelWarning(p) {
                        Label(warning, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                    }
                }
            }
            Section("ID моделей") {
                TextField("Gemini", text: $model.settings.modelIDs.gemini)
                TextField("Gemini (запасная)", text: $model.settings.modelIDs.geminiBackup)
                TextField("DeepSeek", text: $model.settings.modelIDs.deepseek)
                TextField("Anthropic", text: $model.settings.modelIDs.anthropic)
                TextField("Groq", text: $model.settings.modelIDs.groq)
                TextField("Cerebras", text: $model.settings.modelIDs.cerebras)
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
                Stepper(value: $model.settings.hedgeAfter, in: AppSettings.hedgeAfterRange, step: 0.5) {
                    Text(model.settings.hedgeAfter > 0
                         ? "Параллельный запрос через: \(model.settings.hedgeAfter, specifier: "%.1f") с"
                         : "Параллельный запрос: выключен")
                }
                Text("Если модель молчит это время, тот же запрос сразу уходит следующей в цепочке; показывается ответ той, что ответила первой. 0 — строго по очереди.")
                    .font(.footnote).foregroundStyle(.secondary)
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
                Text("Микрофон Mac (самопроверка, без созвона)").tag(3)
                if case .app(_, let name) = model.settings.audioSource { Text(name).tag(2) }
            }
            Picker("Язык", selection: $model.settings.language) {
                ForEach(RecognitionLanguage.allCases, id: \.self) { Text($0.menuTitle).tag($0) }
            }
            Text("Для Whisper выбор известного языка помогает распознаванию. Для Parakeet язык задаёт метку расшифровки, текст остаётся мультиязычным.")
                .font(.footnote).foregroundStyle(.secondary)
            Picker("Движок распознавания", selection: $model.settings.recognitionBackend) {
                Text("Parakeet v3 — локально").tag(RecognitionBackend.parakeet)
                Text("Whisper — локально").tag(RecognitionBackend.whisper)
            }
            if model.settings.recognitionBackend == .whisper {
                Picker("Модель распознавания", selection: $model.settings.whisperModel) {
                    Text("Whisper large-v3-turbo").tag("ggml-large-v3-turbo-q5_0.bin")
                    Text("Whisper medium").tag("ggml-medium-q5_0.bin")
                    Text("Whisper small").tag("ggml-small-q5_1.bin")
                    if !["ggml-large-v3-turbo-q5_0.bin", "ggml-medium-q5_0.bin", "ggml-small-q5_1.bin"].contains(model.settings.whisperModel) {
                        Text(model.settings.whisperModel).tag(model.settings.whisperModel)
                    }
                }
                Toggle("Точный итоговый текст", isOn: $model.settings.recognitionAccuracy)
                Text("Итог распознаётся с полным контекстом. Предварительный текст появляется раньше; итог может занять больше времени.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Распознаёт русский, украинский и английский без отдельного определения языка. Аудио обрабатывается на Mac.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("Украинский итог — через Whisper turbo", isOn: $model.settings.ukrainianWhisperFinal)
                Toggle("Уточнять через Whisper и русский/английский (термины, имена)", isOn: $model.settings.whisperReviseAllLanguages)
                Text("Подсказка запускается сразу по быстрому тексту Parakeet. Через 2–3 с строку в расшифровке заменяет текст Whisper large-v3-turbo с закреплённым языком: украинский не сползает в русский, термины пишутся правильно. Нужен файл модели turbo; если Mac тормозит на созвоне — выключите второй переключатель.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Toggle("Подсказывать распознаванию формулировки из базы вопросов", isOn: $model.settings.recognitionPromptFromBank)
                .disabled(model.settings.recognitionBackend == .parakeet)
            Text("Для Whisper, экспериментально: на сжатом звуке помогает одним фразам и мешает другим.")
                .font(.footnote).foregroundStyle(.secondary)
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
            case .microphone: 3
            }
        } set: { tag in
            switch tag {
            case 0: model.settings.audioSource = .auto
            case 1: model.settings.audioSource = .allSystem
            case 3: model.settings.audioSource = .microphone
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

/// Hotkeys — R-17: глобальные сочетания, переназначение, предупреждение, если сочетание занято.
struct HotkeysSettingsView: View {
    @Bindable var model: AppModel
    let failures: () -> [HotkeyAction: String]
    @State private var recording: HotkeyAction?
    @State private var monitor: Any?
    @State private var problems: [HotkeyAction: String] = [:]

    var body: some View {
        Form {
            ForEach(HotkeyAction.allCases, id: \.self) { action in
                VStack(alignment: .leading, spacing: 2) {
                    LabeledContent(action.title) {
                        HStack {
                            Text(recording == action ? "Нажмите сочетание…" : model.settings.hotkey(action).displayString)
                                .monospaced()
                                .foregroundStyle(recording == action ? .orange : .primary)
                            Button(recording == action ? "Отмена" : "Изменить") { toggleRecording(action) }
                        }
                    }
                    if let problem = problems[action] {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Сбросить на ⌃⌥") { model.settings.hotkeys = [:]; refresh() }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .onDisappear(perform: stopRecording)
    }

    private func refresh() {
        // Регистрация происходит после сохранения настроек; даём ей завершиться.
        DispatchQueue.main.async { problems = failures() }
    }

    private func toggleRecording(_ action: HotkeyAction) {
        if recording == action {
            stopRecording()
            return
        }
        stopRecording()
        recording = action
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc — отмена
                stopRecording()
                return nil
            }
            var mods: UInt32 = 0
            if event.modifierFlags.contains(.control) { mods |= 0x1000 }
            if event.modifierFlags.contains(.option) { mods |= 0x0800 }
            if event.modifierFlags.contains(.shift) { mods |= 0x0200 }
            if event.modifierFlags.contains(.command) { mods |= 0x0100 }
            let binding = HotkeyBinding(keyCode: UInt32(event.keyCode), modifiers: mods)
            if binding.isValidGlobal {
                model.settings.hotkeys[action] = binding
                stopRecording()
                refresh()
            } else {
                problems[action] = "Нужен модификатор ⌃, ⌥ или ⌘"
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
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
