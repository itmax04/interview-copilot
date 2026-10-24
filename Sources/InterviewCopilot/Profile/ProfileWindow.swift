import AppKit
import CopilotCore
import SwiftUI
import UniformTypeIdentifiers

/// Окно «Профиль» — COPILOT-08 R-03: профили, резюме, факты о себе, вакансия, инструкции; загрузка файлов и правка текста.
@MainActor
final class ProfileWindowController {
    private var window: NSWindow?
    private let bank: BankController
    private let preparer: QuestionPreparer

    init(bank: BankController, model: AppModel) {
        self.bank = bank
        self.preparer = QuestionPreparer(bank: bank, model: model)
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: ProfileView(bank: bank, preparer: preparer)))
            w.title = "Профиль"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 1100, height: 720))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Размер текста, который уходит в каждый запрос: дальше бесплатные лимиты (Groq — токены в минуту) кончаются быстрее.
enum ProfileLimits {
    static let warnCharacters = 12_000
}

struct ProfileView: View {
    let bank: BankController
    let preparer: QuestionPreparer
    @State private var naming: NamingMode?
    @State private var newName = ""
    @State private var confirmDelete = false
    @State private var tab: Tab

    enum NamingMode { case create, rename }

    /// P13: разделы профиля — вкладки с иконками.
    enum Tab: String, CaseIterable, Identifiable {
        case resume = "Резюме", facts = "Факты о себе", job = "Вакансия", instructions = "Инструкции"
        case materials = "Материалы", questions = "Вопросы"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .resume: "doc.text"
            case .facts: "person"
            case .job: "briefcase"
            case .instructions: "list.bullet.rectangle"
            case .materials: "paperclip"
            case .questions: "text.bubble"
            }
        }
    }

    init(bank: BankController, preparer: QuestionPreparer, tab: Tab = .resume) {
        self.bank = bank
        self.preparer = preparer
        _tab = State(initialValue: tab)
    }

    var body: some View {
        HStack(spacing: 0) {
            profileList
            Rectangle().fill(IC.line).frame(width: 1)
            VStack(alignment: .leading, spacing: 14) {
                header
                tabBar
                Group {
                    switch tab {
                    case .resume: DocumentEditor(bank: bank, doc: .resume)
                    case .facts: DocumentEditor(bank: bank, doc: .facts)
                    case .job: DocumentEditor(bank: bank, doc: .job)
                    case .instructions: InstructionsEditor(bank: bank)
                    case .materials: MaterialsView(bank: bank)
                    case .questions: QuestionsView(bank: bank, preparer: preparer)
                    }
                }
                .id("\(bank.activeID ?? "")-\(tab.rawValue)")   // другой профиль — свежие тексты
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
                .background(IC.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(IC.line))
                footer
            }
            .padding(24)
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(IC.background)
                .alert(naming == .create ? "Новый профиль" : "Переименовать профиль", isPresented: Binding {
            naming != nil
        } set: { if !$0 { naming = nil } }) {
            TextField("Название, например «iOS в банк»", text: $newName)
            Button(naming == .create ? "Создать" : "Сохранить") {
                if naming == .create { bank.createProfile(name: newName) } else { bank.renameActive(to: newName) }
                naming = nil
            }
            .keyboardShortcut(.defaultAction)
            Button("Отмена", role: .cancel) { naming = nil }
        }
        .confirmationDialog("Удалить профиль «\(bank.profile.name)»?", isPresented: $confirmDelete) {
            Button("Удалить резюме, инструкции и вопросы профиля", role: .destructive) { bank.deleteActive() }
        } message: {
            Text("Файлы профиля удаляются с этого Mac без возможности восстановления.")
        }
    }

    /// P13: список профилей с «+ Новый профиль».
    private var profileList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Профили").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button { newName = ""; naming = .create } label: { Image(systemName: "plus").frame(width: 28, height: 28) }
                    .buttonStyle(ICButtonStyle())
                    .keyboardShortcut("n")
                    .help("Новый профиль")
                    .accessibilityLabel("Новый профиль")
            }
            .padding(.bottom, 6)
            ForEach(bank.profiles) { p in
                let active = p.id == bank.activeID
                Button { bank.select(p.id) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person").font(.system(size: 16)).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.system(size: 13, weight: active ? .semibold : .regular)).lineLimit(1)
                            if active { Text("Активный").font(.system(size: 11)).foregroundStyle(IC.secondary) }
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(active ? IC.accent : IC.ink)
                    .padding(10)
                    .background(active ? IC.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
            Button { newName = ""; naming = .create } label: {
                Label("Новый профиль", systemImage: "plus.circle").font(.system(size: 13)).padding(10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(IC.secondary)
            Spacer()
        }
        .padding(16)
        .frame(width: 250)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text(bank.profile.name).font(.system(size: 28, weight: .bold)).lineLimit(1)
                HStack(spacing: 8) {
                    if bank.profile.resume.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ICBadge(text: "Нет резюме", color: IC.amber, dot: true)
                    } else {
                        ICBadge(text: "Резюме ✓", color: IC.green)
                    }
                    ICBadge(text: "\(bank.materials.count) \(RussianPlural.form(bank.materials.count, "материал", "материала", "материалов"))", color: IC.secondary)
                    ICBadge(text: RussianPlural.questions(bank.cards.count), color: IC.secondary)
                }
            }
            Spacer()
            Button { newName = bank.profile.name; naming = .rename } label: { Label("Переименовать", systemImage: "pencil") }
                .buttonStyle(ICButtonStyle())
            Menu {
                Button("Открыть папку профиля") { bank.openProfileFolder() }
                Divider()
                Button("Удалить профиль…", role: .destructive) { confirmDelete = true }
            } label: {
                Image(systemName: "ellipsis").frame(width: 30, height: 30)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Еще")
        }
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { t in
                let selected = t == tab
                Button { tab = t } label: {
                    VStack(spacing: 8) {
                        Label(t.rawValue, systemImage: t.symbol)
                            .font(.system(size: 13, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? IC.accent : IC.ink2)
                            .padding(.horizontal, 10)
                        Rectangle().fill(selected ? IC.accent : .clear).frame(height: 2)
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer()
        }
        .overlay(alignment: .bottom) { Rectangle().fill(IC.line).frame(height: 1) }
    }

    private var footer: some View {
        let p = bank.profile
        let total = p.resume.count + p.stories.count + p.job.count + p.instructions.count + bank.generalInstructions.count
        return HStack {
            Text("В каждый запрос к модели: \(total) символов · вопросов в базе: \(bank.cards.count)")
            if total > ProfileLimits.warnCharacters {
                Label("Длинно: бесплатные лимиты кончаются быстрее, ответ медленнее", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Spacer()
            if let error = bank.error { Text(error).foregroundStyle(.red).lineLimit(1) }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

/// Раздел профиля: загрузка файла (кнопка, ⌘O или перетаскивание) и правка прочитанного текста с автосохранением.
struct DocumentEditor: View {
    let bank: BankController
    let doc: ProfileDocument
    @State private var text = ""
    @State private var message: String?
    @State private var failed = false
    @State private var saveTask: Task<Void, Never>?
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(hint).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Загрузить файл…", action: pickFile)
                    .keyboardShortcut("o")
                Text("PDF, Word (.docx), RTF, TXT, Markdown — или перетащите файл в поле").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Text("\(text.count) символов").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let message {
                Label(message, systemImage: failed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(failed ? .orange : .green)
                    .font(.callout)
            }
            TextEditor(text: $text)
                .font(.body)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                                                                  lineWidth: dropTargeted ? 2 : 1))
                .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: drop)
                .accessibilityLabel(doc.title)
        }
        .padding(8)
        .onAppear { text = bank.text(doc) }
        .onChange(of: text) { _, new in scheduleSave(new) }
        .onDisappear { flush() }
    }

    private var hint: String {
        switch doc {
        case .resume: "Резюме: места работы, проекты, технологии, достижения. Модель берёт факты отсюда и не противоречит им."
        case .facts: "Факты о себе, которых нет в резюме: истории в формате STAR, цифры, причины ухода, зарплатные ожидания, что важно в работе."
        case .job: "Вакансия и компания, куда идёте: требования, продукт, стек. Модель подстраивает акценты ответов под неё."
        case .instructions: ""
        }
    }

    private func scheduleSave(_ value: String) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            bank.save(value, doc)
        }
    }

    private func flush() {
        guard saveTask != nil else { return }
        saveTask?.cancel()
        saveTask = nil
        bank.save(text, doc)
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = DocumentText.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.message = "Файл для раздела «\(doc.title)»"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in load(url) }
        }
        return true
    }

    private func load(_ url: URL) {
        saveTask?.cancel()
        saveTask = nil
        switch bank.importFile(url, as: doc) {
        case .success(let extracted):
            text = extracted
            saveTask = nil
            failed = false
            message = "Загружено «\(url.lastPathComponent)»: \(extracted.count) символов. Проверьте текст — его можно поправить здесь."
        case .failure(let error):
            failed = true
            message = (error as? DocumentTextError)?.description ?? error.localizedDescription
        }
    }
}

