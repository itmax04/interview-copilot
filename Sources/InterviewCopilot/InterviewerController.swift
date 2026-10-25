import AppKit
import CopilotCore

/// ИИ-собеседование (COPILOT-03): модель задаёт вопросы голосом macOS во вкладке Chrome — звук проходит настоящий
/// захват → распознавание → подсказки, как на созвоне. Владелец отвечает в микрофон; ответ распознаётся
/// и уходит модели для следующего вопроса. Страница и результаты — только на этом Mac.
@MainActor
final class InterviewerController {
    enum Stage: String, Encodable {
        case setup, thinking, speaking, answering, finishing, finished, failed
    }

    private let listening: ListeningController
    private let model: AppModel
    private let profile: () -> Profile
    private let resources: URL
    private var server: LocalTestCallServer?
    private var timer: Task<Void, Never>?
    private var generation: Task<Void, Never>?
    private var port: UInt16 = 0
    private var token = ""
    private var browserURL: URL?
    private var lastContact = Date()
    private var opening = false
    private var closing = false
    private var captureStarted = false
    private var captureTask: Task<Void, Never>?
    private var message = "Открываю собеседование…"
    private(set) var active = false

    // Сессия.
    private var stage: Stage = .setup
    private var language = "ru"
    private var questionCount = 6
    private var autoFinishSeconds: Double = 3
    private var history: [InterviewExchange] = []
    private var records: [InterviewTurnRecord] = []
    private var question: (id: String, text: String, audio: Data, provider: String?)?
    private var trial: TestCallTrial?
    private var playbackStarted = false
    private var answer: AnswerCapture?
    private var errorText: String?

    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?
    var onPermissions: (() -> Void)?
    /// Ответ владельца на вопрос закончен — в память интервью, как ответ на созвоне (COPILOT-07).
    var onOwnerAnswer: ((String) -> Void)?
    var onUsage: ((ProviderID, String, TokenUsage) -> Void)?
    var onProviderError: ((ProviderID, LLMError) -> Void)?

    init(listening: ListeningController, model: AppModel, profile: @escaping () -> Profile) {
        self.listening = listening
        self.model = model
        self.profile = profile
        resources = Bundle.main.resourceURL?.appendingPathComponent("Interviewer")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/Interviewer")
    }

    private static func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

