import CopilotCore
import Foundation
import Observation

/// Живая сессия — COPILOT-09 R-02, R-05: Start / End, таймер с планом, предложение начать сессию при звонке.
/// Что именно включается при старте (профиль, язык, слушание, ходы) — решает AppDelegate в `onStart` / `onEnd`.
@MainActor
@Observable
final class LiveSessionController {
    private(set) var phase: SessionPhase = .none
    private(set) var config = SessionConfig()
    private(set) var clock: SessionClock?
    /// Похоже, начался звонок в этом приложении, а сессии нет.
    private(set) var detectedCall: String?
    private(set) var planWarned = false
    /// Указания на сессию из чата (R-10) — видны значками в оверлее, снимаются кликом.
    private(set) var notes: [String] = []

    /// Настройки с указаниями из чата — то, что видит модель.
    var effectiveConfig: SessionConfig { config.withSessionNotes(notes) }

    func addNote(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isActive, !t.isEmpty else { return }
        notes.append(t)
        Log.app.info("session note added count=\(self.notes.count)")
    }

    func removeNote(at index: Int) {
        guard notes.indices.contains(index) else { return }
        notes.remove(at: index)
    }

    func setAutoGenerate(_ on: Bool) { config.autoGenerate = on }

    var onStart: ((SessionConfig) -> Void)?
    var onEnd: ((SessionConfig) -> Void)?
    /// Раз в секунду — для таймера панели и меню.
    var onTick: (() -> Void)?
    /// Определять звонок, только когда это уместно (нет теста, ИИ-собеседования, записи образца голоса).
    var detectionAllowed: () -> Bool = { true }
    /// Запущенные приложения (bundle ID) — для определения звонка.
    var runningApps: () -> [String] = { [] }

    private var timer: Timer?
    private var lastPrompt: [String: Date] = [:]
    private var ticks = 0

    var isActive: Bool { phase == .active }

    func startTicking() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func start(_ c: SessionConfig) {
        guard phase.canStart else { return }
        phase = .starting
        config = c
        notes = []
        detectedCall = nil
        planWarned = false
        clock = SessionClock(startedAt: Date(), plannedMinutes: c.plannedMinutes)
        onStart?(c)
        phase = .active
        Log.app.info("session start type=\(c.type.rawValue, privacy: .public) auto=\(c.autoGenerate) save=\(c.saveTranscript) plan=\(c.plannedMinutes)")
        onTick?()
    }

    func end() {
        guard phase.canEnd else { return }
        phase = .ending
        onEnd?(config)
        let minutes = clock.map { Int(Date().timeIntervalSince($0.startedAt) / 60) } ?? 0
        clock = nil
        phase = .none
        Log.app.info("session end minutes=\(minutes)")
        onTick?()
    }

    func fail(_ message: String) {
        phase = .failed(message)
        clock = nil
        onTick?()
    }

    /// «Не сейчас»: не предлагать для этого приложения 10 минут.
    func dismissDetectedCall() {
        if let app = detectedCall { lastPrompt[app] = Date() }
        detectedCall = nil
        onTick?()
    }

    private func tick() {
        ticks += 1
        if isActive, let clock, !planWarned, clock.shouldWarn() {
            planWarned = true
            Log.app.info("session plan warning")
        }
        // Звонок проверяется раз в 3 с и только без сессии: читается флаг «микрофон занят», звук не захватывается.
        if phase == .none, ticks % 3 == 0, detectionAllowed() {
            let found = CallDetection.decide(micInUseByOthers: CallDetection.defaultInputInUse(), running: runningApps(),
                                             lastPrompt: lastPrompt)
            if found != detectedCall {
                if let found { lastPrompt[found] = Date(); Log.app.info("call detected app=\(found, privacy: .public)") }
                // Звонок закончился (микрофон освободился) — предложение убирается само.
                detectedCall = found ?? (CallDetection.defaultInputInUse() ? detectedCall : nil)
            }
        } else if phase != .none {
            detectedCall = nil
        }
        onTick?()
    }

    /// Текст для панели: «Осталось 5 мин по плану» / «План превышен на 3 мин».
    var planNotice: String? {
        guard isActive, planWarned, let left = clock?.minutesLeft() else { return nil }
        return left >= 0 ? "Осталось \(left) мин по плану" : "План превышен на \(-left) мин"
    }
}

