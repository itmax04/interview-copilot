import CopilotCore
import Foundation
import Observation
import SwiftUI

/// Живой предпросмотр настроек ответа — COPILOT-09 R-12 (Q6): ответ модели на пример вопроса выбранного типа
/// по профилю сессии. Запрос — через 0,6 с после последнего изменения; прежний отменяется; готовые ответы
/// кэшируются, чтобы переключение туда-обратно не тратило бесплатные лимиты.
@MainActor
@Observable
final class StylePreview {
    /// Всё, что нужно для запроса, кроме стиля и вопроса.
    struct Context {
        var settings: AppSettings
        var secrets: SecretStore
        var profile: Profile?
        var generalInstructions = ""
        var sessionType: SessionType = .interview
        var sessionInstructions = ""
        /// Язык примера: uk / ru / en.
        var language = "uk"
    }

    enum Status: Equatable {
        case idle, loading, done, failed(String)
    }

    var style: AnswerStyle { didSet { if style != oldValue { schedule() } } }
    var question: StylePreviewQuestion = .about { didSet { if question != oldValue { schedule() } } }
    var language: String { didSet { if language != oldValue { schedule() } } }
    private(set) var text = ""
    private(set) var status: Status = .idle
    private(set) var source = ""

    private let context: Context
    private let providers: [ProviderID: LLMProvider]
    private var task: Task<Void, Never>?
    private var cache: [String: (text: String, source: String)] = [:]

    init(style: AnswerStyle, context: Context, providers: [ProviderID: LLMProvider] = ChainFactory.providers()) {
        self.style = style
        self.context = context
        self.language = context.language
        self.providers = providers
    }

    var questionText: String {
        context.sessionType == .regular ? question.regularText(language: language) : question.text(language: language)
    }

    /// Инструкции владельца могут задавать форму сами — тогда они важнее (08/R-04), об этом — подпись.
    var hasOwnerInstructions: Bool {
        !(context.generalInstructions + (context.profile?.instructions ?? "") + context.sessionInstructions)
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var words: Int { AnswerShape.words(text) }

    private var key: String { "\(style.format.rawValue)|\(style.length.rawValue)|\(style.tone.rawValue)|\(question.rawValue)|\(language)" }

    func schedule(delay: Duration = .milliseconds(600)) {
        task?.cancel()
        if let hit = cache[key] {
            text = hit.text
            source = hit.source
            status = .done
            return
        }
        status = .loading
        let key = key
        let request = PromptBuilder.hintRequest(
            question: questionText, transcript: [], cards: [], baseCard: nil, profile: context.profile,
            redactPII: context.settings.piiFilterEnabled, answerLanguage: language, generalInstructions: context.generalInstructions,
            session: SessionPrompt(type: context.sessionType, instructions: context.sessionInstructions, style: style))
        let settings = context.settings, secrets = context.secrets, providers = providers
        task = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            let chain = await Task.detached { ChainFactory.chain(settings: settings, secrets: secrets, providers: providers) }.value
            let started = Date()
            var text = "", provider = "", failure: String?
            for await event in chain.run(request) {
                guard !Task.isCancelled else { return }
                switch event {
                case .text(let t):
                    text += t
                    self?.text = text
                case .restart:
                    text = ""
                    self?.text = ""
                case .finished(let p, _): provider = p.displayName
                case .exhausted(let reason): failure = reason
                default: break
                }
            }
            guard let self, !Task.isCancelled else { return }
            if let failure, text.isEmpty {
                self.status = .failed("Модели недоступны: \(failure)")
                return
            }
            self.source = "\(provider) · " + String(format: "%.1f с", Date().timeIntervalSince(started))
            self.status = .done
            self.cache[key] = (text, self.source)
            Log.app.info("style preview \(key, privacy: .public) words=\(AnswerShape.words(text))")
        }
    }

    func refresh() {
        cache[key] = nil
        schedule(delay: .zero)
    }

    func cancel() { task?.cancel() }

    /// Режим снимков (`--ui-snapshots`): готовый ответ в кэше — без сети и Связки ключей.
    func showSnapshot(text: String, source: String) {
        cache[key] = (text, source)
        schedule(delay: .zero)
    }
}

/// Редактор настроек ответа с предпросмотром. `onSave` — только эта сессия; `onSaveDefault` — для всех (nil — кнопки нет).
struct AnswerStyleEditor: View {
    @Bindable var preview: StylePreview
    var saveTitle = "Сохранить для сессии"
    var onSave: (AnswerStyle) -> Void
    var onSaveDefault: ((AnswerStyle) -> Void)?
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 20) {
                controls.frame(width: 330, alignment: .topLeading)
                previewCard
            }
            HStack {
                if preview.hasOwnerInstructions {
                    Label("Ваши инструкции важнее этих настроек", systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Отмена", role: .cancel) { preview.cancel(); onCancel() }
                    .keyboardShortcut(.cancelAction)
                if let onSaveDefault {
                    Button("По умолчанию") { preview.cancel(); onSaveDefault(preview.style) }
                        .help("Для этой и всех следующих сессий")
                }
                Button(saveTitle) { preview.cancel(); onSave(preview.style) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 760, height: 520)
        .tint(Theme.accent)
        .onAppear { preview.schedule(delay: .zero) }
        .onDisappear { preview.cancel() }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Стиль ответа").font(.title2.bold())
            option("Формат", selection: $preview.style.format, cases: AnswerStyle.Format.allCases) { $0.shortTitle }
            option("Длина", selection: $preview.style.length, cases: AnswerStyle.Length.allCases) { $0.title }
            Text("до \(preview.style.length.maxWords) слов").font(.footnote).foregroundStyle(.secondary)
            option("Тон", selection: $preview.style.tone, cases: AnswerStyle.Tone.allCases) { $0.title }
            Divider()
            option("Пример вопроса", selection: $preview.question, cases: StylePreviewQuestion.allCases) { $0.title }
            Picker("Язык примера", selection: $preview.language) {
                Text("Українська").tag("uk")
                Text("Русский").tag("ru")
                Text("English").tag("en")
            }
            Text("Меняется форма ответа, а не факты: факты — из профиля, как на звонке.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func option<T: Hashable>(_ title: String, selection: Binding<T>, cases: [T], label: @escaping (T) -> String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(cases, id: \.self) { Text(label($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    /// Похоже на карточку оверлея: так видно, как ответ будет выглядеть на звонке.
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Предпросмотр").font(.headline)
                Spacer()
                if preview.status == .loading { ProgressView().controlSize(.small) }
                Button { preview.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .disabled(preview.status == .loading)
                    .help("Сгенерировать заново")
                    .accessibilityLabel("Сгенерировать заново")
            }
            VStack(alignment: .leading, spacing: 10) {
                (Text("Вопрос: ").foregroundStyle(.white.opacity(0.55)) + Text(preview.questionText).foregroundStyle(.white))
                    .font(.system(size: 13, weight: .semibold))
                ScrollView {
                    Group {
                        switch preview.status {
                        case .failed(let reason):
                            Label(reason, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
                        case .loading where preview.text.isEmpty:
                            Text("Готовлю ответ…").foregroundStyle(.white.opacity(0.6))
                        default:
                            MarkdownText(preview.text, fontSize: 14).foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if preview.status == .done {
                    Text("\(preview.source) · \(preview.words) слов")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.13)))
            .environment(\.colorScheme, .dark)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Предпросмотр ответа")
        }
    }
}
