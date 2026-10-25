import CoreAudio
import Foundation

/// Проверка перед стартом — COPILOT-09 R-03 (решение владельца Q12). Отдельная строка на каждое условие: исследование
/// ParakeetAI (4.2, 12.2) — «разрешение есть», «захват идёт» и «звук есть» — разные состояния, их нельзя сливать в одно.
public struct PreflightItem: Equatable, Sendable, Identifiable {
    public enum Status: Equatable, Sendable { case ok, warning, fail, checking }
    public enum Action: Equatable, Sendable { case none, openPermissions, chooseSource, openKeys, openProfile, retry }

    public var id: String
    public var title: String
    public var detail: String
    public var status: Status
    public var action: Action

    public init(id: String, title: String, detail: String, status: Status, action: Action = .none) {
        self.id = id
        self.title = title
        self.detail = detail
        self.status = status
        self.action = action
    }
}

public struct PreflightInput: Equatable, Sendable {
    public var sessionType: SessionType = .interview
    /// Источник — «Микрофон Mac» (самопроверка): звука звонка и разрешения на запись экрана не нужно.
    public var microphoneSource = false
    public var micPermission = true
    /// Пиковый уровень микрофона за проверку, dBFS; nil — ещё не измерен.
    public var micPeakDB: Float?
    public var callSourceName: String?
    public var callPeakDB: Float?
    public var callProbeSeconds = 3
    public var screenPermission = true
    public var recognizerReady = false
    public var recognizerStatus = ""
    /// Модель распознавания не загрузилась (нет файла, ошибка) — «Не готово», а не «Проверяю».
    public var recognizerFailed = false
    public var providersWithKeys: [ProviderID] = []
    public var resumeCharacters = 0
    public var materials = 0
    public var questions = 0
    public var preparedQuestions = 0

    public init() {}
}

public enum Preflight {
    /// Ниже — «тишина»: на этом уровне речь не распознаётся (порог микрофона 05 — −45 dBFS).
    public static let micSpeechDB: Float = -50
    public static let callSignalDB: Float = -60

