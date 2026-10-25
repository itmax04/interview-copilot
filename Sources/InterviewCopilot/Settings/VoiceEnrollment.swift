import CopilotCore
import Foundation
import Observation
import SwiftUI

/// Запись образца голоса — COPILOT-05 R-03, S-09. Звук только в памяти: после расчёта отпечатка массив отбрасывается,
/// на диск пишется только `voice/owner.json` (192 числа и порог).
@MainActor
@Observable
final class VoiceEnrollment {
    enum State: Equatable {
        case idle
        case recording(elapsed: Double)
        case processing
        case done(String)
        case failed(String)
    }

    static let duration: Double = 25

    private(set) var state: State = .idle
    private(set) var levelDB: Float = -120
    private(set) var print: VoicePrint? = VoicePrint.load()

    private var capture: MicrophoneCapture?
    private var timer: Timer?
    private var started = Date()
    private let buffer = SampleBuffer()

    /// Накопитель звука из потока микрофона (не главный поток).
    final class SampleBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var samples: [Float] = []
        private var peak: Float = -120
        func append(_ s: [Float]) {
            lock.withLock {
                if samples.count < 16_000 * 40 { samples.append(contentsOf: s) }
                peak = max(peak, EnergyVAD.rmsDB(s[...]))
            }
        }
        func takePeak() -> Float { lock.withLock { defer { peak = -120 }; return peak } }
        func drain() -> [Float] { lock.withLock { defer { samples = [] }; return samples } }
    }

    var isRecording: Bool { if case .recording = state { true } else { false } }

    func start() {
        guard !isRecording, state != .processing else { return }
        guard Permissions.microphone == .granted else {
            state = .failed("Нет разрешения на микрофон: Системные настройки → Конфиденциальность → Микрофон")
            return
        }
        _ = buffer.drain()
        let buffer = self.buffer
        let capture = MicrophoneCapture { samples in buffer.append(samples) }
        do { try capture.start() } catch {
            state = .failed(L("Микрофон: %@", "\(error)"))
            return
        }
        self.capture = capture
        started = Date()
        state = .recording(elapsed: 0)
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        guard isRecording else { return }
        timer?.invalidate()
        timer = nil
        capture?.stop()
        capture = nil
        let samples = buffer.drain()
        state = .processing
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<VoicePrint, EnrollmentError> in
                guard VoiceEmbedder.isInstalled(in: AppPaths.models) else { return .failure(EnrollmentError(message: "Модель CAM++ не установлена: scripts/fetch-filter-models.py")) }
                guard let embedder = try? VoiceEmbedder.load(from: AppPaths.models) else { return .failure(EnrollmentError(message: "Не удалось загрузить модель CAM++")) }
                guard let print = embedder.makePrint(from: samples) else {
                    return .failure(EnrollmentError(message: "Мало речи: читайте вслух громче и ближе к микрофону (нужно не меньше 5 с речи)"))
                }
                do { try print.save() } catch { return .failure(EnrollmentError(message: L("Не удалось сохранить: %@", "\(error)"))) }
                return .success(print)
            }.value
            guard let self else { return }
            switch result {
            case .success(let print):
                self.print = print
                self.state = .done(L("Образец сохранён: %.0f с речи, порог %.2f", print.speechSeconds, print.recommendedThreshold))
                NotificationCenter.default.post(name: ListeningController.voicePrintChanged, object: nil)
            case .failure(let error):
                self.state = .failed(error.message)
            }
        }
    }

    func delete() {
        VoicePrint.delete()
        print = nil
        state = .done("Образец удалён")
        NotificationCenter.default.post(name: ListeningController.voicePrintChanged, object: nil)
    }

    private func tick() {
        levelDB = buffer.takePeak()
        let elapsed = Date().timeIntervalSince(started)
        state = .recording(elapsed: elapsed)
        if elapsed >= Self.duration { stop() }
    }

    /// Текст для чтения вслух — на языке интервью (Auto — русский).
    static func passage(for language: RecognitionLanguage) -> String {
        switch language {
        case .uk:
            "Мене звати Олексій, я розробник. Останні кілька років я працюю в продуктових командах, пишу код, роблю код-рев'ю " +
            "і допомагаю молодшим колегам. Мені подобається розбиратися в архітектурі та шукати прості рішення складних задач. " +
            "У вільний час я читаю книжки, гуляю містом і катаюся на велосипеді."
        case .en:
            "My name is Alex and I am a developer. For the last few years I have been working in product teams, writing code, " +
            "doing code reviews and mentoring junior colleagues. I enjoy software architecture and finding simple solutions " +
            "to complex problems. In my free time I read books, walk around the city and ride my bike."
        case .ru, .auto:
            "Меня зовут Алексей, я разработчик. Последние несколько лет я работаю в продуктовых командах, пишу код, провожу " +
            "код-ревью и помогаю младшим коллегам. Мне нравится разбираться в архитектуре и искать простые решения сложных задач. " +
            "В свободное время я читаю книги, гуляю по городу и катаюсь на велосипеде."
        }
    }
}

