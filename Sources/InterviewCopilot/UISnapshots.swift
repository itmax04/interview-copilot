import AppKit
import CopilotCore
import SwiftUI
import WebKit

/// `--ui-snapshots <папка>`: снимки всех окон и состояний на синтетических данных — для исследования интерфейса
/// и редизайна (запрос владельца 2026-10-24). Рисуются настоящие представления приложения, без захвата звука,
/// микрофона и запросов к моделям: данные — во временной папке (`INTERVIEWCOPILOT_HOME`), настройки — в отдельном домене,
/// ключи — в памяти. Запуск из корня репозитория (синтетика из `profile.example/` и `evals/`).
@MainActor
enum UISnapshots {
    static func run(to dir: URL) -> Int32 {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("ic-ui-\(UUID().uuidString)")
        setenv("INTERVIEWCOPILOT_HOME", home.path, 1)
        defer { try? FileManager.default.removeItem(at: home) }
        let suite = "com.itmax04.interviewcopilot.ui-snapshots"
        UserDefaults().removePersistentDomain(forName: suite)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let secrets = InMemorySecretStore()
        try? secrets.set("synthetic-key-0000", for: .groq)
        try? secrets.set("synthetic-key-0000", for: .gemini)
        let model = AppModel(settingsStore: SettingsStore(defaults: UserDefaults(suiteName: suite)!), secrets: secrets)
        model.settings.onboardingCompleted = true
        let listening = ListeningController(model: model)
        let bank = BankController()
        bank.start(embeddingModel: "absent-for-snapshots.gguf", activeProfileID: nil)
        fillProfile(bank)
        var count = 0
        func shot<V: View>(_ name: String, _ size: NSSize, dark: Bool = false, _ view: V) {
            if render(view, size: size, dark: dark, to: dir.appendingPathComponent("\(name).png")) { count += 1 }
        }

        // Панель (R-16): все состояния.
        for (name, configure) in panelStates() {
            let pm = PanelModel()
            pm.hotkeys = model.settings.hotkeys
            configure(pm)
            shot("panel-\(name)", NSSize(width: 380, height: name == "answer-code" ? 620 : 440), dark: true,
                 PanelView(model: pm).background(Color(white: 0.13)))
        }

        // Настройки — каждая вкладка.
        let tabs: [(String, AnyView)] = [
            ("keys", AnyView(KeysSettingsView(model: model))), ("models", AnyView(ModelsSettingsView(model: model))),
            ("audio", AnyView(AudioSettingsView(model: model))), ("bank", AnyView(BankSettingsView(model: model))),
            ("privacy", AnyView(PrivacySettingsView(model: model))), ("panel", AnyView(PanelSettingsView(model: model))),
            ("hotkeys", AnyView(HotkeysSettingsView(model: model, failures: { [:] }))), ("budget", AnyView(BudgetSettingsView(model: model))),
        ]
        for (name, view) in tabs {
            shot("settings-\(name)", NSSize(width: 600, height: name == "audio" ? 1100 : 520), SettingsFrame(selected: name) { view })
        }

        // Окно «Профиль» — каждая вкладка.
        let preparer = QuestionPreparer(bank: bank, model: model)
        let profileTabs: [(String, AnyView)] = [
            ("resume", AnyView(DocumentEditor(bank: bank, doc: .resume))), ("facts", AnyView(DocumentEditor(bank: bank, doc: .facts))),
            ("job", AnyView(DocumentEditor(bank: bank, doc: .job))), ("instructions", AnyView(InstructionsEditor(bank: bank))),
            ("materials", AnyView(MaterialsView(bank: bank))), ("questions", AnyView(QuestionsView(bank: bank, preparer: preparer))),
        ]
        for (name, view) in profileTabs {
            shot("profile-\(name)", NSSize(width: 760, height: 580), ProfileFrame(bank: bank, selected: name) { view })
        }

        if let card = bank.cards.first(where: { $0.status == .draft }) {
            shot("profile-question-editor", NSSize(width: 420, height: 520), CardEditor(bank: bank, card: card, onDelete: {})
                .background(Color(nsColor: .windowBackgroundColor)))
        }

        // Страницы в браузере: ИИ-собеседование и тестовый звонок (начальное состояние, без локального сервера).
        for (name, path) in [("ai-interview", "Resources/Interviewer/index.html"), ("test-call", "Resources/TestCall/index.html")] {
            if renderWeb(URL(fileURLWithPath: path), size: NSSize(width: 1100, height: 760), to: dir.appendingPathComponent("\(name).png")) { count += 1 }
        }

        // Мастер «Создать сессию» (COPILOT-09): три шага; проверка — на синтетических результатах, без захвата звука.
        var config = SessionConfig()
        config.profileID = bank.activeID
        config.company = "ФинБанк"
        config.jobDescription = "Senior iOS Engineer\n\nПлатёжный модуль на SwiftUI, код-ревью, менторство. 5+ лет iOS, Swift Concurrency."
        config.plannedMinutes = 60
        let wizard = SessionWizardModel(config: config, model: model, bank: bank, listening: listening)
        wizard.jobLink = "https://jobs.example.com/senior-ios"
        for step in SessionWizardModel.Step.allCases {
            wizard.step = step
            if step == .check {
                var input = PreflightInput()
                input.micPeakDB = -28
                input.callSourceName = "Google Chrome"
                input.callPeakDB = -90
                input.recognizerReady = true
                input.recognizerStatus = "Parakeet v3 + уточнение Whisper turbo"
                input.providersWithKeys = [.groq, .gemini]
                input.resumeCharacters = 1_900
                input.materials = 3
                input.questions = 9
                input.preparedQuestions = 1
                wizard.preflight = Preflight.evaluate(input)
            }
            shot("wizard-\(step.rawValue + 1)", NSSize(width: 820, height: 600), SessionWizardView(state: wizard))
        }

        // История сессий.
        let store = SessionStore(directory: AppPaths.sessions)
        try? store.save(sampleSession(store))
        shot("history", NSSize(width: 820, height: 640), SessionHistoryView(store: store))

        // Мастер первого запуска и разрешения.
        let onboarding = OnboardingState(model: model, listening: listening, onFinish: {})
        for step in OnboardingState.Step.allCases {
            onboarding.step = step
            shot("onboarding-\(step.rawValue + 1)", NSSize(width: 660, height: 520), OnboardingView(state: onboarding).padding(20))
        }
        shot("permissions", NSSize(width: 600, height: 420), PermissionsView(listening: listening).padding(20))

        print("ui-snapshots: \(count) PNG → \(dir.path)")
        return count > 0 ? 0 : 1
    }

