import AppKit
import CopilotCore
import Observation
import SwiftUI

/// Мастер «Создать сессию» — COPILOT-09 R-01, R-03, R-04: «Детали» → «Настройки» → «Проверка» → Start.
@MainActor
final class SessionWizardController {
    private var window: NSWindow?
    private let model: AppModel
    private let bank: BankController
    private let listening: ListeningController
    private let onStart: (SessionConfig) -> Void
    private var state: SessionWizardModel?

    init(model: AppModel, bank: BankController, listening: ListeningController, onStart: @escaping (SessionConfig) -> Void) {
        self.model = model
        self.bank = bank
        self.listening = listening
        self.onStart = onStart
    }

    /// Последние настройки (без компании, вакансии и указаний — R-01) с действующим профилем.
    func defaultConfig() -> SessionConfig {
        var c = model.settings.lastSessionConfig ?? {
            var fresh = SessionConfig()
            fresh.language = model.settings.language
            return fresh
        }()
        if c.profileID == nil || !bank.profiles.contains(where: { $0.id == c.profileID }) { c.profileID = bank.activeID }
        if let p = c.firstProvider, model.hasKey[p] != true { c.firstProvider = nil }
        return c
    }

    func show() {
        let state = SessionWizardModel(config: defaultConfig(), model: model, bank: bank, listening: listening)
        state.onStart = { [weak self] config in
            self?.window?.close()
            self?.onStart(config)
        }
        state.onCancel = { [weak self] in self?.window?.close() }
        self.state = state
        let hosting = NSHostingController(rootView: SessionWizardView(state: state))
        if let window {
            window.contentViewController = hosting
        } else {
            let w = NSWindow(contentViewController: hosting)
            w.title = "Создать сессию"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            window = w
        }
        window?.setContentSize(NSSize(width: 820, height: 600))
        window?.center()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
@Observable
final class SessionWizardModel {
    enum Step: Int, CaseIterable {
        case details, settings, check
        var title: String {
            switch self {
            case .details: "Детали"
            case .settings: "Настройки"
            case .check: "Проверка"
            }
        }
    }

    var step: Step = .details
    var config: SessionConfig
    var jobLink = ""
    private(set) var importing = false
    private(set) var importMessage: String?
    private(set) var importFailed = false
    /// Результат проверки (запись — и из режима снимков `--ui-snapshots`, без захвата звука).
    var preflight: [PreflightItem] = []
    private(set) var checking = false

    let model: AppModel
    let bank: BankController
    let listening: ListeningController
    var onStart: (SessionConfig) -> Void = { _ in }
    var onCancel: () -> Void = {}

    init(config: SessionConfig, model: AppModel, bank: BankController, listening: ListeningController) {
        self.config = config
        self.model = model
        self.bank = bank
        self.listening = listening
    }

    var errors: [String] {
        config.validationErrors(profileExists: config.profileID.map { id in bank.profiles.contains { $0.id == id } } ?? false)
    }

    /// Редактор стиля ответа (R-12) открыт — предпросмотр живёт, пока открыт лист.
    var stylePreview: StylePreview?

    /// Стиль сессии: свой («Сохранить») или по умолчанию из настроек.
    var effectiveStyle: AnswerStyle { config.effectiveStyle(default: model.settings.answerStyle) }

    func openStyleEditor() {
        var settings = model.settings
        settings.chain = config.chain(from: settings.chain)
        var profile: Profile?
        if let id = config.profileID, bank.profiles.contains(where: { $0.id == id }) {
            let p = bank.library.load(id)
            switch config.type {
            case .regular: profile = Profile(name: p.name, instructions: p.instructions)
            case .interview, .mock:
                if settings.useProfile { profile = config.applyingJob(to: p) }
            }
        }
        let context = StylePreview.Context(settings: settings, secrets: model.secrets, profile: profile,
                                           generalInstructions: bank.generalInstructions, sessionType: config.type == .regular ? .regular : .interview,
                                           sessionInstructions: config.instructions, language: config.language.whisperCode ?? "uk")
        stylePreview = StylePreview(style: effectiveStyle, context: context)
    }

    /// «Сохранить для сессии» — только этот звонок; «По умолчанию» — настройки и этот звонок.
    func saveStyle(_ style: AnswerStyle, asDefault: Bool) {
        if asDefault {
            model.settings.answerStyle = style
            config.style = nil
        } else {
            config.style = style == model.settings.answerStyle ? nil : style
        }
        stylePreview = nil
    }

    /// Модели с ключами в порядке цепочки — для выбора первой.
    var providersWithKeys: [ProviderID] { model.settings.chain.filter { model.hasKey[$0] == true } }

    func next() {
        guard errors.isEmpty || step != .details else { return }
        if let n = Step(rawValue: step.rawValue + 1) {
            step = n
            if n == .check { runPreflight() }
        }
    }

    func back() { if let p = Step(rawValue: step.rawValue - 1) { step = p } }

    func start() { onStart(config) }

    // MARK: Импорт вакансии (R-04)

    func importJob() {
        guard !importing else { return }
        guard let url = JobImport.validatedURL(jobLink) else { failImport(JobImportError.badURL.description); return }
        importing = true
        importMessage = "Загружаю страницу…"
        importFailed = false
        let settings = model.settings, secrets = model.secrets
        Task {
            defer { importing = false }
            let page: String
            do { page = JobImport.text(fromHTML: try await JobImport.fetch(url)) } catch {
                failImport((error as? JobImportError)?.description ?? error.localizedDescription)
                return
            }
            guard !JobImport.looksLikeLoginWall(page) else { failImport(JobImportError.loginWall.description); return }
            importMessage = "Модель выделяет вакансию…"
            let chain = await Task.detached { ChainFactory.chain(settings: settings, secrets: secrets, providers: ChainFactory.providers()) }.value
            switch await ChainText.collect(chain, JobImport.request(pageText: page, url: url)) {
            case .success(let reply):
                guard let info = JobImport.parse(reply) else { failImport(JobImportError.notFound.description); return }
                if !info.company.isEmpty { config.company = info.company }
                config.jobDescription = (info.title.isEmpty ? "" : info.title + "\n\n") + info.description
                importMessage = "Вакансия загружена — проверьте и поправьте текст"
                Log.app.info("job import ok chars=\(info.description.count)")
            case .failure(let e):
                failImport(e.description)
            }
        }
    }

    private func failImport(_ message: String) {
        importMessage = message
        importFailed = true
    }

    // MARK: Проверка перед стартом (R-03)

    /// «Распознавание: Parakeet v3» → «Parakeet v3»: заголовок строки уже говорит «Распознавание».
    static func sttDetail(_ status: String) -> String {
        status.hasPrefix("Распознавание: ") ? String(status.dropFirst("Распознавание: ".count)) : status
    }

    /// Источник звука звонка — та же настройка, что в меню Listening (R-03: «Выбрать источник»).
    var sourceTag: String {
        get {
            switch model.settings.audioSource {
            case .auto: "auto"
            case .allSystem: "all"
            case .microphone: "mic"
            case .app(let id, _): "app:" + id
            }
        }
        set {
            switch newValue {
            case "auto": model.settings.audioSource = .auto
            case "all": model.settings.audioSource = .allSystem
            case "mic": model.settings.audioSource = .microphone
            default:
                let id = String(newValue.dropFirst(4))
                let name = ListeningController.runningApps().first { $0.bundleID == id }?.name ?? id
                model.settings.audioSource = .app(bundleID: id, name: name)
            }
        }
    }

    func runPreflight() {
        checking = true
        var input = PreflightInput()
        let settings = model.settings
        input.sessionType = config.type
        input.microphoneSource = settings.audioSource == .microphone || config.type == .mock
        input.micPermission = Permissions.microphone == .granted
        input.screenPermission = Permissions.screenCaptureGranted
        input.recognizerReady = listening.recognizerLoaded
        input.recognizerStatus = Self.sttDetail(listening.sttStatus)
        input.providersWithKeys = config.chain(from: settings.chain).filter { model.hasKey[$0] == true }
        if let id = config.profileID {
            input.resumeCharacters = bank.library.read(.resume, of: id).trimmingCharacters(in: .whitespacesAndNewlines).count
            input.materials = bank.library.listMaterials(id).count
            let cards = (try? QuestionBankParser.load(bank.library.questionsURL(id))) ?? []
            input.questions = cards.count
            input.preparedQuestions = cards.filter(\.prepared).count
        }
        preflight = Preflight.evaluate(input)
        let microphoneOnly = input.microphoneSource
        Task {
            async let mic = listening.probeMicrophone()
            async let call = microphoneOnly ? (nil as String?, nil as Float?) : listening.probeCall()
            let (micPeak, callResult) = await (mic, call)
            input.micPeakDB = input.micPermission ? (micPeak ?? -120) : nil
            input.callSourceName = callResult.0
            input.callPeakDB = callResult.0 == nil ? nil : (callResult.1 ?? -120)
            input.recognizerReady = listening.recognizerLoaded
            input.recognizerStatus = Self.sttDetail(listening.sttStatus)
            preflight = Preflight.evaluate(input)
            checking = false
            Log.app.info("preflight ok=\(Preflight.canStart(self.preflight)) items=\(self.preflight.map { "\($0.id):\($0.status)" }.joined(separator: ","), privacy: .public)")
        }
    }
}

struct SessionWizardView: View {
    @Bindable var state: SessionWizardModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                ScrollView {
                    Group {
                        switch state.step {
                        case .details: details
                        case .settings: settings
                        case .check: check
                        }
                    }
                    .padding(.trailing, 4)
                }
                footer
            }
            .padding(24)
        }
        .frame(width: 820, height: 600)
        .tint(Theme.accent)
        .sheet(isPresented: Binding(get: { state.stylePreview != nil }, set: { if !$0 { state.stylePreview = nil } })) {
            if let preview = state.stylePreview {
                AnswerStyleEditor(preview: preview,
                                  onSave: { state.saveStyle($0, asDefault: false) },
                                  onSaveDefault: { state.saveStyle($0, asDefault: true) },
                                  onCancel: { state.stylePreview = nil })
            }
        }
    }

    // MARK: Колонка шагов

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Создать сессию").font(.title2.bold())
                Text("Детали и настройки звонка").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                ForEach(SessionWizardModel.Step.allCases, id: \.self) { s in
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(s.rawValue <= state.step.rawValue ? Theme.accent : Color.secondary.opacity(0.2))
                                .frame(width: 24, height: 24)
                            Text(s.rawValue < state.step.rawValue ? "✓" : "\(s.rawValue + 1)")
                                .font(.caption.bold()).foregroundStyle(.white)
                        }
                        Text(s.title).fontWeight(s == state.step ? .semibold : .regular)
                            .foregroundStyle(s == state.step ? .primary : .secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Шаг \(s.rawValue + 1): \(s.title)\(s == state.step ? ", текущий" : "")")
                }
            }
            Spacer()
            Text("Без сессии приложение не слушает звонок и микрофон.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 230, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: Шаг 1 — Детали

    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Тип", selection: $state.config.type) {
                ForEach(SessionType.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(typeHint).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            ThemeCard {
                Picker("Профиль", selection: Binding(get: { state.config.profileID ?? "" }, set: { state.config.profileID = $0 })) {
                    ForEach(state.bank.profiles) { Text($0.name).tag($0.id) }
                }
                if state.config.type == .regular {
                    Text("Из профиля берутся инструкции и материалы; резюме и вопросы — нет.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            if state.config.type == .interview {
                ThemeCard {
                    Text("Ссылка на вакансию").font(.callout).foregroundStyle(.secondary)
                    HStack {
                        TextField("https://…", text: $state.jobLink)
                            .onSubmit { state.importJob() }
                        Button(state.importing ? "Загружаю…" : "Загрузить") { state.importJob() }
                            .disabled(state.importing || state.jobLink.isEmpty)
                    }
                    if let message = state.importMessage {
                        Label(message, systemImage: state.importFailed ? "exclamationmark.triangle.fill" : (state.importing ? "hourglass" : "checkmark.circle.fill"))
                            .font(.callout).foregroundStyle(state.importFailed ? Theme.warn : .secondary)
                    }
                    Text("Компания").font(.callout).foregroundStyle(.secondary)
                    TextField("Например, ФинБанк", text: $state.config.company)
                    Text("Описание вакансии").font(.callout).foregroundStyle(.secondary)
                    TextEditor(text: $state.config.jobDescription)
                        .frame(minHeight: 140)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                        .accessibilityLabel("Описание вакансии")
                    Text("Пусто — берётся вакансия из профиля.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            ForEach(state.errors, id: \.self) { e in
                Label(e, systemImage: "exclamationmark.circle").foregroundStyle(Theme.warn)
            }
        }
    }

    private var typeHint: String {
        switch state.config.type {
        case .interview: "Собеседование: ответы от вашего лица по резюме, фактам, вакансии, материалам и вопросам профиля."
        case .regular: "Обычный звонок: что сказать по теме разговора, вашим инструкциям и материалам. После звонка — сводка и договорённости."
        case .mock: "ИИ-собеседование: модель задаёт вопросы голосом, вы отвечаете в микрофон, подсказки — как на звонке."
        }
    }

    // MARK: Шаг 2 — Настройки

    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            ThemeCard {
                if state.config.type != .mock {
                    Picker("Источник звука", selection: $state.sourceTag) {
                        Text("Авто (Zoom → Chrome → Telegram)").tag("auto")
                        ForEach(ListeningController.runningApps().sorted { $0.name < $1.name }, id: \.bundleID) { app in
                            Text(app.name).tag("app:" + app.bundleID)
                        }
                        if case .app(let id, let name) = state.model.settings.audioSource,
                           !ListeningController.runningApps().contains(where: { $0.bundleID == id }) {
                            Text("\(name) (не запущено)").tag("app:" + id)
                        }
                        Text("Весь системный звук").tag("all")
                        Text("Микрофон Mac (самопроверка)").tag("mic")
                    }
                }
                Picker("Язык звонка", selection: $state.config.language) {
                    ForEach(RecognitionLanguage.allCases, id: \.self) { Text($0.menuTitle).tag($0) }
                }
                Picker("Модель", selection: $state.config.firstProvider) {
                    Text("По порядку цепочки (\(state.providersWithKeys.first?.displayName ?? "нет ключей"))").tag(ProviderID?.none)
                    ForEach(state.providersWithKeys, id: \.self) { Text($0.displayName).tag(ProviderID?.some($0)) }
                }
                Text("Выбранная модель — первой, остальные из цепочки — запасными.").font(.footnote).foregroundStyle(.secondary)
            }
            if state.config.type != .mock {
                ThemeCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Стиль ответа").font(.headline)
                            Text(state.effectiveStyle.summary).foregroundStyle(.secondary)
                            Text(state.config.style == nil ? "По умолчанию — меняется в Settings → Models" : "Только для этой сессии")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Настроить…") { state.openStyleEditor() }
                    }
                }
            }
            ThemeCard {
                Text("Указания на эту сессию").font(.headline)
                TextEditor(text: $state.config.instructions)
                    .frame(minHeight: 70)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                    .accessibilityLabel("Указания на эту сессию")
                Text("Важнее инструкций профиля и общих. Например: «Отвечай по-английски», «Акцент на руководстве командой».")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ThemeCard {
                Toggle("Автоответ на вопросы", isOn: $state.config.autoGenerate)
                Text("Выключено — ответ только по кнопке «Ответ» (⌃⌥↩); расшифровка идёт всегда.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("Сохранять расшифровку и ответы в историю", isOn: $state.config.saveTranscript)
                Toggle("Разбор после завершения", isOn: $state.config.reviewAfterEnd)
                    .disabled(!state.config.saveTranscript)
                Stepper(value: $state.config.plannedMinutes, in: SessionConfig.plannedMinutesRange, step: 15) {
                    Text(state.config.plannedMinutes == 0 ? "План длительности: без плана" : "План длительности: \(state.config.plannedMinutes) мин — предупрежу за 5 минут")
                }
                Text("История хранится только на этом Mac \(state.model.settings.historyRetentionDays) дн.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Шаг 3 — Проверка

    private var check: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Проверка перед стартом").font(.headline)
                Spacer()
                if state.checking { ProgressView().controlSize(.small); Text("Слушаю микрофон и звонок 3 с…").foregroundStyle(.secondary).font(.callout) }
                Button("Проверить снова") { state.runPreflight() }.disabled(state.checking)
            }
            ForEach(state.preflight) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon(item.status)).foregroundStyle(color(item.status)).font(.title3)
                        .accessibilityLabel(statusLabel(item.status))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).fontWeight(.semibold)
                        Text(item.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    actionButton(item)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Color.primary.opacity(0.04)))
            }
        }
    }

    @ViewBuilder private func actionButton(_ item: PreflightItem) -> some View {
        switch item.action {
        case .openPermissions:
            Button("Открыть настройки") { NSWorkspace.shared.open(item.id == "mic" ? Permissions.microphoneSettingsURL : Permissions.screenCaptureSettingsURL) }
        case .chooseSource:
            Button("Выбрать источник") { state.step = .settings }
        case .retry:
            Button("Проверить снова") { state.runPreflight() }.disabled(state.checking)
        default:
            EmptyView()
        }
    }

    private func icon(_ s: PreflightItem.Status) -> String {
        switch s {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .fail: "xmark.octagon.fill"
        case .checking: "clock"
        }
    }

    private func color(_ s: PreflightItem.Status) -> Color {
        switch s {
        case .ok: Theme.ok
        case .warning: Theme.warn
        case .fail: Theme.danger
        case .checking: .secondary
        }
    }

    private func statusLabel(_ s: PreflightItem.Status) -> String {
        switch s {
        case .ok: "Готово"
        case .warning: "Предупреждение"
        case .fail: "Не готово"
        case .checking: "Проверяю"
        }
    }

    // MARK: Кнопки

    private var footer: some View {
        HStack {
            Button("Отмена") { state.onCancel() }.keyboardShortcut(.cancelAction)
            Spacer()
            if state.step != .details { Button("Назад") { state.back() } }
            if state.step == .check {
                if !Preflight.canStart(state.preflight) {
                    Button("Начать всё равно") { state.start() }
                }
                Button(state.config.type == .mock ? "Начать собеседование" : "Начать сессию") { state.start() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!Preflight.canStart(state.preflight))
            } else {
                Button(state.step == .settings ? "Далее: проверка" : "Далее") { state.next() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.step == .details && !state.errors.isEmpty)
            }
        }
    }
}