/// Инструкции владельца (R-04): профиля и общие. Это указания модели — стиль, длина, акценты, чего не говорить.
struct InstructionsEditor: View {
    let bank: BankController
    @State private var profileText = ""
    @State private var generalText = ""
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Как модели отвечать: стиль, длина, на чём делать акцент, чего не говорить. Инструкции важнее встроенных правил "
                 + "оформления; профиль важнее общих. Например: «Отвечай 2–3 предложениями без списков», «Делай акцент на лидерстве», "
                 + "«Не упоминай Kafka — я с ней не работал», «Отвечай на английском».")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Для профиля «\(bank.profile.name)»").font(.headline)
            TextEditor(text: $profileText)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                .accessibilityLabel("Инструкции профиля")
            Text("Общие — для всех профилей и режима «Без профиля»").font(.headline)
            TextEditor(text: $generalText)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                .accessibilityLabel("Общие инструкции")
        }
        .padding(8)
        .onAppear {
            profileText = bank.text(.instructions)
            generalText = bank.generalInstructions
        }
        .onChange(of: profileText) { _, _ in scheduleSave() }
        .onChange(of: generalText) { _, _ in scheduleSave() }
        .onDisappear { save() }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func save() {
        saveTask?.cancel()
        saveTask = nil
        if profileText != bank.text(.instructions) { bank.save(profileText, .instructions) }
        if generalText != bank.generalInstructions { bank.saveGeneralInstructions(generalText) }
    }
}

