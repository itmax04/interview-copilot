import AppKit
import CopilotCore

/// Звук играет в отдельном браузере и проходит настоящий SystemAudioCapture → STT.
/// Страница и результаты доступны только на этом Mac, без провайдеров ответов.
@MainActor
final class TestCallController {
    private let listening: ListeningController
    private let resources: URL
    private var server: LocalTestCallServer?
    private var timer: Task<Void, Never>?
    private var port: UInt16 = 0
    private var token = ""
    private var browserURL: URL?
    private var clips: [TestCallClip] = []
    private var trial: TestCallTrial?
    private var results: [TestCallResult] = []
    private var lastContact = Date()
    private var opening = false
    private var closing = false
    private var captureStarted = false
    private var captureTask: Task<Void, Never>?
    private var message = "Открываю тестовый звонок…"
    private(set) var active = false
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?
    var onPermissions: (() -> Void)?

    init(listening: ListeningController) {
        self.listening = listening
        resources = Bundle.main.resourceURL?.appendingPathComponent("TestCall")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/TestCall")
    }

    func start() {
        if active {
            if let browserURL { NSWorkspace.shared.open(browserURL) }
            return
        }
        do {
            clips = try JSONDecoder().decode([TestCallClip].self, from: Data(contentsOf: resources.appendingPathComponent("clips.json")))
            guard !clips.isEmpty, FileManager.default.fileExists(atPath: resources.appendingPathComponent("index.html").path),
                  clips.allSatisfy({ FileManager.default.fileExists(atPath: resources.appendingPathComponent("audio/\($0.file)").path) }) else {
                throw CocoaError(.fileNoSuchFile)
            }
            token = UUID().uuidString.lowercased()
            trial = nil; results = []; message = "Открываю тестовый звонок…"
            active = true; opening = true; closing = false; lastContact = Date()
            onBegin?()
            server = try LocalTestCallServer { [weak self] request in
                guard let self else { return .error(410, "Тест закрыт") }
                return await self.handle(request)
            }
            server?.start(onReady: { [weak self] port in self?.openBrowser(port: port) },
                          onError: { [weak self] error in self?.failedToStart(error) })
            timer = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled, let self, self.active else { return }
                    self.tick()
                }
            }
        } catch {
            let wasActive = active
            stopServer()
            if wasActive { onEnd?() }
            let alert = NSAlert()
            alert.messageText = "Тестовый звонок недоступен"
            alert.informativeText = "Откройте собранное приложение InterviewCopilot.app: в нём находятся тестовые фразы. \(error.localizedDescription)"
            alert.runModal()
        }
    }

    private func openBrowser(port: UInt16) {
        guard active else { return }
        self.port = port
        let url = URL(string: "http://127.0.0.1:\(port)/\(token)/")!
        browserURL = url
        let workspace = NSWorkspace.shared
        let chrome = workspace.urlForApplication(withBundleIdentifier: "com.google.Chrome")
        let app = chrome ?? workspace.urlForApplication(withBundleIdentifier: "com.apple.Safari")
        guard let app else { failedToStart("Установите Chrome или Safari для тестового звонка."); return }
        let source: AudioSourceSetting = chrome != nil ? .app(bundleID: "com.google.Chrome", name: "Chrome") : .allSystem
        workspace.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            Task { @MainActor in
                guard let self, self.active, !self.closing else { return }
                if let error { self.failedToStart("Браузер не открылся: \(error.localizedDescription)"); return }
                self.captureTask = Task { [weak self] in
                    guard let self else { return }
                    self.captureStarted = true
                    await self.listening.beginTestCallCapture(source)
                    guard self.active, !self.closing else { return }
                    self.opening = false
                    self.message = chrome != nil ? "Захватываю звук Chrome" : "Захватываю системный звук. На время теста выключите другие звуки."
                    if self.listening.phase == .noPermission { self.onPermissions?() }
                }
            }
        }
        if CommandLine.arguments.contains("--test-call") {
            // Только локальный адрес теста, без ключей, профиля или истории.
            print("TEST_CALL_URL=\(url.absoluteString)")
            fflush(stdout)
        }
    }

    private func failedToStart(_ detail: String) {
        Task {
            await close()
            let alert = NSAlert()
            alert.messageText = "Не удалось открыть тестовый звонок"
            alert.informativeText = detail
            alert.runModal()
        }
    }

    func handleTranscript(_ event: TranscriptEvent) {
        guard active else { return }
        trial?.handle(event)
    }

    func recognitionChanged() {
        guard active else { return }
        trial?.fail("Настройки распознавания изменились. Повторите фразу после загрузки модели.")
        recordResult()
    }

    private func tick() {
        trial?.tick(at: Date().timeIntervalSinceReferenceDate)
        recordResult()
        if Date().timeIntervalSince(lastContact) > 90 { Task { await close() } }
    }

    private func recordResult() {
        if let result = trial?.result, !results.contains(where: { $0.trialID == result.trialID }) { results.append(result) }
    }

    func close() async {
        guard active, !closing else { return }
        closing = true
        // Остаёмся active, пока старые события сбрасываются: они не попадут в генерацию ответов.
        server?.stop(); server = nil; timer?.cancel(); timer = nil
        trial = nil
        await captureTask?.value
        captureTask = nil
        if captureStarted { await listening.endTestCallCapture() }
        captureStarted = false
        active = false
        onEnd?()
    }

    /// При выходе из приложения источник восстанавливать уже не нужно.
    func stopServer() {
        active = false; server?.stop(); server = nil; timer?.cancel(); timer = nil; captureTask?.cancel(); captureTask = nil
    }

    private struct Current: Encodable {
        let id: String; let clipID: String; let phase: String; let text: String; let partial: String
    }
    private struct Snapshot: Encodable {
        let ready: Bool; let message: String; let backend: String; let source: String; let levelDB: Float
        let clips: [TestCallClip]; let current: Current?; let results: [TestCallResult]
    }
    private func state() -> LocalHTTPResponse {
        let status: String
        if opening { status = message }
        else if listening.phase == .noPermission { status = "Разрешите «Запись экрана и системного аудио» для Interview Copilot в настройках Mac и откройте тест снова." }
        else if case .error(let error) = listening.phase { status = "Захват звука: \(error)" }
        else if listening.phase == .paused { status = "Слушание на паузе. Возобновите его в меню приложения." }
        else if !listening.recognitionReady { status = listening.sttStatus }
        else { status = message }
        let current = trial.map { Current(id: $0.id, clipID: $0.clip.id, phase: $0.phase, text: $0.text, partial: $0.partial) }
        let snapshot = Snapshot(ready: !opening && listening.recognitionReady, message: status, backend: listening.sttStatus,
                                source: listening.source.displayName ?? "—", levelDB: listening.levelDB,
                                clips: clips, current: current, results: results)
        return LocalHTTPResponse(body: (try? JSONEncoder().encode(snapshot)) ?? Data())
    }

    private func handle(_ request: LocalHTTPRequest) async -> LocalHTTPResponse {
        guard active, request.headers["host"] == "127.0.0.1:\(port)",
              request.headers["origin"] == nil || request.headers["origin"] == "http://127.0.0.1:\(port)" else {
            return .error(403, "Доступ только из локального теста")
        }
        let prefix = "/\(token)/"
        guard request.path.hasPrefix(prefix) else { return .error(404, "Не найдено") }
        let path = String(request.path.dropFirst(prefix.count))
        lastContact = Date()
        if request.method == "GET" {
            if path.isEmpty { return file("index.html", type: "text/html; charset=utf-8") }
            if path == "state" { return state() }
            if path.hasPrefix("audio/") {
                let id = String(path.dropFirst(6))
                guard let clip = clips.first(where: { $0.id == id }) else { return .error(404, "Фраза не найдена") }
                return file("audio/\(clip.file)", type: "audio/wav", range: request.headers["range"])
            }
        } else {
            if path.hasPrefix("begin/") {
                let id = String(path.dropFirst(6))
                guard !opening, listening.recognitionReady else { return .error(409, "Дождитесь готовности распознавания") }
                guard trial == nil || trial?.result != nil else { return .error(409, "Предыдущая фраза ещё не завершена") }
                guard let clip = clips.first(where: { $0.id == id }) else { return .error(404, "Фраза не найдена") }
                listening.resetTestCallPhrase()
                trial = TestCallTrial(clip: clip)
                return state()
            }
            if path.hasPrefix("ended/") {
                guard String(path.dropFirst(6)) == trial?.id else { return .error(409, "Фраза уже изменилась") }
                trial?.endPlayback(at: Date().timeIntervalSinceReferenceDate)
                return state()
            }
            if path == "cancel" { listening.resetTestCallPhrase(); trial = nil; return state() }
            if path == "close" { await close(); return LocalHTTPResponse(body: Data("{}".utf8)) }
        }
        return .error(404, "Не найдено")
    }

    private func file(_ path: String, type: String, range: String? = nil) -> LocalHTTPResponse {
        guard let data = try? Data(contentsOf: resources.appendingPathComponent(path)) else { return .error(404, "Ресурс не найден") }
        let headers = ["Accept-Ranges": "bytes"]
        guard let range else { return LocalHTTPResponse(body: data, contentType: type, headers: headers) }
        // Safari запрашивает WAV частями. Только один диапазон, без произвольных файлов.
        let parts = range.hasPrefix("bytes=") ? String(range.dropFirst(6)).split(separator: "-", omittingEmptySubsequences: false) : []
        guard parts.count == 2, let start = Int(parts[0]), start >= 0, start < data.count,
              let end = parts[1].isEmpty ? data.count - 1 : Int(parts[1]), end >= start else {
            return LocalHTTPResponse(status: 416, body: Data(), headers: ["Content-Range": "bytes */\(data.count)"])
        }
        let last = min(end, data.count - 1)
        return LocalHTTPResponse(status: 206, body: data.subdata(in: start..<(last + 1)), contentType: type,
                                 headers: ["Accept-Ranges": "bytes", "Content-Range": "bytes \(start)-\(last)/\(data.count)"])
    }
}