/// Понятная владельцу причина неудачной записи образца.
struct EnrollmentError: Error {
    let message: String
}

/// Раздел «Ваш голос» во вкладке Audio (COPILOT-05 R-03, R-10, S-09).
struct VoiceSettingsSection: View {
    @Bindable var model: AppModel
    @State private var enrollment = VoiceEnrollment()

    var body: some View {
        Section("Ваш голос") {
            Toggle("Только мой голос в микрофоне: чужие голоса, ТВ и видео — серым", isOn: $model.settings.ownerVoiceOnly)
            Text("Действует в режиме «Микрофон Mac» и в ответах на ИИ-собеседовании. Нужен образец голоса и модель CAM++.")
                .font(.footnote).foregroundStyle(.secondary)
            statusView
            switch enrollment.state {
            case .recording(let elapsed):
                Text(VoiceEnrollment.passage(for: model.settings.language))
                    .font(.callout)
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                ProgressView(value: min(elapsed / VoiceEnrollment.duration, 1)) {
                    Text(L("Читайте вслух обычным голосом · %.0f из %.0f с · уровень %.0f dB",
                                elapsed, VoiceEnrollment.duration, enrollment.levelDB))
                }
                Button("Готово — остановить запись") { enrollment.stop() }
                    .keyboardShortcut(.defaultAction)
            case .processing:
                ProgressView("Считаю отпечаток голоса…")
            default:
                HStack {
                    Button(enrollment.print == nil ? "Записать образец голоса (25 с)" : "Перезаписать образец") { enrollment.start() }
                        .keyboardShortcut(.defaultAction)
                    if enrollment.print != nil {
                        Button("Удалить образец", role: .destructive) { enrollment.delete() }
                    }
                }
                Text("Нажмите кнопку (или Enter) и прочитайте вслух текст, который появится. Сам звук не сохраняется — только «отпечаток» из чисел.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Toggle("Учитывать мои ответы в подсказках (на созвоне)", isOn: $model.settings.ownerSpeechContext)
            Text("Приложение расшифровывает вашу речь с микрофона и сохраняет её ответом на вопрос в памяти интервью: модель не повторяет сказанное, держит факты согласованными и опирается на них, когда интервьюер возвращается к теме. Ответы видны в истории сессии; текст уходит в модель вместе со следующими вопросами. С образцом голоса чужие голоса и эхо динамиков отсекаются.")
                .font(.footnote).foregroundStyle(.secondary)
            Toggle("Шумоподавление микрофона LocalVQE (экспериментально)", isOn: $model.settings.micNoiseSuppression)
            Text("По замеру распознавание с ним хуже (3,9% → 6,3% ошибок в словах): Parakeet сам устойчив к шуму. Для шума в комнате лучше системный Voice Isolation (Пункт управления → Режим микрофона).")
                .font(.footnote).foregroundStyle(.secondary)
            Toggle("Порог сходства — автоматически по образцу", isOn: autoThreshold)
            if model.settings.ownerVoiceThreshold > 0 {
                VStack(alignment: .leading) {
                    Text(L("Порог: %.2f — выше строже (чужие голоса отсекаются чаще, но может отсечь и вас)", model.settings.ownerVoiceThreshold))
                    Slider(value: $model.settings.ownerVoiceThreshold, in: 0.5...0.9, step: 0.01)
                }
            }
        }
    }

    @ViewBuilder private var statusView: some View {
        switch enrollment.state {
        case .done(let message): Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message): Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        default:
            if let print = enrollment.print {
                Label(L("Образец записан %@: %.0f с речи, автопорог %.2f",
                             print.createdAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)), print.speechSeconds, print.recommendedThreshold),
                      systemImage: "person.wave.2.fill")
            } else {
                Label("Образец голоса не записан", systemImage: "person.wave.2").foregroundStyle(.secondary)
            }
        }
    }

    private var autoThreshold: Binding<Bool> {
        Binding { model.settings.ownerVoiceThreshold == 0 } set: { auto in
            model.settings.ownerVoiceThreshold = auto ? 0 : Double(enrollment.print?.recommendedThreshold ?? 0.75)
        }
    }
}