    public static func evaluate(_ i: PreflightInput) -> [PreflightItem] {
        var out: [PreflightItem] = []
        if !i.micPermission {
            out.append(.init(id: "mic", title: L10n.t("Микрофон"), detail: L10n.t("Нет разрешения — без него приложение не слышит ваших ответов"),
                             status: i.microphoneSource ? .fail : .warning, action: .openPermissions))
        } else if let peak = i.micPeakDB {
            out.append(peak >= micSpeechDB
                ? .init(id: "mic", title: L10n.t("Микрофон"), detail: L10n.f("Слышу вас (%.0f dB)", Double(peak)), status: .ok)
                : .init(id: "mic", title: L10n.t("Микрофон"), detail: L10n.t("Тихо — скажите пару слов или проверьте вход звука"), status: .warning, action: .retry))
        } else {
            out.append(.init(id: "mic", title: L10n.t("Микрофон"), detail: L10n.t("Проверяю уровень…"), status: .checking))
        }

        if !i.microphoneSource {
            if !i.screenPermission {
                out.append(.init(id: "call", title: L10n.t("Звук звонка"), detail: L10n.t("Нет разрешения «Запись экрана и системного звука»"),
                                 status: .fail, action: .openPermissions))
            } else if let name = i.callSourceName {
                if let peak = i.callPeakDB {
                    out.append(peak >= callSignalDB
                        ? .init(id: "call", title: L10n.f("Звук звонка — %@", name), detail: L10n.f("Сигнал есть (%.0f dB)", Double(peak)), status: .ok)
                        : .init(id: "call", title: L10n.f("Звук звонка — %@", name),
                                detail: L10n.f("Нет сигнала %lld с — включите звук вкладки или дождитесь собеседника", i.callProbeSeconds),
                                status: .warning, action: .chooseSource))
                } else {
                    out.append(.init(id: "call", title: L10n.f("Звук звонка — %@", name), detail: L10n.t("Проверяю сигнал…"), status: .checking))
                }
            } else {
                out.append(.init(id: "call", title: L10n.t("Звук звонка"), detail: L10n.t("Звонок не найден: откройте Meet в Chrome, Zoom или Telegram"),
                                 status: .warning, action: .chooseSource))
            }
        }

        out.append(i.recognizerReady
            ? .init(id: "stt", title: L10n.t("Распознавание"), detail: i.recognizerStatus, status: .ok)
            : .init(id: "stt", title: L10n.t("Распознавание"), detail: i.recognizerStatus.isEmpty ? L10n.t("Загружаю модель…") : i.recognizerStatus,
                    status: i.recognizerFailed || i.recognizerStatus.hasPrefix(L10n.t("Нет модели")) || i.recognizerStatus.hasPrefix(L10n.t("Ошибка")) ? .fail : .checking))

        out.append(i.providersWithKeys.isEmpty
            ? .init(id: "keys", title: L10n.t("Модели"), detail: L10n.t("Нет ни одного ключа — ответов не будет. Бесплатный ключ Groq — в настройках"),
                    status: .fail, action: .openKeys)
            : .init(id: "keys", title: L10n.t("Модели"), detail: i.providersWithKeys.map(\.displayName).joined(separator: ", "), status: .ok))

        if i.sessionType == .interview {
            var parts: [String] = []
            parts.append(i.resumeCharacters > 0 ? L10n.t("резюме ✓") : L10n.t("резюме нет"))
            if i.materials > 0 { parts.append(L10n.f("материалов: %lld", i.materials)) }
            if i.questions > 0 { parts.append(L10n.f("вопросов: %lld (подготовлено %lld)", i.questions, i.preparedQuestions)) }
            let weak = i.resumeCharacters == 0 || i.preparedQuestions < i.questions
            out.append(.init(id: "profile", title: L10n.t("Профиль"), detail: parts.joined(separator: " · "),
                             status: weak ? .warning : .ok, action: weak ? .openProfile : .none))
        }
        return out
    }

    /// Можно начинать без «Начать всё равно»: ничего не провалено (предупреждения и проверки в процессе — не мешают).
    public static func canStart(_ items: [PreflightItem]) -> Bool { !items.contains { $0.status == .fail } }
}

/// Определение начала звонка — COPILOT-09 R-05: микрофон занят другим приложением, и запущено приложение звонка.
/// Звук при этом не захватывается (без сессии приложение не слушает, Q3) — читается только флаг CoreAudio «устройство занято».
public enum CallDetection {
    /// Приложения звонков по приоритету; браузеры — для Meet и других веб-звонков.
    public static let apps: [(bundleIDs: [String], name: String)] = [
        (["us.zoom.xos"], "Zoom"),
        (["com.microsoft.teams2", "com.microsoft.teams"], "Teams"),
        (["ru.keepcoder.Telegram", "org.telegram.desktop"], "Telegram"),
        (["com.apple.FaceTime"], "FaceTime"),
        (["com.hnc.Discord"], "Discord"),
        (["com.tinyspeck.slackmacgap"], "Slack"),
        (["com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "com.microsoft.edgemac", "com.brave.Browser",
          "org.mozilla.firefox"], "браузер (Meet)"),
    ]
    /// Не чаще раза в 10 минут на приложение.
    public static let repeatAfter: TimeInterval = 600

    /// Какой звонок предложить, или nil.
    public static func decide(micInUseByOthers: Bool, running: [String], lastPrompt: [String: Date], now: Date = Date()) -> String? {
        guard micInUseByOthers else { return nil }
        for app in apps where app.bundleIDs.contains(where: { id in running.contains { AudioSourceResolver.belongsTo($0, app: id) } }) {
            if let last = lastPrompt[app.name], now.timeIntervalSince(last) < repeatAfter { return nil }
            return app.name
        }
        return nil
    }

    /// Вход звука по умолчанию занят каким-то процессом (CoreAudio `DeviceIsRunningSomewhere`).
    public static func defaultInputInUse() -> Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return false }
        var running = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }
}
