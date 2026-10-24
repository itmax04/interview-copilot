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
    /// «Пробный звонок» из мастера: мастер закрывается, запускается тестовый звонок.
    var onTestCall: (() -> Void)?

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
        if let test = onTestCall {
            state.onTestCall = { [weak self] in
                self?.window?.close()
                test()
            }
        }
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
        window?.setContentSize(NSSize(width: 900, height: 640))
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
    /// «Пробный звонок» в колонке шагов (P07).
    var onTestCall: (() -> Void)?
    /// Поле ссылки на вакансию открыто кнопкой «Вставить ссылку на вакансию» (P07).
    var showJobLink = false
    /// Указания на сессию раскрыты кнопкой «+ Добавить» (P08).
    var showInstructions = false

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

    /// Сводка профиля для бейджей (P07): чтение с диска — один раз на профиль, а не на каждую перерисовку.
    struct ProfileSummary: Equatable {
        var hasResume: Bool
        var materials: Int
        var questions: Int
    }

    @ObservationIgnored private var summaries: [String: ProfileSummary] = [:]

    func profileSummary(_ id: String) -> ProfileSummary {
        if let cached = summaries[id] { return cached }
        let s = ProfileSummary(hasResume: !bank.library.read(.resume, of: id).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               materials: bank.library.listMaterials(id).count,
                               questions: ((try? QuestionBankParser.load(bank.library.questionsURL(id))) ?? []).count)
        summaries[id] = s
        return s
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

@MainActor
struct SessionWizardView: View {
    @Bindable var state: SessionWizardModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(IC.line).frame(width: 1)
            VStack(alignment: .leading, spacing: 16) {
                ScrollView {
                    Group {
                        switch state.step {
                        case .details: details
                        case .settings: settings
                        case .check: check
                        }
                    }
                    .padding(.trailing, 6)
                }
                Rectangle().fill(IC.line).frame(height: 1)
                footer
            }
            .padding(24)
        }
        .frame(width: 900, height: 640)
        .background(IC.background)
        .foregroundStyle(IC.ink)
        .tint(IC.accent)
                .sheet(isPresented: Binding(get: { state.stylePreview != nil }, set: { if !$0 { state.stylePreview = nil } })) {
            if let preview = state.stylePreview {
                AnswerStyleEditor(preview: preview,
                                  onSave: { state.saveStyle($0, asDefault: false) },
                                  onSaveDefault: { state.saveStyle($0, asDefault: true) },
                                  onCancel: { state.stylePreview = nil })
            }
        }
    }

    // MARK: Колонка шагов (P07)

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Создать сессию").font(.system(size: 28, weight: .bold))
                Text("Детали и настройки звонка").font(.system(size: 15)).foregroundStyle(IC.secondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(SessionWizardModel.Step.allCases, id: \.self) { s in
                    let done = s.rawValue < state.step.rawValue, current = s == state.step
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(current ? IC.accent : IC.card).frame(width: 34, height: 34)
                                .overlay(Circle().strokeBorder(current ? .clear : IC.line))
                            if done {
                                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(IC.accent)
                            } else {
                                Text("\(s.rawValue + 1)").font(.system(size: 15, weight: .medium)).foregroundStyle(current ? .white : IC.secondary)
                            }
                        }
                        Text(s.title).font(.system(size: 16, weight: current ? .semibold : .regular))
                            .foregroundStyle(current ? IC.accent : IC.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Шаг \(s.rawValue + 1): \(s.title)\(current ? ", текущий" : done ? ", пройден" : "")")
                    if s != SessionWizardModel.Step.allCases.last {
                        Rectangle().stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(IC.secondary.opacity(0.5))
                            .frame(width: 1, height: 30).padding(.leading, 17)
                    }
                }
            }
            Spacer()
            Rectangle().fill(IC.line).frame(height: 1)
            if let test = state.onTestCall {
                Button { test() } label: { Label("Пробный звонок", systemImage: "phone").frame(maxWidth: .infinity) }
                    .buttonStyle(ICButtonStyle())
            }
            Text("Без сессии приложение не слушает звонок и микрофон.")
                .font(.system(size: 11)).foregroundStyle(IC.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
        .frame(width: 290, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(IC.sidebar.opacity(0.5))
    }

    // MARK: Шаг 1 — Детали (P07)

    private var typePicker: some View {
        HStack(spacing: 4) {
            ForEach(SessionType.allCases) { t in
                let selected = state.config.type == t
                Button { state.config.type = t } label: {
                    Label(t.title, systemImage: t == .interview ? "person.fill" : t == .regular ? "phone" : "sparkles")
                        .font(.system(size: 14, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? .white : IC.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(selected ? IC.accent : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(IC.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(IC.line))
    }

    private func field<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 14, weight: .semibold))
            content()
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 18) {
            typePicker
            Text(typeHint).font(.system(size: 12)).foregroundStyle(IC.secondary).fixedSize(horizontal: false, vertical: true)
            field("Профиль") {
                Picker("Профиль", selection: Binding(get: { state.config.profileID ?? "" }, set: { state.config.profileID = $0 })) {
                    ForEach(state.bank.profiles) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
                HStack(spacing: 8) {
                    profileBadges
                    Spacer()
                    if state.config.type == .interview, !state.showJobLink, state.jobLink.isEmpty {
                        Button { state.showJobLink = true } label: { Label("Вставить ссылку на вакансию", systemImage: "sparkles") }
                            .buttonStyle(ICButtonStyle())
                    }
                }
                if state.config.type == .regular {
                    Text("Из профиля берутся инструкции и материалы; резюме и вопросы — нет.").font(.system(size: 11)).foregroundStyle(IC.secondary)
                }
            }
            if state.config.type == .interview {
                if state.showJobLink || !state.jobLink.isEmpty {
                    field("Ссылка на вакансию") {
                        HStack {
                            TextField("https://…", text: $state.jobLink).textFieldStyle(.roundedBorder).onSubmit { state.importJob() }
                            Button(state.importing ? "Загружаю…" : "Загрузить") { state.importJob() }
                                .buttonStyle(ICButtonStyle(primary: true))
                                .disabled(state.importing || state.jobLink.isEmpty)
                        }
                        if let message = state.importMessage {
                            Label(message, systemImage: state.importFailed ? "exclamationmark.triangle.fill" : (state.importing ? "hourglass" : "checkmark.circle.fill"))
                                .font(.system(size: 12)).foregroundStyle(state.importFailed ? IC.amber : IC.secondary)
                        }
                    }
                }
                field("Компания") {
                    TextField("Например, ФинБанк", text: $state.config.company).textFieldStyle(.roundedBorder)
                }
                field("Описание вакансии") {
                    TextEditor(text: $state.config.jobDescription)
                        .font(.system(size: 13))
                        .frame(minHeight: 130)
                        .padding(6)
                        .background(IC.card, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(IC.line))
                        .accessibilityLabel("Описание вакансии")
                    Text("Пусто — берется вакансия из профиля.").font(.system(size: 11)).foregroundStyle(IC.secondary)
                }
            }
            ForEach(state.errors, id: \.self) { e in
                Label(e, systemImage: "exclamationmark.circle").foregroundStyle(IC.amber)
            }
        }
    }

    /// «резюме ✓ · 3 материала · 24 вопроса» выбранного профиля.
    @ViewBuilder private var profileBadges: some View {
        if let id = state.config.profileID, state.bank.profiles.contains(where: { $0.id == id }) {
            let p = state.profileSummary(id)
            ICBadge(text: p.hasResume ? "резюме ✓" : "нет резюме", color: p.hasResume ? IC.green : IC.amber)
            ICBadge(text: "\(p.materials) \(RussianPlural.form(p.materials, "материал", "материала", "материалов"))", color: IC.secondary)
            ICBadge(text: RussianPlural.questions(p.questions), color: IC.secondary)
        }
    }

    private var typeHint: String {
        switch state.config.type {
        case .interview: "Собеседование: ответы от вашего лица по резюме, фактам, вакансии, материалам и вопросам профиля."
        case .regular: "Обычный звонок: что сказать по теме разговора, вашим инструкциям и материалам. После звонка — сводка и договоренности."
        case .mock: "ИИ-собеседование: модель задает вопросы голосом, вы отвечаете в микрофон, подсказки — как на звонке."
        }
    }

    // MARK: Шаг 2 — Настройки (P08)

    private func row<Content: View>(_ icon: String, _ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 17)).frame(width: 24).foregroundStyle(IC.ink2)
            Text(title).font(.system(size: 14)).frame(width: 150, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(IC.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(IC.line))
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.config.type != .mock {
                row("speaker.wave.2", "Источник звука") {
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
                    .labelsHidden()
                }
            }
            row("globe", "Язык звонка") {
                Picker("Язык звонка", selection: $state.config.language) {
                    ForEach(RecognitionLanguage.allCases, id: \.self) { Text($0.menuTitle).tag($0) }
                }
                .labelsHidden()
            }
            row("cpu", "Модель") {
                Picker("Модель", selection: $state.config.firstProvider) {
                    Text("По порядку цепочки (\(state.providersWithKeys.first?.displayName ?? "нет ключей"))").tag(ProviderID?.none)
                    ForEach(state.providersWithKeys, id: \.self) { Text($0.displayName).tag(ProviderID?.some($0)) }
                }
                .labelsHidden()
                .help("Выбранная модель — первой, остальные из цепочки — запасными.")
            }
            if state.config.type != .mock {
                row("doc.text", "Стиль ответа") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.effectiveStyle.summary).font(.system(size: 13)).lineLimit(1)
                            Text(state.config.style == nil ? "По умолчанию" : "Только для этой сессии")
                                .font(.system(size: 11)).foregroundStyle(IC.secondary)
                        }
                        Spacer()
                        Button { state.openStyleEditor() } label: { Label("Настроить", systemImage: "gearshape") }
                            .buttonStyle(ICButtonStyle())
                    }
                }
            }
            row("list.bullet.rectangle", "Указания на сессию") {
                if state.showInstructions || !state.config.instructions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        TextEditor(text: $state.config.instructions)
                            .font(.system(size: 13))
                            .frame(minHeight: 60)
                            .padding(4)
                            .background(IC.background, in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel("Указания на эту сессию")
                        Text("Важнее инструкций профиля и общих: «Отвечай по-английски», «Акцент на руководстве командой».")
                            .font(.system(size: 11)).foregroundStyle(IC.secondary)
                    }
                } else {
                    Button { state.showInstructions = true } label: {
                        Label("Добавить", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 9)
                            .foregroundStyle(IC.accent)
                            .background(IC.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(IC.accent.opacity(0.25)))
                    }
                    .buttonStyle(.plain)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Дополнительно").font(.system(size: 14, weight: .semibold))
                Toggle("Автоответ на вопросы (рекомендуется)", isOn: $state.config.autoGenerate).toggleStyle(.switch)
                Text("Выключено — ответ только по кнопке «Ответ»; расшифровка идет всегда.").font(.system(size: 11)).foregroundStyle(IC.secondary)
                Toggle("Сохранять расшифровку", isOn: $state.config.saveTranscript).toggleStyle(.switch)
                Toggle("Разбор после завершения", isOn: $state.config.reviewAfterEnd).toggleStyle(.switch)
                    .disabled(!state.config.saveTranscript)
                Text("Расшифровка хранится только на этом Mac \(state.model.settings.historyRetentionDays) дн.")
                    .font(.system(size: 11)).foregroundStyle(IC.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(IC.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(IC.line))
            row("clock", "План длительности") {
                HStack {
                    Text(state.config.plannedMinutes == 0 ? "Без плана" : "Предупрежу за 5 минут").font(.system(size: 12)).foregroundStyle(IC.secondary)
                    Spacer()
                    Stepper(value: $state.config.plannedMinutes, in: SessionConfig.plannedMinutesRange, step: 15) {
                        Text(state.config.plannedMinutes == 0 ? "—" : "\(state.config.plannedMinutes) мин").monospacedDigit()
                    }
                    .fixedSize()
                }
            }
        }
    }

    // MARK: Шаг 3 — Проверка (P09)

    private var check: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Проверка перед стартом").font(.system(size: 18, weight: .semibold))
                Spacer()
                if state.checking {
                    ProgressView().controlSize(.small)
                    Text("Слушаю микрофон и звонок 3 с…").foregroundStyle(IC.secondary).font(.system(size: 12))
                }
                Button { state.runPreflight() } label: { Label("Проверить снова", systemImage: "arrow.clockwise") }
                    .buttonStyle(ICButtonStyle())
                    .disabled(state.checking)
            }
            ForEach(state.preflight) { item in
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: icon(item.id)).font(.system(size: 18)).frame(width: 26).foregroundStyle(IC.ink2)
                    Text(item.title).font(.system(size: 15, weight: .medium)).frame(width: 150, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            if item.status == .checking { ProgressView().controlSize(.mini) } else { Circle().fill(color(item.status)).frame(width: 9, height: 9) }
                            Text(statusLabel(item.status)).font(.system(size: 13, weight: .medium)).foregroundStyle(color(item.status))
                        }
                        Text(item.detail).font(.system(size: 12)).foregroundStyle(IC.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    actionButton(item)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(IC.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(IC.line))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func icon(_ id: String) -> String {
        switch id {
        case "mic": "mic"
        case "call": "speaker.wave.2"
        case "stt": "doc.text"
        case "keys": "bolt"
        case "profile": "person"
        default: "checkmark.circle"
        }
    }

    @ViewBuilder private func actionButton(_ item: PreflightItem) -> some View {
        switch item.action {
        case .openPermissions:
            Button("Открыть настройки") { NSWorkspace.shared.open(item.id == "mic" ? Permissions.microphoneSettingsURL : Permissions.screenCaptureSettingsURL) }
                .buttonStyle(ICButtonStyle())
        case .chooseSource:
            Button("Выбрать источник") { state.step = .settings }.buttonStyle(ICButtonStyle())
        case .retry:
            Button("Проверить снова") { state.runPreflight() }.buttonStyle(ICButtonStyle()).disabled(state.checking)
        default:
            EmptyView()
        }
    }

    private func color(_ s: PreflightItem.Status) -> Color {
        switch s {
        case .ok: IC.green
        case .warning: IC.amber
        case .fail: IC.red
        case .checking: IC.secondary
        }
    }

    private func statusLabel(_ s: PreflightItem.Status) -> String {
        switch s {
        case .ok: "Готово"
        case .warning: "Внимание"
        case .fail: "Не готово"
        case .checking: "Проверяю"
        }
    }

    // MARK: Кнопки

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Отмена") { state.onCancel() }.keyboardShortcut(.cancelAction).buttonStyle(ICButtonStyle())
            Spacer()
            if state.step != .details { Button("Назад") { state.back() }.buttonStyle(ICButtonStyle()) }
            if state.step == .check {
                if !Preflight.canStart(state.preflight) {
                    Button("Начать всё равно") { state.start() }.buttonStyle(ICButtonStyle())
                }
                Button { state.start() } label: {
                    Label(state.config.type == .mock ? "Начать собеседование" : "Начать сессию", systemImage: "play")
                }
                .buttonStyle(ICButtonStyle(primary: true))
                .keyboardShortcut(.defaultAction)
                .disabled(!Preflight.canStart(state.preflight))
            } else {
                Button(state.step == .settings ? "Далее: проверка" : "Далее") { state.next() }
                    .buttonStyle(ICButtonStyle(primary: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.step == .details && !state.errors.isEmpty)
            }
        }
    }
}
