import AVFoundation
import CoreGraphics
import Foundation

/// Разрешения macOS — S-09, AC-13. Исполнитель их не меняет: только читает статус и показывает инструкцию.
public enum Permissions {
    /// «Запись экрана и системного звука» — нужна ScreenCaptureKit, в том числе только для звука.
    public static var screenCaptureGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Показывает системный запрос (один раз; дальше — только через Системные настройки).
    @discardableResult
    public static func requestScreenCapture() -> Bool { CGRequestScreenCaptureAccess() }

    public enum MicStatus: Sendable { case granted, denied, notDetermined }

    public static var microphone: MicStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    public static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public static let screenCaptureSettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
    public static let microphoneSettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
}
