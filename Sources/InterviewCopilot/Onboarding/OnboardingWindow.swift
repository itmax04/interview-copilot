import AppKit
import CopilotCore
import SwiftUI

/// Мастер первого запуска — S-09, P18: разрешения → бесплатный ключ Groq → модели с прогрессом.
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

    /// P18: шаги с линиями, крупный заголовок шага, справа — значок приложения.
    var body: some View {
        VStack(spacing: 0) {
            stepper.padding(.top, 26).padding(.bottom, 18)
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(heading).font(.system(size: 32, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                    Text(subheading).font(.system(size: 17)).foregroundStyle(IC.secondary).fixedSize(horizontal: false, vertical: true)
                    Group {
                        switch state.step {
                        case .permissions: PermissionsView(listening: state.listening).frame(maxWidth: .infinity, alignment: .leading)
                        case .key: KeyStep(model: state.model)
                        case .models: ModelsStep(state: state)
                        }
                    }
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                art
            }
            .padding(.horizontal, 40)
            Spacer(minLength: 12)
            Rectangle().fill(IC.line).frame(height: 1)
            HStack {
                if state.step != .permissions {
                    Button { state.step = OnboardingState.Step(rawValue: state.step.rawValue - 1)! } label: { Label("Назад", systemImage: "chevron.left") }
                        .buttonStyle(ICButtonStyle())
                }
                Spacer()
                if state.step == .models {
                    Button("Готово") { state.finish() }
                        .buttonStyle(ICButtonStyle(primary: true))
                        .keyboardShortcut(.defaultAction)
                        .disabled(!state.allModelsPresent)
                } else {
                    Button { state.step = OnboardingState.Step(rawValue: state.step.rawValue + 1)! } label: {
                        HStack(spacing: 8) { Text("Далее"); Image(systemName: "chevron.right") }
                    }
                    .buttonStyle(ICButtonStyle(primary: true))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 860, height: 600)
        .background(IC.background)
        .foregroundStyle(IC.ink)
        .tint(IC.accent)
            }

    private var stepper: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(OnboardingState.Step.allCases, id: \.self) { s in
                let done = s.rawValue < state.step.rawValue, current = s == state.step
                if s.rawValue > 0 {
                    Rectangle().fill(done || current ? IC.green.opacity(0.8) : IC.line).frame(width: 120, height: 3).padding(.top, 17)
                }
                VStack(spacing: 8) {
                    ZStack {
                        Circle().fill(done ? IC.green : current ? IC.accent : IC.card).frame(width: 36, height: 36)
                            .overlay(Circle().strokeBorder(done || current ? .clear : IC.line))
                        if done { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white) }
                        else { Text("\(s.rawValue + 1)").font(.system(size: 15, weight: .medium)).foregroundStyle(current ? .white : IC.secondary) }
                    }
                    Text(title(s)).font(.system(size: 14, weight: current ? .semibold : .regular)).foregroundStyle(current ? IC.accent : IC.secondary)
                        .fixedSize()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Шаг \(s.rawValue + 1): \(title(s))\(current ? ", текущий" : "")")
            }
        }
    }

    private var art: some View {
        ZStack {
            ForEach(0..<3) { i in
                RoundedRectangle(cornerRadius: 50).stroke(IC.accent.opacity(0.10), lineWidth: 1)
                    .frame(width: CGFloat(170 + i * 40), height: CGFloat(170 + i * 40)).rotationEffect(.degrees(-14))
            }
            Image(nsImage: ParrotIcon.colored(size: 150))
                .shadow(color: IC.accent.opacity(0.25), radius: 24, y: 12)
        }
        .frame(width: 280, height: 300)
        .background(RadialGradient(colors: [IC.accent.opacity(0.10), .clear], center: .center, startRadius: 10, endRadius: 160))
        .accessibilityHidden(true)
    }

    private var heading: String {
        switch state.step {
        case .permissions: "Разрешите слушать звонок"
        case .key: "Подключите бесплатную модель"
        case .models: "Загрузите модели распознавания"
        }
    }

    private var subheading: String {
        switch state.step {
        case .permissions: "Звук звонка и микрофон распознаются на этом Mac."
        case .key: "Groq отвечает примерно за 1 с и бесплатен."
        case .models: "Речь и поиск по вашим ответам работают локально."
        }
    }

    private func title(_ s: OnboardingState.Step) -> String {
        switch s {
        case .permissions: "Разрешения"
        case .key: "Бесплатный ключ"
        case .models: "Модели"
        }
    }
}

/// P18: ключ Groq — первый в цепочке и бесплатный; остальные модели — позже в Настройках.
private struct KeyStep: View {
    @Bindable var model: AppModel
    @State private var input = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ключ Groq").font(.system(size: 14, weight: .medium))
            HStack(spacing: 8) {
                Image(systemName: "lock").foregroundStyle(IC.secondary)
                SecureField(saved ? "Сохранен — вставьте новый, чтобы заменить" : "Вставьте ключ gsk_…", text: $input)
                    .textFieldStyle(.plain)
                Button("Проверить") {
                    let v = input
                    input = ""
                    model.saveKey(v, for: .groq)
                    model.checkKey(.groq)
                }
                .buttonStyle(ICButtonStyle(primary: true))
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.leading, 12).padding(4)
            .background(IC.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(IC.accent.opacity(0.6), lineWidth: 1.5))
            HStack(spacing: 8) {
                Image(systemName: saved ? "checkmark.circle.fill" : "circle.dashed").foregroundStyle(saved ? IC.green : IC.secondary)
                Text(model.keyStatus[.groq] ?? (saved ? "Ключ сохранен" : "Нет ключа")).foregroundStyle(IC.secondary).font(.system(size: 12))
                Spacer()
                if saved { Button("Проверить") { model.checkKey(.groq) }.buttonStyle(.borderless) }
            }
            Link(destination: URL(string: "https://console.groq.com/keys")!) {
                Label("Получить ключ на console.groq.com", systemImage: "arrow.up.right.square").font(.system(size: 13))
            }
            HStack(spacing: 12) {
                Image(systemName: "plus").frame(width: 32, height: 32).background(IC.background, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Добавить другие модели позже").font(.system(size: 13, weight: .medium))
                    Text("Cerebras, Gemini, DeepSeek, Claude и свой API — в Настройках → Ключи моделей. Шаг можно пропустить: ваши готовые ответы работают и без ключа.")
                        .font(.system(size: 11)).foregroundStyle(IC.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(IC.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(IC.line))
        }
    }

    private var saved: Bool { model.hasKey[.groq] == true }
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
