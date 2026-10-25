import AppKit
import CopilotCore
import SwiftUI
import UniformTypeIdentifiers

/// Вопросы профиля (COPILOT-08 R-07, R-08): таблица, импорт файла с проверкой, подготовка формулировок и черновиков.
struct QuestionsView: View {
    let bank: BankController
    let preparer: QuestionPreparer
    @State private var selection: String?
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Примерные вопросы и, если хотите, ваши ответы. На интервью похожий вопрос (другими словами, на другом языке) находится, и модель подстраивает ваш ответ под точную формулировку. «Подготовить» добавит формулировки на трёх языках и черновики ответов там, где ответа нет; ваши ответы не меняются.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            toolbar
            let unprepared = QuestionPreparation.needsPhrasings(bank.cards).count
            if unprepared > 0, !preparer.running {
                // eval bank (2026-10-24): одна формулировка — похожий вопрос находится в 49% случаев, с подготовленными — 95%.
                Label("Не подготовлено вопросов: \(unprepared). Без формулировок на трёх языках похожий вопрос на интервью находится примерно вдвое реже — нажмите «Подготовить».", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange).font(.callout)
            }
            if let message = preparer.message {
                Label(message, systemImage: preparer.failed ? "exclamationmark.triangle.fill" : (preparer.running ? "hourglass" : "checkmark.circle.fill"))
                    .foregroundStyle(preparer.failed ? .orange : .secondary)
                    .font(.callout)
            }
            HSplitView {
                List(bank.cards, selection: $selection) { card in
                    HStack {
                        Text(card.questions.first ?? "").lineLimit(2)
                        Spacer()
                        Text(card.status.title)
                            .font(.caption)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(color(card.status).opacity(0.2)))
                        if card.questions.count > 1 {
                            Text("+\(card.questions.count - 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .help("Других формулировок: \(card.questions.count - 1)")
                        }
                    }
                    .tag(card.id)
                }
                .frame(minWidth: 260, idealWidth: 320)
                .overlay {
                    if bank.cards.isEmpty {
                        Text("Вопросов пока нет: «Импорт файла…» или «Добавить вопрос»").foregroundStyle(.secondary).padding()
                    }
                }
                Group {
                    if let id = selection, let card = bank.cards.first(where: { $0.id == id }) {
                        CardEditor(bank: bank, card: card) { confirmDelete = true }
                            .id(card.id)
                    } else {
                        Text("Выберите вопрос").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 300)
            }
        }
        .padding(8)
        .sheet(isPresented: Binding { preparer.pendingImport != nil } set: { if !$0 { preparer.pendingImport = nil } }) {
            ImportReview(items: preparer.pendingImport ?? []) { preparer.acceptImport($0) } cancel: { preparer.pendingImport = nil }
        }
        .confirmationDialog("Удалить вопрос?", isPresented: $confirmDelete) {
            Button("Удалить", role: .destructive) {
                bank.saveCards(bank.cards.filter { $0.id != selection })
                selection = nil
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Button("Импорт файла…", action: pickFile).keyboardShortcut("i")
            Button("Добавить вопрос") {
                let id = QuestionBankWriter.nextID(bank.cards)
                bank.saveCards(bank.cards + [BankCard(id: id, questions: ["Новый вопрос"], answer: "")])
                selection = id
            }
            Divider().frame(height: 16)
            if preparer.running {
                ProgressView(value: Double(preparer.progress.done), total: Double(max(preparer.progress.total, 1))).frame(width: 120)
                Button("Остановить") { preparer.cancel() }.keyboardShortcut(.cancelAction)
            } else {
                Button("Подготовить") { preparer.prepare() }
                    .disabled(preparer.pendingWork == 0)
                    .help("Формулировки uk/ru/en и черновики ответов — моделями из цепочки (бесплатно, частями)")
            }
            let drafts = bank.cards.filter { $0.status == .draft }.count
            if drafts > 0 {
                Button("Подтвердить черновики (\(drafts))") {
                    bank.saveCards(bank.cards.map { var c = $0; if c.status == .draft { c.status = .approved }; return c })
                }
            }
            Spacer()
            Text("\(bank.cards.count) вопросов").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func color(_ s: AnswerStatus) -> Color {
        switch s {
        case .none: .orange
        case .own: .green
        case .draft: .yellow
        case .approved: .blue
        }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = DocumentText.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.message = "Файл с вопросами (и ответами) — в любой форме"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        preparer.importFile(url)
    }
}

/// Правка одного вопроса: формулировка, ответ, другие формулировки. Сохраняется сама; правка ответа делает его вашим.
struct CardEditor: View {
    let bank: BankController
    let card: BankCard
    let onDelete: () -> Void
    @State private var question = ""
    @State private var answer = ""
    @State private var phrasings = ""
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Вопрос").font(.headline)
            TextField("Вопрос", text: $question, axis: .vertical).lineLimit(1...3)
            HStack {
                Text("Ответ").font(.headline)
                Text("· \(card.status.title)").foregroundStyle(.secondary)
                Spacer()
                if card.status == .draft {
                    Button("Подтвердить") { update { $0.status = .approved } }
                }
            }
            TextEditor(text: $answer)
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                .accessibilityLabel("Ответ")
            Text("Другие формулировки — по одной в строке").font(.headline)
            TextEditor(text: $phrasings)
                .frame(minHeight: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                .accessibilityLabel("Другие формулировки")
            HStack {
                Spacer()
                Button("Удалить вопрос…", role: .destructive, action: onDelete)
            }
        }
        .padding(8)
        .onAppear {
            question = card.questions.first ?? ""
            answer = card.answer
            phrasings = card.questions.dropFirst().joined(separator: "\n")
        }
        .onChange(of: question) { _, _ in scheduleSave() }
        .onChange(of: answer) { _, _ in scheduleSave() }
        .onChange(of: phrasings) { _, _ in scheduleSave() }
        .onDisappear { if saveTask != nil { save() } }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func save() {
        saveTask?.cancel()
        saveTask = nil
        update { c in
            let main = question.trimmingCharacters(in: .whitespacesAndNewlines)
            let others = phrasings.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            c.questions = (main.isEmpty ? [] : [main]) + others.filter { $0 != main }
            if c.questions.isEmpty { c.questions = [card.questions.first ?? "Вопрос"] }
            let newAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            if newAnswer != c.answer.trimmingCharacters(in: .whitespacesAndNewlines) {
                c.answer = newAnswer
                c.status = newAnswer.isEmpty ? .none : .own   // поправили — это уже ваш ответ
            }
        }
    }

    private func update(_ change: (inout BankCard) -> Void) {
        var cards = bank.cards
        guard let i = cards.firstIndex(where: { $0.id == card.id }) else { return }
        let before = cards[i]
        change(&cards[i])
        if cards[i] != before { bank.saveCards(cards) }
    }
}

/// Проверка вопросов из файла перед добавлением (Q13).
struct ImportReview: View {
    let items: [ImportedQuestion]
    let accept: ([ImportedQuestion]) -> Void
    let cancel: () -> Void
    @State private var included: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Найдено вопросов: \(items.count)").font(.title3.bold())
            Text("Снимите отметку с лишнего. Ответы из файла станут вашими; без ответа — «Подготовить» сделает черновик.")
                .font(.callout).foregroundStyle(.secondary)
            List(Array(items.enumerated()), id: \.offset) { i, item in
                Toggle(isOn: Binding { included.contains(i) } set: { if $0 { included.insert(i) } else { included.remove(i) } }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.question).fontWeight(.semibold)
                        Text(item.answer.isEmpty ? "без ответа" : item.answer).lineLimit(2).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(minHeight: 300)
            HStack {
                Spacer()
                Button("Отмена", action: cancel).keyboardShortcut(.cancelAction)
                Button("Добавить (\(included.count))") { accept(items.enumerated().filter { included.contains($0.offset) }.map(\.element)) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(included.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 620, height: 520)
        .onAppear { included = Set(items.indices) }
    }
}
