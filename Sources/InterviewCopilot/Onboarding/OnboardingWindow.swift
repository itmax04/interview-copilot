import AppKit
import CopilotCore
import SwiftUI

/// Мастер первого запуска — S-09: разрешения → ключ Gemini → модели с прогрессом.
/// Без разрешения на запись экрана слушать нельзя, и это явно показано.
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    let state: OnboardingState

    init(model: AppModel, listening: ListeningController, onFinish: @escaping () -> Void) {
        state = OnboardingState(model: model, listening: listening, onFinish: onFinish)
    }

    func show() {
        state.refresh()
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView(state: state)))
            w.title = "Interview Copilot — первый запуск"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }
}

@MainActor
@Observable
final class OnboardingState {
    enum Step: Int, CaseIterable { case permissions, key, models }

    var step: Step = .permissions
    let model: AppModel
    let listening: ListeningController
    let onFinish: () -> Void
    var downloads: [String: Double] = [:]
    var errors: [String: String] = [:]
    var present: [String: Bool] = [:]
    let downloader: ModelDownloader

    init(model: AppModel, listening: ListeningController, onFinish: @escaping () -> Void) {
        self.model = model
        self.listening = listening
        self.onFinish = onFinish
        let listURL = Bundle.main.url(forResource: "models", withExtension: "sha256")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../models.sha256")
        let list = ModelFile.parseList((try? String(contentsOf: listURL, encoding: .utf8)) ?? "")
        downloader = ModelDownloader(directory: AppPaths.models, list: list)
    }

    var requiredModels: [String] { [model.settings.whisperModel, model.settings.embeddingModel] }
    var allModelsPresent: Bool { requiredModels.allSatisfy { present[$0] == true } }
    var isDownloading: Bool { !downloads.isEmpty }

    func refresh() {
        for f in requiredModels { present[f] = downloader.isPresent(f) }
    }

    func downloadMissing() {
        for f in requiredModels where present[f] != true && downloads[f] == nil {
            downloads[f] = 0
            errors[f] = nil
            Task {
                do {
                    try await downloader.download(f) { p in
                        Task { @MainActor in self.downloads[f] = p }
                    }
                    present[f] = true
                } catch {
                    errors[f] = "\(error)"
                }
                downloads[f] = nil
                if allModelsPresent { listening.warmUp() } // загрузка и прогрев модели распознавания (слушает только сессия)
            }
        }
    }

    var overallProgress: Double? {
        guard !downloads.isEmpty else { return nil }
        let sizes = downloads.keys.map { Double(downloader.entry($0)?.size ?? 1) }
        let done = downloads.map { Double(downloader.entry($0.key)?.size ?? 1) * $0.value }
        return done.reduce(0, +) / max(1, sizes.reduce(0, +))
    }

    func finish() {
        model.settings.onboardingCompleted = true
        onFinish()
    }
}

struct OnboardingView: View {
    @Bindable var state: OnboardingState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ForEach(OnboardingState.Step.allCases, id: \.self) { s in
                    HStack(spacing: 6) {
                        Text("\(s.rawValue + 1)")
                            .font(.caption.bold())
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(s == state.step ? Color.accentColor : Color.secondary.opacity(0.3)))
                            .foregroundStyle(.white)
                        Text(title(s)).foregroundStyle(s == state.step ? .primary : .secondary)
                    }
                }
            }
            Divider()
            Group {
                switch state.step {
                case .permissions:
                    PermissionsView(listening: state.listening)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .key:
                    KeyStep(model: state.model)
                case .models:
                    ModelsStep(state: state)
                }
            }
            .frame(minHeight: 300, alignment: .top)
            Divider()
            HStack {
                if state.step != .permissions {
                    Button("Назад") { state.step = OnboardingState.Step(rawValue: state.step.rawValue - 1)! }
                }
                Spacer()
                if state.step == .models {
                    Button("Готово") { state.finish() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!state.allModelsPresent)
                } else {
                    Button("Далее") { state.step = OnboardingState.Step(rawValue: state.step.rawValue + 1)! }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 620)
    }

    private func title(_ s: OnboardingState.Step) -> String {
        switch s {
        case .permissions: "Разрешения"
        case .key: "Ключ Gemini"
        case .models: "Модели"
        }
    }
}

private struct KeyStep: View {
    @Bindable var model: AppModel
    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ключ Gemini API нужен для подсказок на вопросы, которых нет в базе. Бесплатный ключ: aistudio.google.com/apikey.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                SecureField(model.hasKey[.gemini] == true ? "Ключ сохранён — введите новый, чтобы заменить" : "Вставьте ключ", text: $input)
                    .textFieldStyle(.roundedBorder)
                Button("Сохранить") {
                    let v = input
                    input = ""
                    model.saveKey(v, for: .gemini)
                }
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                Image(systemName: model.hasKey[.gemini] == true ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(model.hasKey[.gemini] == true ? .green : .secondary)
                Text(model.keyStatus[.gemini] ?? (model.hasKey[.gemini] == true ? "Ключ сохранён" : "Нет ключа")).foregroundStyle(.secondary)
                Spacer()
                Button("Проверить") { model.checkKey(.gemini) }.disabled(model.hasKey[.gemini] != true)
            }
            Text("Можно пропустить: база вопросов работает и без ключа. DeepSeek и Anthropic — в Settings → Keys.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

private struct ModelsStep: View {
    @Bindable var state: OnboardingState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Модели распознавания речи и поиска по базе работают на этом Mac. Загрузка один раз, файлы проверяются по SHA256.")
                .fixedSize(horizontal: false, vertical: true)
            ForEach(state.requiredModels, id: \.self) { f in
                HStack {
                    Image(systemName: state.present[f] == true ? "checkmark.circle.fill" : "arrow.down.circle")
                        .foregroundStyle(state.present[f] == true ? .green : .secondary)
                    VStack(alignment: .leading) {
                        Text(f)
                        if let size = state.downloader.entry(f)?.size {
                            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                        }
                        if let e = state.errors[f] { Text(e).font(.caption).foregroundStyle(.red) }
                    }
                    Spacer()
                    if let p = state.downloads[f] {
                        ProgressView(value: p).frame(width: 160)
                            .accessibilityLabel("Загрузка \(Int(p * 100)) процентов")
                    }
                }
            }
            if !state.allModelsPresent {
                Button("Скачать") { state.downloadMissing() }.disabled(state.isDownloading)
            } else {
                Label("Все модели на месте", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            }
        }
    }
}
