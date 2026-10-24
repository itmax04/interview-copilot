import CopilotCore
import SwiftUI

/// Карточка ответа — COPILOT-09 R-07…R-10: «Вопрос: …», история ←/→, версии, состояние запроса, быстрые уточнения.
/// Показывается выбранный вопрос; новый ответ при просмотре старого — значком, без прыжка (R-09).
struct AnswerCard: View {
    let model: PanelModel
    @State private var following = true

    var body: some View {
        if let entry = model.history.current, let version = entry.current {
            VStack(alignment: .leading, spacing: 8) {
                header(entry)
                if entry.versions.count > 1 { versionTabs(entry) }
                bodyView(entry: entry, version: version)
                if version.status == .complete || version.status == .cancelled { footer(version) }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Color.white.opacity(0.08)))
            if model.history.hasUnseenNew {
                Button { model.history.selectLatest() } label: {
                    Label("Новый ответ", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: model.fontSize - 2, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityHint("Показать новый ответ")
            }
        }
    }

    private func header(_ entry: AnswerEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if model.history.entries.count > 1 {
                navButton("chevron.left", label: "Предыдущий ответ \(model.hotkey(.previousAnswer))",
                          disabled: model.history.selected == 0) { model.selectPrevious() }
                Text(model.history.position ?? "").font(.system(size: model.fontSize - 3).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                navButton("chevron.right", label: "Следующий ответ \(model.hotkey(.nextAnswer))",
                          disabled: model.history.isViewingLatest) { model.selectNext() }
            }
            (Text("Вопрос: ").foregroundColor(.white.opacity(0.6)) + Text(entry.title))
                .font(.system(size: model.fontSize - 1, weight: .semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { model.onCopy?() } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.plain)
                .help("Скопировать ответ")
                .accessibilityLabel("Скопировать ответ")
                .disabled(entry.current?.text.isEmpty ?? true)
        }
    }

    private func navButton(_ symbol: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 11, weight: .bold)) }
            .buttonStyle(.plain)
            .disabled(disabled)
            .opacity(disabled ? 0.3 : 1)
            .help(label)
            .accessibilityLabel(label)
    }

    private func versionTabs(_ entry: AnswerEntry) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(entry.versions.enumerated()), id: \.offset) { i, v in
                Button { model.history.selectVersion(i) } label: {
                    Text(versionTitle(v, index: i)).lineLimit(1)
                        .font(.system(size: max(9, model.fontSize - 4), weight: i == entry.selectedVersion ? .semibold : .regular))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(i == entry.selectedVersion ? Theme.accent.opacity(0.5) : Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func versionTitle(_ v: AnswerVersion, index: Int) -> String {
        switch v.kind {
        case .refine: "\(index + 1) · \(v.instruction ?? "уточнение")"
        case .strong: "\(index + 1) · сильная модель"
        default: "\(index + 1)"
        }
    }

    @ViewBuilder private func bodyView(entry: AnswerEntry, version: AnswerVersion) -> some View {
        switch version.status {
        case .waiting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Готовлю ответ…").foregroundStyle(.white.opacity(0.75))
            }
            // R-08: прежний ответ виден, но не выдаёт себя за новый.
            if entry.versions.count == 1, let previous = model.history.previous, let text = previous.current?.text, !text.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Предыдущий ответ · \(previous.title)").font(.system(size: model.fontSize - 4, weight: .semibold))
                    MarkdownText(text, fontSize: model.fontSize - 2).lineLimit(4)
                }
                .opacity(0.4)
                .accessibilityLabel("Предыдущий ответ")
            }
        case .streaming, .complete, .cancelled:
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        MarkdownText(version.text, fontSize: model.fontSize)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        if version.status == .streaming { Text("▍").foregroundStyle(.white.opacity(0.6)) }
                        Color.clear.frame(height: 1).id("end")
                    }
                }
                .frame(maxHeight: 360)
                .onScrollGeometryChange(for: Bool.self) { geo in
                    geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - 12
                } action: { _, atBottom in
                    following = atBottom
                }
                .onChange(of: version.text) { _, _ in
                    // Следуем за текстом, пока читатель не прокрутил вверх (R-09).
                    if following, version.status == .streaming { proxy.scrollTo("end", anchor: .bottom) }
                }
            }
            if version.status == .cancelled {
                Label("Прервано новым вопросом", systemImage: "scissors").font(.system(size: model.fontSize - 4))
                    .foregroundStyle(.white.opacity(0.5))
            }
        case .failed(let reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Повторить") { model.onRetryAnswer?(entry.id) }
                Button("Настройки моделей") { model.onOpenSettings?() }
            }
            .controlSize(.small)
        case .noMatch(let ids):
            Label(version.source.isEmpty ? "Нет в базе" : version.source, systemImage: "questionmark.circle")
                .font(.system(size: model.fontSize, weight: .semibold))
            if !ids.isEmpty {
                Text("Ближайшие карточки: " + ids.joined(separator: ", "))
                    .font(.system(size: model.fontSize - 3)).foregroundStyle(.white.opacity(0.7))
            }
            strongButton
        }
    }

    private func footer(_ version: AnswerVersion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text([version.source, version.latency.map { String(format: "%.1f с", $0) }].compactMap { $0 }.filter { !$0.isEmpty }
                    .joined(separator: " · "))
                    .font(.system(size: max(9, model.fontSize - 4))).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                Spacer()
                ForEach(version.tags, id: \.self) { tag in
                    Text(tag).font(.system(size: model.fontSize - 4, weight: .bold)).frame(width: 18, height: 18)
                        .background(Circle().fill(Theme.accent.opacity(0.55))).accessibilityLabel("STAR: \(tag)")
                }
            }
            // Крупный масштаб: кнопка сильной модели уходит на свою строку, слова в чипах не переносятся.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    chips
                    Spacer()
                    strongButton
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) { chips }
                    strongButton
                }
            }
        }
    }

    private var chips: some View {
        ForEach(["Короче", "Подробнее", "Пример"], id: \.self) { chip in
            Button(chip) { model.onQuickRefine?(chip) }
                .buttonStyle(.plain)
                .font(.system(size: max(10, model.fontSize - 3)))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.1)))
                .accessibilityHint("Новая версия ответа: \(chip.lowercased())")
        }
    }

    private var strongButton: some View {
        Button { model.onStrongModel?() } label: { Label("↑ \(model.strongModelName)", systemImage: "sparkles").lineLimit(1) }
            .fixedSize()
            .disabled(!model.strongModelAvailable)
            .help(model.strongModelHint)
            .controlSize(.small)
            .buttonStyle(.bordered)
    }
}

