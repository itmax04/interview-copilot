import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

public enum AudioCaptureError: Error, CustomStringConvertible {
    case noPermission
    case noDisplay
    case sourceNotRunning(String)
    case failed(String)

    public var description: String {
        switch self {
        case .noPermission: "Нет разрешения «Запись экрана и системного звука»"
        case .noDisplay: "Не найден дисплей для захвата"
        case .sourceNotRunning(let name): "Приложение \(name) не запущено"
        case .failed(let message): message
        }
    }
}

/// Захват звука выбранного приложения или всей системы через ScreenCaptureKit — R-01, R-04, ADR-0001 п. 4.
/// Звук самого помощника исключён (`excludesCurrentProcessAudio`). Выход — 16 кГц моно Float32.
public final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    public typealias SamplesHandler = @Sendable ([Float]) -> Void
    public typealias StopHandler = @Sendable (Error?) -> Void

    private let queue = DispatchQueue(label: "com.itmax04.interviewcopilot.audio-capture", qos: .userInteractive)
    private let converter = PCMConverter()
    private var stream: SCStream?
    private let onSamples: SamplesHandler
    private let onStop: StopHandler
    private let lock = NSLock()

    public init(onSamples: @escaping SamplesHandler, onStop: @escaping StopHandler) {
        self.onSamples = onSamples
        self.onStop = onStop
    }

    public var isRunning: Bool { lock.withLock { stream != nil } }

    public func start(_ source: ResolvedAudioSource) async throws {
        guard Permissions.screenCaptureGranted else { throw AudioCaptureError.noPermission }
        let filter = try await Self.makeFilter(for: source)
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = Int(PCMConverter.targetSampleRate)
        config.channelCount = 1
        // Видео не нужно: минимальный кадр раз в секунду, кадры отбрасываются.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        do {
            try await stream.startCapture()
        } catch {
            throw AudioCaptureError.failed("SCStream: \(error.localizedDescription)")
        }
        let previous = lock.withLock { () -> SCStream? in
            let old = self.stream
            self.stream = stream
            return old
        }
        try? await previous?.stopCapture()
        Log.audio.info("capture started: \(source.displayName ?? "none", privacy: .public)")
    }

    /// Смена источника без перезапуска (R-01).
    public func switchSource(_ source: ResolvedAudioSource) async throws {
        guard let stream = lock.withLock({ self.stream }) else {
            try await start(source)
            return
        }
        let filter = try await Self.makeFilter(for: source)
        try await stream.updateContentFilter(filter)
        Log.audio.info("capture source switched: \(source.displayName ?? "none", privacy: .public)")
    }

    public func stop() async {
        let stream = lock.withLock { () -> SCStream? in
            let s = self.stream
            self.stream = nil
            return s
        }
        guard let stream else { return }
        try? await stream.stopCapture()
        Log.audio.info("capture stopped")
    }

    static func makeFilter(for source: ResolvedAudioSource) async throws -> SCContentFilter {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw Permissions.screenCaptureGranted ? AudioCaptureError.failed(error.localizedDescription) : .noPermission
        }
        guard let display = content.displays.first else { throw AudioCaptureError.noDisplay }
        switch source {
        case .app(let app):
            let apps = content.applications.filter { AudioSourceResolver.belongsTo($0.bundleIdentifier, app: app.bundleID) }
            guard !apps.isEmpty else { throw AudioCaptureError.sourceNotRunning(app.name) }
            return SCContentFilter(display: display, including: apps, exceptingWindows: [])
        case .allSystem:
            let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            return SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
        case .none:
            throw AudioCaptureError.failed("Источник не выбран")
        }
    }

    // MARK: SCStreamOutput

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        let samples = converter.convert(sampleBuffer)
        if !samples.isEmpty { onSamples(samples) }
    }

    // MARK: SCStreamDelegate

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        let wasCurrent = lock.withLock { () -> Bool in
            guard self.stream === stream else { return false }
            self.stream = nil
            return true
        }
        Log.audio.error("capture stopped with error: \(error.localizedDescription, privacy: .public)")
        if wasCurrent { onStop(error) }
    }
}
