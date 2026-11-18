import Foundation
import Testing
@testable import CopilotCore
@testable import InterviewCopilot

@MainActor
struct AudioSessionLifecycleTests {
    @Test func lateMockEndCannotEndTheNextMock() async throws {
        let live = LiveSessionController()
        var callbacks: [() -> Void] = []
        live.onStart = { _ in callbacks.append(live.mockEndHandler()) }
        var config = SessionConfig()
        config.type = .mock
        live.start(config)
        let oldEnd = try #require(callbacks.first)
        oldEnd()
        live.end()
        live.start(config)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        #expect(live.isActive)
        #expect(callbacks.count == 2)
    }
}

@MainActor
private final class SyntheticCapture: CallAudioCapture {
    var source: ResolvedAudioSource?
    var isRunning: Bool { source != nil }
    var starts = 0
    var stops = 0
    var holdStart = false
    var pendingStart: CheckedContinuation<Void, Never>?
    var failNextStart = false

    func start(_ source: ResolvedAudioSource) async throws {
        if holdStart {
            holdStart = false
            await withCheckedContinuation { pendingStart = $0 }
            pendingStart = nil
        }
        if failNextStart {
            failNextStart = false
            throw AudioCaptureError.failed("Synthetic capture failure")
        }
        starts += 1
        self.source = source
    }

    func switchSource(_ source: ResolvedAudioSource) async throws { try await start(source) }
    func stop() async {
        stops += 1
        source = nil
    }
}

@MainActor
private final class SyntheticMic: MicrophoneInput {
    var isRunning = false
    func start() throws { isRunning = true }
    func stop() { isRunning = false }
}

extension AudioSessionLifecycleTests {
    private func model() -> AppModel {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(settingsStore: SettingsStore(defaults: defaults), secrets: InMemorySecretStore())
        model.settings.recognitionBackend = .whisper
        model.settings.whisperModel = "missing-synthetic-model"
        model.settings.audioSource = .allSystem
        return model
    }

    private func until(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(2)) }
        try #require(condition())
    }

    @Test func browserCompletionFromPreviousMockCannotStartCaptureOrEndItsSuccessor() async throws {
        let model = model()
        let mic = SyntheticMic()
        let listening = ListeningController(model: model, capture: SyntheticCapture(), micSource: mic,
                                            screenGranted: { true }, micPermission: { .granted })
        await listening.enterStandby().value
        defer { listening.shutdown() }
        let live = LiveSessionController()
        var launches: [(@MainActor (String?) -> Void)] = []
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/Interviewer")
        let interviewer = InterviewerController(listening: listening, model: model, profile: { Profile(name: "Test") },
                                               resources: resources, launchChrome: { _, done in launches.append(done) })
        var ends = 0
        live.onStart = { _ in
            let end = live.mockEndHandler()
            interviewer.onEnd = { ends += 1; end() }
            interviewer.start()
        }
        live.onEnd = { _ in interviewer.close() }
        var config = SessionConfig()
        config.type = .mock
        live.start(config)
        try await until { launches.count == 1 }
        live.end()
        live.start(config)
        #expect(live.phase == .ending)
        try await until { launches.count == 2 }
        launches[0]("Old browser failed")
        launches[0](nil)
        await Task.yield()
        #expect(live.isActive && interviewer.active)
        #expect(ends == 1)
        #expect(listening.interviewRoute == nil && !mic.isRunning)
        launches[1](nil)
        try await until { mic.isRunning }
        #expect(listening.interviewRoute == .call)
        await interviewer.close()?.value
        try await until { live.phase == .none }
        #expect(ends == 2)
        #expect(listening.phase == .standby && listening.interviewRoute == nil && !mic.isRunning)
    }

    @Test(arguments: [false, true])
    func endingDuringCaptureStartupRestoresStandbyAndLetsNextCallCapture(fails: Bool) async throws {
        let capture = SyntheticCapture()
        let listening = ListeningController(model: model(), capture: capture, screenGranted: { true }, micPermission: { .denied })
        defer { listening.shutdown() }
        await listening.enterStandby().value
        capture.holdStart = true
        capture.failNextStart = fails
        let opening = Task { await listening.beginTestCallCapture(.allSystem) }
        try await until { capture.pendingStart != nil }
        let standby = listening.enterStandby()
        capture.pendingStart?.resume()
        await opening.value
        await standby.value
        await listening.endTestCallCapture()
        #expect(listening.phase == .standby && !capture.isRunning)
        listening.startSession()
        try await until { listening.phase == .listening }
        #expect(capture.source == .allSystem)
    }

    @Test func immediateRestartDrainsPreviousStream() async throws {
        let capture = SyntheticCapture()
        let listening = ListeningController(model: model(), capture: capture, screenGranted: { true }, micPermission: { .denied })
        defer { listening.shutdown() }
        listening.startSession()
        try await until { capture.starts == 1 }
        listening.enterStandby()
        listening.startSession()
        try await until { capture.starts == 2 }
        #expect(capture.stops == 1 && capture.isRunning && listening.phase == .listening)
    }

    @Test func testCallRestoresActiveAndPausedSourcesAndRecoversFromRestoreError() async throws {
        let capture = SyntheticCapture()
        let listening = ListeningController(model: model(), capture: capture, screenGranted: { true }, micPermission: { .denied })
        defer { listening.shutdown() }
        listening.startSession()
        try await until { capture.isRunning }
        let absent = AudioSourceSetting.app(bundleID: "test.invalid.synthetic-call", name: "Test")
        await listening.beginTestCallCapture(absent)
        #expect(listening.phase == .idle && !capture.isRunning)
        await listening.endTestCallCapture()
        #expect(listening.phase == .listening && capture.source == .allSystem)
        listening.togglePause()
        await listening.beginTestCallCapture(.allSystem)
        await listening.endTestCallCapture()
        #expect(listening.phase == .paused && listening.source == .allSystem && !capture.isRunning)
        listening.togglePause()
        try await until { capture.isRunning }
        await listening.beginTestCallCapture(.allSystem)
        #expect(capture.isRunning)
        capture.holdStart = true
        capture.failNextStart = true
        let restoring = Task { await listening.endTestCallCapture() }
        try await until { capture.pendingStart != nil }
        #expect(listening.phase == .idle && !listening.recognitionReady)
        capture.pendingStart?.resume()
        await restoring.value
        #expect(listening.phase == .error("Synthetic capture failure") && !capture.isRunning)
        listening.startSession()
        try await until { listening.phase == .listening }
        #expect(capture.source == .allSystem)
    }
}

extension AudioSessionLifecycleTests {
    @Test func loopbackCloseAcknowledgesRequestAndDisconnectsIdleBrowser() async throws {
        var server: LocalTestCallServer?
        server = try LocalTestCallServer { _ in
            server?.stop()
            return LocalHTTPResponse(body: Data("closed".utf8))
        }
        let listener = try #require(server)
        defer { server = nil; listener.stop() }
        var readyPort: UInt16?
        var listenerError: String?
        listener.start(onReady: { readyPort = $0 }, onError: { listenerError = $0 })
        try await until { readyPort != nil || listenerError != nil }
        let port = try #require(readyPort)
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        try #require(fd >= 0)
        defer { Darwin.close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = port.bigEndian
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        try #require(connected == 0)
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        try #require(setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout))) == 0)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/close")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 3
        let (body, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200 && body == Data("closed".utf8))
        var byte: UInt8 = 0
        let count = recv(fd, &byte, 1, 0)
        #expect(count == 0 || (count == -1 && errno == ECONNRESET))
    }
}