    // MARK: Отрисовка

    private static func render<V: View>(_ view: V, size: NSSize, dark: Bool, to url: URL) -> Bool {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height, alignment: .topLeading))
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        // onAppear, загрузка текста и раскладка — несколько оборотов цикла.
        for _ in 0..<6 { RunLoop.main.run(until: Date().addingTimeInterval(0.08)); hosting.layoutSubtreeIfNeeded() }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return false }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }

    private static func renderWeb(_ url: URL, size: NSSize, to out: URL) -> Bool {
        let web = WKWebView(frame: NSRect(origin: .zero, size: size))
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = web
        window.orderFrontRegardless()
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        final class Box: @unchecked Sendable { var image: NSImage?; var done = false }
        let box = Box()
        web.takeSnapshot(with: nil) { image, _ in box.image = image; box.done = true }
        let deadline = Date().addingTimeInterval(5)
        while !box.done, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        window.orderOut(nil)
        guard let tiff = box.image?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: out)) != nil
    }

    // MARK: Синтетические данные

    private static func fillProfile(_ bank: BankController) {
        let example = URL(fileURLWithPath: "profile.example")
        func read(_ f: String) -> String { (try? String(contentsOf: example.appendingPathComponent(f), encoding: .utf8)) ?? "" }
        bank.renameActive(to: "Senior iOS — ФинБанк")
        bank.save(read("resume.md"), .resume)
        bank.save(read("stories.md"), .facts)
        bank.save(read("job.md"), .job)
        bank.save("Отвечай 2–3 предложениями, делай акцент на измеримых результатах.", .instructions)
        bank.saveGeneralInstructions("Не упоминай технологии, которых нет в резюме, как свой опыт.")
        if var cards = try? QuestionBankParser.load(example.appendingPathComponent("questions.yaml")) {
            cards = Array(cards.prefix(8))
            if cards.count > 3 { cards[2].status = .draft; cards[3].answer = ""; cards[3].status = .none; cards[3].questions = [cards[3].questions[0]] }
            cards[0].prepared = true
            bank.saveCards(cards + [BankCard(id: "q-new", questions: ["Как вы проводите код-ревью?"], answer: "")])
        }
        let docs = URL(fileURLWithPath: "evals/materials/docs")
        let files = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? []
        _ = bank.addMaterials(files.filter { $0.pathExtension == "md" }.sorted { $0.path < $1.path })
    }

    private static func sampleSession(_ store: SessionStore) -> SessionRecord {
        let start = Date(timeIntervalSince1970: 1_792_400_000)
        var s = store.newSession(source: "Google Chrome", at: start)
        s.endedAt = start.addingTimeInterval(1_900)
        s.utterances = [
            .init(id: 1, text: "Расскажите о себе.", language: "ru", at: start.addingTimeInterval(30)),
            .init(id: 2, text: "Как вы организуете тестирование?", language: "ru", at: start.addingTimeInterval(180)),
            .init(id: 3, text: "Tell me about a conflict in your team.", language: "en", at: start.addingTimeInterval(420)),
        ]
        s.turns = [
            .init(id: 1, question: "Расскажите о себе.", answer: "**7 лет в iOS, 3 года тимлидом.**\n- Мобильный банк на 1,2 млн пользователей\n- 70% экранов на SwiftUI",
                  source: "groq", model: "openai/gpt-oss-120b", cardID: nil, forced: false, cardShownMs: nil, firstTokenMs: 1180,
                  inputTokens: 1420, outputTokens: 160, at: start.addingTimeInterval(32)),
            .init(id: 2, question: "Как вы организуете тестирование?", answer: "• Unit-тесты на бизнес-логику\n• Snapshot-тесты экранов\n• Покрытие ~70%",
                  source: "bank", model: nil, cardID: "testing", forced: false, cardShownMs: 640, firstTokenMs: nil,
                  inputTokens: nil, outputTokens: nil, at: start.addingTimeInterval(182)),
            .init(id: 3, question: "Tell me about a conflict in your team.", answer: "**We disagreed on the API format.**\n- Aligned on a shared call\n- Fixed the contract in OpenAPI",
                  source: "gemini", model: "gemini-flash-lite-latest", cardID: nil, forced: true, cardShownMs: nil, firstTokenMs: 1490,
                  inputTokens: 1610, outputTokens: 140, at: start.addingTimeInterval(424)),
        ]
        s.exchanges = [
            SessionExchange(id: 1, question: "Расскажите о себе.", answer: ["Я iOS-разработчик, семь лет опыта, последние три года — тимлид."],
                            askedAt: start.addingTimeInterval(30), turnID: 1),
            SessionExchange(id: 2, question: "Как вы организуете тестирование?", answer: ["Unit и snapshot тесты, покрытие около семидесяти процентов."],
                            askedAt: start.addingTimeInterval(180), turnID: 2),
        ]
        return s
    }

    private static func panelStates() -> [(String, (PanelModel) -> Void)] {
        func listening(_ m: PanelModel) {
            m.sourceName = "Google Chrome"
            m.lines = [.init(id: 1, text: "Добрый день! Расскажите немного о себе."),
                       .init(id: 2, text: "Und dann haben wir das Meeting verschoben.", filtered: "язык de"),
                       .init(id: 3, text: "Какой у вас опыт со SwiftUI?")]
        }
        func session(_ m: PanelModel) {
            listening(m); m.state = .listening; m.sessionActive = true; m.sessionTimer = "12:40"
            m.micLevel = -32; m.callLevel = -24
        }
        @discardableResult
        func answer(_ m: PanelModel, _ q: String, _ text: String, source: String, latency: Double) -> (entry: Int, version: Int) {
            let ids = m.history.begin(question: q, turnID: nil, kind: .hint)
            m.history.update(entry: ids.entry, version: ids.version) {
                $0.text = text; $0.source = source; $0.latency = latency; $0.status = .complete
            }
            return ids
        }
        let swiftUI = "**Пять лет со SwiftUI, перевёл 70% экранов банка без остановки релизов.**\n- Навигация на NavigationStack и координаторах\n- Состояние — @Observable, тяжёлые списки — LazyVStack\n- Snapshot-тесты на ключевые экраны"
        return [
            ("idle", { $0.state = .idle }),
            ("no-session", { $0.state = .noSession }),
            ("call-detected", { $0.state = .noSession; $0.callDetected = "Zoom" }),
            ("session-active", { m in
                listening(m); m.state = .listening; m.sessionActive = true; m.sessionTimer = "56:12"
                m.planNotice = "Осталось 4 мин по плану"
            }),
            ("no-permission", { $0.state = .noPermission }),
            ("downloading", { $0.state = .downloading(0.42) }),
            ("listening", { m in listening(m); m.state = .listening; m.partial = "А как вы тестируете" }),
            ("detecting", { m in session(m); m.detection = .checking; m.partial = "Какой у вас опыт со SwiftUI" }),
            ("thinking", { m in
                session(m); m.detection = .detected
                answer(m, "Расскажите о себе.", "**7 лет в iOS, 3 года тимлидом.**\n- Мобильный банк на 1,2 млн пользователей", source: "Groq · generated", latency: 1.1)
                m.history.begin(question: "Какой у вас опыт со SwiftUI?", turnID: 2, kind: .hint)
            }),
            ("answer", { m in
                session(m); m.detection = .detected; m.strongModelAvailable = true; m.strongModelName = "Claude"
                answer(m, "Расскажите о себе.", "**7 лет в iOS, 3 года тимлидом.**", source: "Groq · generated", latency: 1.1)
                answer(m, "Эээ, какой у вас опыт со SwiftUI? И как вы тестируете?", swiftUI, source: "Groq · generated", latency: 1.2)
            }),
            ("answer-history", { m in
                session(m)
                answer(m, "Расскажите о себе.", "**7 лет в iOS, 3 года тимлидом.**\n- Мобильный банк на 1,2 млн пользователей", source: "Groq · generated", latency: 1.1)
                answer(m, "Какой у вас опыт со SwiftUI?", swiftUI, source: "Groq · generated", latency: 1.2)
                m.history.selectPrevious()
                answer(m, "Как вы организуете тестирование?", "• Unit-тесты на бизнес-логику", source: "Groq · generated", latency: 0.9)
            }),
            ("answer-versions", { m in
                session(m)
                let ids = answer(m, "Какой у вас опыт со SwiftUI?", swiftUI, source: "Groq · generated", latency: 1.2)
                if let v = m.history.beginVersion(of: ids.entry, kind: .refine, instruction: "короче") {
                    m.history.update(entry: ids.entry, version: v) {
                        $0.text = "**5 лет со SwiftUI, 70% экранов банка.**"; $0.source = "Groq · уточнение"; $0.latency = 0.8; $0.status = .complete
                    }
                }
            }),
            ("answer-code", { m in
                session(m)
                let ids = m.history.begin(question: "Скриншот задачи", turnID: nil, kind: .screenshot)
                m.history.update(entry: ids.entry, version: ids.version) {
                    $0.text = "1. **Task** — найти два числа с суммой target.\n2. **Approach** — словарь «значение → индекс».\n```swift\nfunc twoSum(_ nums: [Int], _ target: Int) -> [Int] {\n    var seen: [Int: Int] = [:]\n    for (i, n) in nums.enumerated() {\n        if let j = seen[target - n] { return [j, i] }\n        seen[n] = i\n    }\n    return []\n}\n```\n4. **Complexity** — O(n) времени, O(n) памяти."
                    $0.source = "Claude · strong"; $0.latency = 3.4; $0.status = .complete
                }
            }),
            ("bank-card", { m in
                session(m)
                let ids = m.history.begin(question: "Расскажите о себе.", turnID: 1, kind: .bank)
                m.history.update(entry: ids.entry, version: ids.version) {
                    $0.text = "• 7 лет в iOS, 3 года тимлидом команды из 4 человек\n• Мобильный банк на 1,2 млн пользователей, рейтинг 4,8"
                    $0.source = "Bank · about-me · 91%"; $0.latency = 0.6; $0.tags = ["S", "T", "A", "R"]; $0.status = .complete
                }
            }),
            ("no-match", { m in
                session(m)
                let ids = m.history.begin(question: "Какой у вас опыт со SwiftUI?", turnID: 1, kind: .bank)
                m.history.update(entry: ids.entry, version: ids.version) {
                    $0.source = "Нет в базе"; $0.status = .noMatch(["swiftui · 71%", "architecture · 66%", "testing · 52%"])
                }
            }),
            ("answer-failed", { m in
                session(m)
                let ids = m.history.begin(question: "Какой у вас опыт со SwiftUI?", turnID: 1, kind: .hint)
                m.history.update(entry: ids.entry, version: ids.version) { $0.status = .failed("Все модели недоступны: Groq 429, Gemini — таймаут") }
            }),
            ("not-question", { m in session(m); m.detection = .notQuestion }),
            ("chat-open", { m in
                session(m); answer(m, "Какой у вас опыт со SwiftUI?", swiftUI, source: "Groq · generated", latency: 1.2)
                m.chatOpen = true; m.chatMode = .refine; m.chatText = "без Combine, только async/await"
            }),
            ("session-notes", { m in
                session(m); m.sessionNotes = ["Отвечай на английском", "Не упоминай прошлую зарплату"]
                answer(m, "Tell me about a conflict in your team.", "**We disagreed on the API format.**\n- Aligned on a shared call", source: "Gemini · generated", latency: 1.5)
            }),
            ("call-silent", { m in session(m); m.callSilentSeconds = 14; m.callLevel = -120 }),
            ("collapsed", { m in session(m); m.collapsed = true }),
            ("zoomed", { m in
                session(m); m.zoom = 1.3
                answer(m, "Какой у вас опыт со SwiftUI?", swiftUI, source: "Groq · generated", latency: 1.2)
            }),
            ("private", { m in session(m); m.hiddenFromCapture = true; m.visibilityResult = "Не видно в захвате экрана · 24.10.2026, macOS 15.6" }),
            ("error", { $0.state = .error("Захват звука остановлен macOS. Пауза → Продолжить, чтобы включить снова.") }),
            ("paused", { $0.state = .paused; $0.sourceName = "Google Chrome" }),
            ("self-test-answering", { m in
                m.sourceName = "Микрофон Mac"; m.state = .listening; m.selfTest = true; m.ownerAnswering = true
                m.lines = [.init(id: 1, text: "Над яким проєктом ви працювали останнім?")]
            }),
        ]
    }
}

