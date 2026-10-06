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
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 420),
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
        model.fontSize = settings.panelFontSize.pointSize
        model.hotkeys = settings.hotkeys
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
}

/// Панель, которая не становится главным окном и не активирует приложение.
final class CopilotPanel: NSPanel {
    override var canBecomeMain: Bool { false }
    override var canBecomeKey: Bool { false }
}
