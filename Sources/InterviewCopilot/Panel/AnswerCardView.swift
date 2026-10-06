import CopilotCore
import SwiftUI

/// Карточка ответа — R-16: источник, Markdown, чипы S/T/A/R, «Copy», «↑ Claude»; состояния thinking и no-match.
struct AnswerArea: View {
    let model: PanelModel

    var body: some View {
        switch model.state {
        case .thinking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Готовлю подсказку…").foregroundStyle(.white.opacity(0.75))
            }
            .accessibilityElement(children: .combine)
        case .answer:
            AnswerCardView(model: model)
        case .noMatch:
            NoMatchView(model: model)
        default:
            EmptyView()
        }
    }
}

struct AnswerCardView: View {
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(model.answerSource ?? "")
                    .font(.system(size: model.fontSize - 3, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                Spacer()
                ForEach(model.answerTags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: model.fontSize - 3, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.accentColor.opacity(0.55)))
                        .accessibilityLabel("STAR: \(tag)")
                }
            }
            ScrollView {
                MarkdownText(model.answerText, fontSize: model.fontSize)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 360)
            HStack(spacing: 8) {
                Button { model.onCopy?() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .accessibilityHint("Скопировать ответ")
                Button { model.onStrongModel?() } label: { Label("↑ \(model.strongModelName)", systemImage: "sparkles") }
                    .disabled(!model.strongModelAvailable)
                    .help(model.strongModelHint)
                    .accessibilityHint(model.strongModelHint)
                Spacer()
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
    }
}

struct NoMatchView: View {
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(model.answerSource ?? "Нет в базе", systemImage: "questionmark.circle")
                .font(.system(size: model.fontSize, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            if !model.suggestions.isEmpty {
                Text("Ближайшие карточки:")
                    .font(.system(size: model.fontSize - 3))
                    .foregroundStyle(.white.opacity(0.7))
                ForEach(model.suggestions, id: \.id) { s in
                    HStack {
                        Text(s.id)
                        Spacer()
                        Text("\(Int((s.score * 100).rounded()))%").monospacedDigit().foregroundStyle(.white.opacity(0.7))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if model.question != nil {
                Button { model.onStrongModel?() } label: { Label("↑ \(model.strongModelName)", systemImage: "sparkles") }
                    .disabled(!model.strongModelAvailable)
                    .help(model.strongModelHint)
                    .controlSize(.small)
                    .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
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