/// Простой Markdown: строки с **жирным**/`кодом`/списками и блоки кода ``` (ответы по скриншоту).
struct MarkdownText: View {
    let text: String
    let fontSize: Double

    init(_ text: String, fontSize: Double) {
        self.text = text
        self.fontSize = fontSize
    }

    private enum Block: Hashable {
        case text(String)
        case code(String)
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var inCode = false
        var buffer: [String] = []
        func flush() {
            guard !buffer.isEmpty else { return }
            let joined = buffer.joined(separator: "\n")
            out.append(inCode ? .code(joined) : .text(joined))
            buffer.removeAll()
        }
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                flush()
                inCode.toggle()
                continue
            }
            buffer.append(line)
        }
        flush()
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let t):
                    Text(Self.attributed(t))
                        .font(.system(size: fontSize))
                        .fixedSize(horizontal: false, vertical: true)
                case .code(let c):
                    Text(c)
                        .font(.system(size: fontSize - 1, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
                }
            }
        }
    }

    static func attributed(_ s: String) -> AttributedString {
        // Заголовки «## » и маркеры «- »/«* » превращаем в читаемый текст; остальное — inline Markdown.
        let prepared = s.components(separatedBy: "\n").map { line -> String in
            var l = line
            while l.hasPrefix("#") { l.removeFirst() }
            if l.hasPrefix("- ") || l.hasPrefix("* ") { l = "• " + l.dropFirst(2) }
            return l.trimmingCharacters(in: .init(charactersIn: " ")) == "" ? "" : l
        }.joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: prepared, options: options)) ?? AttributedString(prepared)
    }
}