    func start() {
        if active {
            if let browserURL { NSWorkspace.shared.open(browserURL) }
            return
        }
        guard FileManager.default.fileExists(atPath: resources.appendingPathComponent("index.html").path) else {
            let alert = NSAlert()
            alert.messageText = "ИИ-собеседование недоступно"
            alert.informativeText = "Откройте собранное приложение InterviewCopilot.app: в нём находится страница собеседования."
            alert.runModal()
            return
        }
        do {
            token = UUID().uuidString.lowercased()
            resetSession()
            message = "Открываю собеседование…"
            active = true; opening = true; closing = false; lastContact = Date()
            onBegin?()
            server = try LocalTestCallServer { [weak self] request in
                guard let self else { return .error(410, "Собеседование закрыто") }
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
            stopServer()
            onEnd?()
        }
    }

    private func resetSession() {
        generation?.cancel(); generation = nil
        stage = .setup; history = []; records = []; question = nil; trial = nil; answer = nil
        playbackStarted = false; errorText = nil
    }

    private func openBrowser(port: UInt16) {
        guard active else { return }
        self.port = port
        let url = URL(string: "http://127.0.0.1:\(port)/\(token)/")!
        browserURL = url
        let workspace = NSWorkspace.shared
        // Нужен браузер с отдельным процессом звука: так голос интервьюера идёт через захват приложения, как на созвоне.
        guard let chrome = workspace.urlForApplication(withBundleIdentifier: "com.google.Chrome") else {
            failedToStart("Для ИИ-собеседования нужен Google Chrome: его звук захватывается так же, как звук Meet.")
            return
        }
        workspace.open([url], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            Task { @MainActor in
                guard let self, self.active, !self.closing else { return }
                if let error { self.failedToStart(L("Chrome не открылся: %@", "\(error.localizedDescription)")); return }
                self.captureTask = Task { [weak self] in
                    guard let self else { return }
                    self.captureStarted = true
                    if let problem = await self.listening.beginInterviewCapture(.app(bundleID: "com.google.Chrome", name: "Chrome")) {
                        self.errorText = problem
                    }
                    guard self.active, !self.closing else { return }
                    self.opening = false
                    self.message = "Захватываю звук Chrome и микрофон"
                    if self.listening.phase == .noPermission { self.onPermissions?() }
                }
            }
        }
        if CommandLine.arguments.contains("--ai-interview") {
            print("AI_INTERVIEW_URL=\(url.absoluteString)")
            fflush(stdout)
        }
    }

    private func failedToStart(_ detail: String) {
        Task {
            await close()
            let alert = NSAlert()
            alert.messageText = "Не удалось открыть ИИ-собеседование"
            alert.informativeText = detail
            alert.runModal()
        }
    }

    // MARK: События распознавания

    /// Звук браузера: вопрос интервьюера (эталон — текст модели).
    func handleCallTranscript(_ event: TranscriptEvent) {
        guard active, stage == .speaking else { return }
        trial?.handle(event)
    }

    /// Микрофон: ответ владельца.
    func handleOwnerTranscript(_ event: TranscriptEvent) {
        guard active, stage == .answering || stage == .finishing else { return }
        answer?.handle(event, at: Self.now())
    }

    func recognitionChanged() {
        guard active, stage == .speaking else { return }
        trial?.fail("Настройки распознавания изменились во время вопроса.")
    }

    // MARK: Ход собеседования

    private func tick() {
        let now = Self.now()
        switch stage {
        case .speaking:
            trial?.tick(at: Date().timeIntervalSinceReferenceDate)
            if let result = trial?.result { questionHeard(result) }
        case .answering:
            if let a = answer, a.shouldAutoFinish(at: now, silence: autoFinishSeconds) {
                answer?.requestFinish(at: now)
                stage = .finishing
            }
        case .finishing:
            if let a = answer, a.isComplete(at: now) { answerFinished() }
        default:
            break
        }
        if Date().timeIntervalSince(lastContact) > 90 { Task { await close() } }
    }

    private func begin(language: String, count: Int, autoFinish: Double) {
        resetSession()
        self.language = InterviewerPrompt.languages.contains(language) ? language : "ru"
        questionCount = min(max(count, 1), 20)
        autoFinishSeconds = autoFinish
        nextQuestion()
    }

    private func nextQuestion() {
        stage = .thinking
        question = nil; trial = nil; answer = nil; playbackStarted = false; errorText = nil
        listening.setInterviewRoute(.call)
        var settings = model.settings
        // Вопрос интервьюера не срочный, в отличие от подсказки: перегруженной модели даём больше времени на первый токен.
        settings.firstTokenTimeout = max(settings.firstTokenTimeout, 20)
        let secrets = model.secrets
        let request = InterviewerPrompt.request(profile: profile(), language: language, history: history,
                                                questionCount: questionCount, redactPII: settings.piiFilterEnabled)
        let language = self.language
        generation = Task { [weak self] in
            let chain = await Task.detached { ChainFactory.chain(settings: settings, secrets: secrets, providers: ChainFactory.providers()) }.value
            var text = ""
            var provider: String?
            var failure: String?
            for await event in chain.run(request) {
                if Task.isCancelled { return }
                switch event {
                case .attempt(let p, let m): provider = "\(p.displayName) · \(m)"
                case .text(let t): text += t
                case .restart: text = ""
                case .providerFailed(let p, let error): self?.onProviderError?(p, error)
                case .usage(let p, let m, let u): self?.onUsage?(p, m, u)
                case .exhausted(let reason): failure = L("Модели недоступны: %@", "\(reason)")
                default: break
                }
            }
            guard let self, !Task.isCancelled, self.active else { return }
            let spoken = InterviewerPrompt.spoken(text)
            guard failure == nil, !spoken.isEmpty else {
                self.fail(failure ?? "Модель вернула пустой вопрос")
                return
            }
            do {
                let audio = try await SpeechSynth.wav(spoken, language: language)
                guard !Task.isCancelled, self.active, self.stage == .thinking else { return }
                let id = UUID().uuidString.lowercased()
                self.question = (id, spoken, audio, provider)
                let clip = TestCallClip(id: id, language: language, title: L("Вопрос %@", "\(self.history.count + 1)"), text: spoken, file: "")
                self.listening.resetTestCallPhrase()
                self.trial = TestCallTrial(clip: clip)
                self.stage = .speaking
                Log.app.notice("interviewer question ready index=\(self.history.count + 1) words=\(TranscriptComparison.words(spoken).count) wav_bytes=\(audio.count)")
            } catch {
                self.fail(L("Синтез речи: %@", "\(error)"))
            }
        }
    }

    private func questionHeard(_ result: TestCallResult) {
        guard let question else { return }
        records.append(InterviewTurnRecord(id: question.id, index: history.count + 1, language: language,
                                           question: question.text, result: result, provider: question.provider))
        Log.metrics.notice("interviewer_question index=\(self.history.count + 1) words=\(result.words) errors=\(result.errors) latency_ms=\(Int(result.latencyMs ?? -1))")
        trial = nil
        listening.setInterviewRoute(.owner)
        answer = AnswerCapture(startedAt: Self.now())
        stage = .answering
    }

    private func answerFinished() {
        guard let question, let a = answer else { return }
        let text = a.text
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { onOwnerAnswer?(text) }
        if let i = records.firstIndex(where: { $0.id == question.id }) {
            records[i].answer = text
            records[i].answerSeconds = a.speechSeconds
        }
        Log.metrics.notice("interviewer_answer index=\(self.history.count + 1) words=\(TranscriptComparison.words(text).count) seconds=\(a.speechSeconds ?? 0, format: .fixed(precision: 1))")
        history.append(InterviewExchange(question: question.text, answer: text))
        answer = nil
        if history.count >= questionCount {
            listening.setInterviewRoute(.call)
            stage = .finished
            self.question = nil
        } else {
            nextQuestion()
        }
    }

    private func fail(_ text: String) {
        errorText = text
        stage = .failed
        Log.app.error("interviewer failed: \(text, privacy: .public)")
    }

    func close() async {
        guard active, !closing else { return }
        closing = true
        server?.stop(); server = nil; timer?.cancel(); timer = nil
        generation?.cancel(); generation = nil
        trial = nil; answer = nil
        await captureTask?.value
        captureTask = nil
        if captureStarted { await listening.endInterviewCapture() }
        captureStarted = false
        active = false
        onEnd?()
    }

    /// При выходе из приложения источник восстанавливать уже не нужно.
    func stopServer() {
        active = false; server?.stop(); server = nil; timer?.cancel(); timer = nil
        generation?.cancel(); generation = nil; captureTask?.cancel(); captureTask = nil
    }

    // MARK: HTTP

    private struct Current: Encodable {
        let id: String; let index: Int; let text: String; let audio: Bool; let heard: String; let partial: String
    }
    private struct Answering: Encodable {
        let text: String; let partial: String; let speech: Bool; let finishing: Bool
    }
    private struct Snapshot: Encodable {
        let ready: Bool; let message: String; let backend: String; let source: String; let levelDB: Float
        let stage: Stage; let language: String; let count: Int; let autoFinish: Double; let index: Int
        let current: Current?; let answer: Answering?; let error: String?; let turns: [InterviewTurnRecord]
        let models: String
    }

    private func state() -> LocalHTTPResponse {
        let status: String
        if opening { status = message }
        else if listening.phase == .noPermission { status = "Разрешите «Запись экрана и системного аудио» для Interview Copilot в настройках Mac и откройте собеседование снова." }
        else if case .error(let error) = listening.phase { status = L("Захват звука: %@", "\(error)") }
        else if listening.phase == .paused { status = "Слушание на паузе. Возобновите его в меню приложения." }
        else if !listening.recognitionReady { status = listening.sttStatus }
        else { status = message }
        let current = question.map { q in
            Current(id: q.id, index: history.count + 1, text: q.text, audio: stage == .speaking,
                    heard: trial?.text ?? records.first(where: { $0.id == q.id })?.heard ?? "", partial: trial?.partial ?? "")
        }
        let answering = answer.map { Answering(text: $0.text, partial: $0.partial, speech: $0.hasSpeech, finishing: stage == .finishing) }
        let snapshot = Snapshot(ready: !opening && listening.recognitionReady, message: status, backend: listening.sttStatus,
                                source: listening.interviewRoute == .owner ? "Микрофон" : (listening.source.displayName ?? "—"),
                                levelDB: listening.levelDB, stage: stage, language: language, count: questionCount,
                                autoFinish: autoFinishSeconds, index: history.count + (stage == .finished ? 0 : 1),
                                current: current, answer: answering, error: errorText, turns: records,
                                models: model.settings.chain.map(\.displayName).joined(separator: " → "))
        return LocalHTTPResponse(body: (try? JSONEncoder().encode(snapshot)) ?? Data())
    }

    private func handle(_ request: LocalHTTPRequest) async -> LocalHTTPResponse {
        guard active, request.headers["host"] == "127.0.0.1:\(port)",
              request.headers["origin"] == nil || request.headers["origin"] == "http://127.0.0.1:\(port)" else {
            return .error(403, "Доступ только из локальной страницы")
        }
        let prefix = "/\(token)/"
        guard request.path.hasPrefix(prefix) else { return .error(404, "Не найдено") }
        let components = URLComponents(string: "http://127.0.0.1" + request.path)
        let path = String((components?.path ?? request.path).dropFirst(prefix.count))
        let query = Dictionary((components?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        lastContact = Date()
        if request.method == "GET" {
            if path.isEmpty { return page() }
            if path == "state" { return state() }
            if path.hasPrefix("audio/") {
                guard let q = question, String(path.dropFirst(6)) == q.id else { return .error(404, "Вопрос не найден") }
                return Self.ranged(q.audio, type: "audio/wav", range: request.headers["range"])
            }
        } else {
            switch path {
            case "start":
                guard !opening, listening.recognitionReady else { return .error(409, "Дождитесь готовности распознавания") }
                if stage == .setup, let problem = errorText { return .error(409, problem) }
                begin(language: query["lang"] ?? "ru", count: Int(query["count"] ?? "") ?? 6,
                      autoFinish: Double(query["auto"] ?? "") ?? 3)
                return state()
            case "ended":
                guard stage == .speaking, query["id"] == question?.id else { return .error(409, "Вопрос уже изменился") }
                trial?.endPlayback(at: Date().timeIntervalSinceReferenceDate)
                return state()
            case "answered":
                guard stage == .answering else { return .error(409, "Сейчас не время ответа") }
                answer?.requestFinish(at: Self.now())
                stage = .finishing
                return state()
            case "retry":
                // После ошибки модели или синтеза — запросить вопрос заново.
                guard stage == .failed, history.count < questionCount else { return .error(409, "Нечего повторять") }
                nextQuestion()
                return state()
            case "correct":
                guard let id = query["id"], let i = records.firstIndex(where: { $0.id == id }) else { return .error(404, "Ответ не найден") }
                let text = String(data: request.body, encoding: .utf8) ?? ""
                records[i].correct(text)
                return state()
            case "stop":
                generation?.cancel(); generation = nil
                listening.setInterviewRoute(.call)
                question = nil; trial = nil; answer = nil
                stage = records.isEmpty ? .setup : .finished
                return state()
            case "close":
                await close()
                return LocalHTTPResponse(body: Data("{}".utf8))
            default:
                break
            }
        }
        return .error(404, "Не найдено")
    }

    private func page() -> LocalHTTPResponse {
        guard let data = try? Data(contentsOf: resources.appendingPathComponent("index.html")) else { return .error(404, L("Ресурс не найден")) }
        return LocalHTTPResponse(body: localizedPage(data, resources: resources), contentType: "text/html; charset=utf-8")
    }

    private static func ranged(_ data: Data, type: String, range: String?) -> LocalHTTPResponse {
        guard let range else { return LocalHTTPResponse(body: data, contentType: type, headers: ["Accept-Ranges": "bytes"]) }
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
