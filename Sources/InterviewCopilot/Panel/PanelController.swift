import AppKit
import CopilotCore
import SwiftUI

/// Плавающая панель: `NSPanel` nonactivating, поверх окон, на всех рабочих столах — R-16.
/// Не забирает фокус у Chrome, Zoom или Telegram (AC-09).
@MainActor
final class PanelController {
    private let panel: CopilotPanel
    let model: PanelModel

    var isVisible: Bool { panel.isVisible }

    init(model: PanelModel) {
        self.model = model
        panel = CopilotPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 540),
            styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView, .utilityWindow],
            backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.minSize = NSSize(width: AppSettings.panelWidthRange.lowerBound, height: 220)
        panel.maxSize = NSSize(width: AppSettings.panelWidthRange.upperBound, height: 1200)
        panel.setAccessibilityTitle("Interview Copilot")

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true
        let hosting = NSHostingView(rootView: PanelView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect

        // Позиция и размер запоминаются (R-16).
        if !panel.setFrameUsingName(Self.autosaveName) {
            if let screen = NSScreen.main?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: screen.maxX - 400, y: screen.maxY - 460))
            }
        }
        panel.setFrameAutosaveName(Self.autosaveName)
    }

    static let autosaveName = "InterviewCopilotPanel"

    func apply(_ settings: AppSettings) {
        panel.alphaValue = settings.panelOpacity
        model.baseFontSize = settings.panelFontSize.pointSize
        model.zoom = settings.panelZoom
        model.hotkeys = settings.hotkeys
        model.hiddenFromCapture = settings.panelHiddenFromCapture
        // R-17: исключить окно из захвата экрана. На macOS 15+ захват через ScreenCaptureKit может это игнорировать —
        // поэтому есть «Проверить видимость», а не обещание.
        panel.sharingType = settings.panelHiddenFromCapture ? .none : .readOnly
        var frame = panel.frame
        if abs(frame.width - settings.panelWidth) > 1 {
            frame.size.width = settings.panelWidth
            panel.setFrame(frame, display: true)
        }
    }

    /// Ширина, выбранная мышью, — для сохранения в настройки.
    var currentWidth: Double { panel.frame.width }

    func show() {
        // orderFrontRegardless: показать без активации приложения — фокус остаётся у браузера (AC-09).
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    // MARK: COPILOT-09 R-07, R-10, R-11, R-17

    private var expandedHeight: CGFloat?

    /// Свернуть до панели действий / развернуть; верхний край остаётся на месте.
    func setCollapsed(_ collapsed: Bool) {
        model.collapsed = collapsed
        var frame = panel.frame
        let top = frame.maxY
        if collapsed {
            expandedHeight = frame.height
            panel.minSize = NSSize(width: AppSettings.panelWidthRange.lowerBound, height: 44)
            frame.size.height = 52
        } else {
            panel.minSize = NSSize(width: AppSettings.panelWidthRange.lowerBound, height: 220)
            frame.size.height = max(220, expandedHeight ?? 420)
        }
        frame.origin.y = top - frame.height
        panel.setFrame(frame, display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    /// На следующий экран, в то же место относительно правого верхнего угла.
    func moveToNextScreen() {
        let screens = NSScreen.screens
        guard screens.count > 1, let current = panel.screen ?? NSScreen.main,
              let i = screens.firstIndex(of: current) else { return }
        let next = screens[(i + 1) % screens.count].visibleFrame
        let from = current.visibleFrame
        var frame = panel.frame
        let right = from.maxX - frame.maxX, top = from.maxY - frame.maxY
        frame.origin = NSPoint(x: next.maxX - right - frame.width, y: next.maxY - top - frame.height)
        frame.origin.x = min(max(frame.origin.x, next.minX), next.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, next.minY), next.maxY - frame.height)
        panel.setFrame(frame, display: true)
    }

    /// Чат: на время ввода панель принимает клавиатуру (не активируя приложение — звонок остаётся активным).
    func setChatFocus(_ on: Bool) {
        panel.allowsKey = on
        if on {
            show()
            panel.makeKey()
        } else {
            panel.resignKey()
        }
    }

    /// Проверка видимости (R-17): оверлей на миг заливается контрольным цветом, экран снимается через ScreenCaptureKit
    /// вместе с нашими окнами — если цвет есть в снимке, оверлей виден в захвате экрана.
    func checkVisibility() async -> String {
        guard isVisible, let screen = panel.screen ?? NSScreen.main,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return "Покажите оверлей, чтобы проверить"
        }
        model.visibilityProbe = true
        try? await Task.sleep(for: .milliseconds(250))
        defer { model.visibilityProbe = false }
        do {
            let image = try await ScreenshotService.captureDisplayIncludingOwnWindows(displayID)
            // Кадр окна в координатах снимка (начало — левый верхний угол экрана).
            let scale = CGFloat(image.width) / screen.frame.width
            let f = panel.frame
            let rect = CGRect(x: (f.minX - screen.frame.minX) * scale, y: (screen.frame.maxY - f.maxY) * scale,
                              width: f.width * scale, height: f.height * scale)
            let share = VisibilityProbe.fraction(in: image, rect: rect)
            let os = ProcessInfo.processInfo.operatingSystemVersionString
            let date = Date().formatted(date: .numeric, time: .shortened)
            Log.app.info("visibility check hidden=\(self.panel.sharingType == .none) share=\(share, format: .fixed(precision: 2))")
            switch VisibilityProbe.verdict(share: share) {
            case .visible: return "Виден в захвате экрана (\(date), \(os))"
            case .hidden: return "Не виден в захвате экрана (\(date), \(os))"
            case .unclear: return "Не удалось определить: оверлей перекрыт или снимок неполный — повторите (\(date))"
            }
        } catch {
            return "Не удалось проверить: \(error.localizedDescription)"
        }
    }
}

/// Панель, которая не становится главным окном и не активирует приложение.
final class CopilotPanel: NSPanel {
    /// Клавиатура — только пока открыт чат (COPILOT-09 R-10); иначе панель не забирает фокус у звонка (AC-09).
    var allowsKey = false
    override var canBecomeMain: Bool { false }
    override var canBecomeKey: Bool { allowsKey }
}