/// Рамка окна настроек для снимка: вкладки сверху, как в `SettingsView`, выбранная — подсвечена.
private struct SettingsFrame<Content: View>: View {
    let selected: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ForEach(SettingsTab.allCases) { t in
                    VStack(spacing: 2) {
                        Image(systemName: t.symbol)
                        Text(t.rawValue).font(.caption)
                    }
                    .foregroundStyle(t.rawValue.lowercased() == selected ? Color.accentColor : .secondary)
                }
            }
            .padding(.vertical, 8)
            Divider()
            content.padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Рамка окна «Профиль» для снимка: шапка с выбором профиля и вкладки, выбранная — подсвечена.
private struct ProfileFrame<Content: View>: View {
    let bank: BankController
    let selected: String
    @ViewBuilder let content: Content
    private let names = [("resume", "Резюме"), ("facts", "Факты о себе"), ("job", "Вакансия"), ("instructions", "Инструкции"),
                         ("materials", "Материалы"), ("questions", "Вопросы")]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Профиль:").foregroundStyle(.secondary)
                Text(bank.profile.name).fontWeight(.semibold)
                Spacer()
                Text("Новый…  Переименовать…  Удалить…  Папка").foregroundStyle(.secondary).font(.callout)
            }
            HStack(spacing: 2) {
                ForEach(names, id: \.0) { n in
                    Text(n.1).font(.callout)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(n.0 == selected ? Color.accentColor.opacity(0.25) : .clear))
                }
            }
            content
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
