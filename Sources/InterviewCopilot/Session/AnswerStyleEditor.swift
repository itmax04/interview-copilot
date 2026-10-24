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

/// Редактор настроек ответа с предпросмотром (P11). `onSave` — только эта сессия; `onSaveDefault` — для всех (nil — кнопки нет).
struct AnswerStyleEditor: View {
    @Bindable var preview: StylePreview
    var saveTitle = "Сохранить для сессии"
    var onSave: (AnswerStyle) -> Void
    var onSaveDefault: ((AnswerStyle) -> Void)?
    var onCancel: () -> Void
    @State private var open: Option? = .length

    enum Option { case format, length, tone }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Стиль ответа").font(.system(size: 22, weight: .bold))
                    Spacer()
                    Button { preview.cancel(); onCancel() } label: { Image(systemName: "xmark").frame(width: 14, height: 14) }
                        .buttonStyle(ICButtonStyle())
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel("Закрыть")
                }
                optionCard(.format, icon: "doc.text", title: "Формат", value: preview.style.format.title) {
                    segmented($preview.style.format, AnswerStyle.Format.allCases) { $0.shortTitle }
                }
                optionCard(.length, icon: "clock", title: "Длина", value: "\(preview.style.length.title) · до \(preview.style.length.maxWords) слов") {
                    segmented($preview.style.length, AnswerStyle.Length.allCases) { $0.title }
                }
                optionCard(.tone, icon: "waveform", title: "Тон", value: preview.style.tone.title) {
                    segmented($preview.style.tone, AnswerStyle.Tone.allCases) { $0.title }
                }
                if preview.hasOwnerInstructions {
                    Label("Ваши инструкции важнее этих настроек", systemImage: "info.circle")
                        .font(.system(size: 11)).foregroundStyle(IC.secondary)
                }
                Spacer()
                Rectangle().fill(IC.line).frame(height: 1)
                HStack(spacing: 10) {
                    if let onSaveDefault {
                        Button { preview.cancel(); onSaveDefault(preview.style) } label: { Label("По умолчанию", systemImage: "arrow.clockwise") }
                            .buttonStyle(ICButtonStyle())
                            .help("Для этой и всех следующих сессий")
                    }
                    Button { preview.cancel(); onSave(preview.style) } label: {
                        Label(saveTitle, systemImage: "paperplane").lineLimit(1).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ICButtonStyle(primary: true))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 430)
            Rectangle().fill(IC.line).frame(width: 1)
            previewPane.padding(24)
        }
        .frame(width: 900, height: 600)
        .background(IC.background)
        .foregroundStyle(IC.ink)
        .tint(IC.accent)
                .onAppear { preview.schedule(delay: .zero) }
        .onDisappear { preview.cancel() }
    }

    private func optionCard<Content: View>(_ option: Option, icon: String, title: String, value: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        let expanded = open == option
        return VStack(alignment: .leading, spacing: 12) {
            Button { open = expanded ? nil : option } label: {
                HStack(spacing: 14) {
                    Image(systemName: icon).font(.system(size: 18)).frame(width: 44, height: 44)
                        .background(expanded ? IC.accent.opacity(0.12) : IC.background, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(expanded ? IC.accent : IC.ink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 15, weight: .semibold))
                        Text(value).font(.system(size: 13)).foregroundStyle(IC.secondary)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").foregroundStyle(expanded ? IC.accent : IC.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title): \(value)")
            if expanded { content() }
        }
        .padding(14)
        .background(expanded ? IC.accent.opacity(0.05) : IC.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(expanded ? IC.accent.opacity(0.3) : IC.line))
    }

    private func segmented<T: Hashable>(_ selection: Binding<T>, _ cases: [T], label: @escaping (T) -> String) -> some View {
        HStack(spacing: 4) {
            ForEach(cases, id: \.self) { c in
                let selected = selection.wrappedValue == c
                Button { selection.wrappedValue = c } label: {
                    Text(label(c)).font(.system(size: 13, weight: selected ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(selected ? .white : IC.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(selected ? IC.accent : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(IC.card, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(IC.line))
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Тип вопроса").font(.system(size: 13)).foregroundStyle(IC.secondary)
            HStack(spacing: 10) {
                Picker("Тип вопроса", selection: $preview.question) {
                    ForEach(StylePreviewQuestion.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                Picker("Язык", selection: $preview.language) {
                    Text("Українська").tag("uk")
                    Text("Русский").tag("ru")
                    Text("English").tag("en")
                }
                .labelsHidden()
                .frame(width: 130)
            }
            Rectangle().fill(IC.line).frame(height: 1)
            HStack(spacing: 6) {
                Text("Предпросмотр").font(.system(size: 16, weight: .semibold))
                Text("· по вашему профилю").font(.system(size: 13)).foregroundStyle(IC.secondary)
                Spacer()
                if preview.status == .loading { ProgressView().controlSize(.small) }
                Button { preview.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .disabled(preview.status == .loading)
                    .help("Сгенерировать заново")
                    .accessibilityLabel("Сгенерировать заново")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Вопрос").font(.system(size: 13, weight: .medium))
                Text(preview.questionText).font(.system(size: 13)).foregroundStyle(IC.ink2)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(IC.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(IC.line))
            VStack(alignment: .leading, spacing: 8) {
                Text("Предлагаемый ответ").font(.system(size: 13, weight: .medium)).foregroundStyle(IC.accent)
                ScrollView {
                    Group {
                        switch preview.status {
                        case .failed(let reason):
                            Label(reason, systemImage: "exclamationmark.triangle.fill").foregroundStyle(IC.amber)
                        case .loading where preview.text.isEmpty:
                            Text("Готовлю ответ…").foregroundStyle(IC.secondary)
                        default:
                            MarkdownText(preview.text, fontSize: 14).textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if preview.status == .done {
                    Text("\(preview.source) · \(preview.words) слов").font(.system(size: 11)).foregroundStyle(IC.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(IC.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(IC.accent.opacity(0.18)))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Предпросмотр ответа")
        }
    }
}