/// Материалы профиля (R-06): конспекты, документация, заметки. Целиком в запрос не идут — только 3–4 фрагмента,
/// похожие на вопрос (локальный поиск bge-m3).
struct MaterialsView: View {
    let bank: BankController
    @State private var selection: String?
    @State private var errors: [String] = []
    @State private var confirmDelete: String?
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Конспекты, документация, заметки по темам интервью — десятки и сотни страниц. Модель получает только "
                 + "несколько фрагментов, похожих на текущий вопрос, и использует их факты и термины.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Добавить файлы…", action: pickFiles)
                    .keyboardShortcut("o")
                Button("Удалить…", role: .destructive) { confirmDelete = selection }
                    .disabled(selection == nil)
                    .keyboardShortcut(.delete)
                Spacer()
                Text(bank.materialStatus).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            ForEach(errors, id: \.self) { e in
                Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
            }
            HSplitView {
                List(bank.materials, selection: $selection) { m in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.name).lineLimit(1)
                        Text("\(m.characters) символов").font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(m.name)
                }
                .frame(minWidth: 200, idealWidth: 240)
                .overlay {
                    if bank.materials.isEmpty {
                        Text("Перетащите сюда PDF, Word, RTF, TXT или Markdown").foregroundStyle(.secondary).padding()
                    }
                }
                ScrollView {
                    Text(selection.map { bank.materialText($0) } ?? "Выберите файл, чтобы увидеть прочитанный текст")
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minWidth: 280)
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(dropTargeted ? Color.accentColor : .clear, lineWidth: 2))
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: drop)
        }
        .padding(8)
        .confirmationDialog("Удалить «\(confirmDelete ?? "")» из материалов?", isPresented: Binding {
            confirmDelete != nil
        } set: { if !$0 { confirmDelete = nil } }) {
            Button("Удалить", role: .destructive) {
                if let name = confirmDelete { bank.removeMaterial(name) }
                if selection == confirmDelete { selection = nil }
                confirmDelete = nil
            }
        }
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = DocumentText.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = true
        panel.message = "Материалы для профиля «\(bank.profile.name)»"
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        let box = URLCollector(expected: providers.count) { urls in Task { @MainActor in add(urls) } }
        for p in providers { _ = p.loadObject(ofClass: URL.self) { url, _ in box.add(url) } }
        return !providers.isEmpty
    }

    private func add(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        errors = bank.addMaterials(urls)
        if selection == nil { selection = urls.first?.lastPathComponent }
    }
}

/// Собирает адреса перетащенных файлов (приходят по одному из разных потоков) и отдаёт их разом.
final class URLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    private var received = 0
    private let expected: Int
    private let done: @Sendable ([URL]) -> Void

    init(expected: Int, done: @escaping @Sendable ([URL]) -> Void) {
        self.expected = expected
        self.done = done
    }

    func add(_ url: URL?) {
        let finished: [URL]? = lock.withLock {
            if let url { urls.append(url) }
            received += 1
            return received == expected ? urls : nil
        }
        if let finished { done(finished) }
    }
}
