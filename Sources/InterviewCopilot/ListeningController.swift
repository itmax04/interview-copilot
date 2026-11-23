import AppKit
import CopilotCore
import Observation

@MainActor
protocol CallAudioCapture: Sendable {
    var isRunning: Bool { get }
    func start(_ source: ResolvedAudioSource) async throws
    func switchSource(_ source: ResolvedAudioSource) async throws
    func stop() async
}

extension SystemAudioCapture: CallAudioCapture {}

@MainActor
protocol MicrophoneInput: AnyObject {
    var isRunning: Bool { get }
    func start() throws
    func stop()
}

extension MicrophoneCapture: MicrophoneInput {}

/// Управление слушанием: разрешения, выбор источника, захват, пауза, микрофон владельца (R-01, R-02, R-04, S-08, AC-13).
@MainActor
@Observable
final class ListeningController {
    enum Phase: Equatable {
        case noPermission
        case idle            // нет источника
        case listening
        case paused
        /// Сессии нет (COPILOT-09 R-02): звук и микрофон не захватываются, модель распознавания загружена заранее.
        case standby
        case error(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var source: ResolvedAudioSource = .none {
        didSet { if source != oldValue { refreshAllSystemNotice() } }
    }
    /// Уровень сигнала собеседника, dBFS (debug-индикатор P-03).
    private(set) var levelDB: Float = -120
    /// Уровень микрофона владельца для индикатора оверлея (COPILOT-09 R-08).
    private(set) var micLevelDB: Float = -120
    private var micPeakSecond: Float = -120
    /// Каждые 100 мс — для индикаторов оверлея (дёшево: без перерисовки остального).
    var onLevels: (() -> Void)?
    private(set) var ownerSpeaking = false

    /// Расшифровка собеседника (R-03): итоговые реплики и текущая частичная.
    private(set) var transcript: [TranscriptLine] = []
    private(set) var partialText: String?
    private(set) var sttStatus: String = "Модель распознавания не загружена"
    /// Модель распознавания не загрузилась (нет файла, ошибка) — для проверки перед стартом, независимо от языка текста.
    private(set) var sttFailed = false
    /// Последнее событие распознавания — для определения хода (P-05).
    var onTranscript: ((TranscriptEvent) -> Void)?
    /// Владелец начал/перестал говорить; время — мс монотонных часов (R-02, S-07).
    var onOwnerSpeaking: ((Bool, Double) -> Void)?
    /// ИИ-собеседование: распознавание ответа владельца с микрофона (COPILOT-03, R-32). В расшифровку собеседника не попадает.
    var onOwnerTranscript: ((TranscriptEvent) -> Void)?

    struct TranscriptLine: Identifiable, Equatable {
        let id: Int
        let text: String
        let language: String
        /// Причина фильтра («язык de») — строка серым, в подсказки не идёт (COPILOT-05 R-06).
        var filtered: String? = nil
        /// Текст фразы ещё предварительный (COPILOT-15 R-04): вопрос хода заменит его повторным распознаванием.
        var provisional = false
    }

    /// Повторное распознавание вопроса целиком по звуку фраз хода (COPILOT-15 R-01); освобождает звук фраз (кроме опережающего запроса: звук ещё нужен ходу).
    func redecodeQuestion(utterances: [Int], turn: Int, provisional: String, release: Bool = true) async -> String? {
        guard let transcriber else { return nil }
        return await transcriber.redecodeQuestion(utterances: utterances, turn: turn, provisional: provisional, release: release)?.text
    }

    /// Итоговый текст хода заменяет строки его фраз: первая строка получает весь вопрос, остальные убираются (R-04).
    func replaceQuestionLines(utterances: [Int], with text: String) {
        guard let first = utterances.first, let i = transcript.lastIndex(where: { $0.id == first && $0.filtered == nil }) else { return }
        transcript[i] = TranscriptLine(id: first, text: text, language: transcript[i].language)
        let rest = Set(utterances.dropFirst())
        transcript.removeAll { rest.contains($0.id) && $0.filtered == nil }
        onChange?()
    }

    /// Фильтр отбросил реплику (COPILOT-05 R-06) — текст для ⌃⌥↩ «ответить всё равно».
    var onFiltered: ((String) -> Void)?
    /// Фоновый проход Whisper по истории закончил вопрос хода (COPILOT-15 R-07): (номер хода, прежний текст, уточнённый, язык).
    var onHistoryText: ((Int, String, String, String) -> Void)?

    /// После хода: поставить проход Whisper по звуку вопроса (только история и память, не подсказка).
    func submitHistoryPass(utterances: [Int], turn: Int, text: String) {
        transcriber?.submitHistoryPass(utterances: utterances, turn: turn, text: text)
    }
    /// Словарь терминов для фильтра языка: встроенный + резюме, вакансия, база (R-05).
    private var terms = TermDictionary()
    /// Silero (R-02): загружается один раз, применяется к распознаванию по настройке.
    private var speechGate: SileroSpeechGate?
    private var speechGateLoading = false

    func setTerms(_ terms: TermDictionary) { self.terms = terms }

    /// Проверка голоса владельца (COPILOT-05 R-03): отпечаток, порог, модель CAM++.
    let voiceGate = VoiceGateBox()
    private var voiceEmbedderLoading = false
    static let voicePrintChanged = Notification.Name("InterviewCopilot.voicePrintChanged")

    /// Перечитать образец и настройки голоса; модель загружается один раз в фоне.
    func voiceSettingsChanged() {
        let settings = model.settings
        voiceGate.update {
            $0.print = VoicePrint.load()
            $0.threshold = Float(settings.ownerVoiceThreshold)
        }
        updateVoiceGateActive()
        guard voiceGate.current.embedder == nil, !voiceEmbedderLoading, VoiceEmbedder.isInstalled(in: AppPaths.models) else { return }
        voiceEmbedderLoading = true
        Task { [weak self] in
            let embedder = await Task.detached(priority: .utility) { try? VoiceEmbedder.load(from: AppPaths.models) }.value
            guard let self else { return }
            self.voiceEmbedderLoading = false
            if embedder == nil { Log.stt.error("CAM++ load failed") }
            self.voiceGate.update { $0.embedder = embedder }
            self.onChange?()
        }
    }

    /// Голос проверяется в режиме «Микрофон Mac» и в ответе владельца на ИИ-собеседовании (R-01, Q13).
    /// Репетиция с собеседником — только в «Микрофон Mac» вне ИИ-собеседования: проверка включена и без «Только мой голос».
    private func updateVoiceGateActive() {
        let selfTestMic = testSource == nil && source == .microphone
        let micChannel = selfTestMic || interviewRoute == .owner
        let rehearsal = model.settings.rehearsalWithInterviewer && selfTestMic && interviewRoute == nil
        voiceGate.update {
            $0.active = (model.settings.ownerVoiceOnly || rehearsal) && micChannel
            $0.routeBySpeaker = rehearsal
        }
        // Вердикты прошлого режима или источника не должны решать судьбу новых реплик.
        if speakerRouter.rehearsal != rehearsal { speakerRouter.reset() }
        speakerRouter.rehearsal = rehearsal
        enhancerBox.update { $0.active = model.settings.micNoiseSuppression && micChannel }
        updateOwnerChannel()
    }

    /// Настройка «Учитывать мои ответы в подсказках» изменилась.
    func ownerSpeechSettingChanged() { updateOwnerChannel() }

    // MARK: Речь владельца на созвоне (COPILOT-05 R-01, R-07)

    /// Второй распознаватель: микрофон во время созвона. Тот же движок, без уточнения Whisper и без промежуточного текста.
    private var ownerTranscriber: StreamingTranscriber?
    private let ownerBuffer = AudioRingBuffer(seconds: 30)
    private let ownerBox = TranscriberBox()
    private let ownerActive = LockedFlag()
    /// Текущий активный обмен в памяти интервью — чтобы ответ владельца при перебивании крепился к нему.
    var currentExchangeID: (() -> Int?)?
    /// Фраза владельца прошла фильтры — в память интервью или повтор вопроса голосом
    /// (текст, целевой exchangeID при перебивании, флаг `interrupted`).
    var onOwnerSaid: ((String, Int?, Bool) -> Void)?
    /// Уточнение предварительно сброшенного (при перебивании) ответа владельца после re-decode.
    var onOwnerAnswerRevised: ((String, String, Int) -> Void)?
    /// Вопрос или ответ владельца по говорящему (репетиция с собеседником) и ⌃⌥A.
    private var speakerRouter = SpeakerRouter()

    /// Самопроверка: «сейчас отвечаю я» (⌃⌥A, COPILOT-06) — речь с микрофона идёт ответом в память, а не вопросом.
    private(set) var ownerAnswering = false

    /// Переключить режим ответа. Только в «Микрофон Mac»: на созвоне ответы слышны отдельным каналом сами.
    @discardableResult
    func toggleOwnerAnswering() -> Bool {
        guard testSource == nil, source == .microphone else {
            ownerAnswering = false
            return false
        }
        ownerAnswering.toggle()
        partialText = nil
        Log.app.info("owner answering \(self.ownerAnswering ? "on" : "off", privacy: .public)")
        onChange?()
        return true
    }

    /// Канал владельца работает на созвоне (звук приложения или весь системный звук), не в самопроверке и не в тестах.
    /// COPILOT-16 R-05: микрофон должен звучать — источник «Микрофон» или включён канал владельца (не тестовый звонок).
    var micExpected: Bool { phase == .listening && testSource == nil && (source == .microphone || ownerActive.value) }

    private func updateOwnerChannel() {
        let callSource: Bool = switch source {
        case .app, .allSystem: true
        default: false
        }
        let active = model.settings.ownerSpeechContext && testSource == nil && phase == .listening && callSource
            && Permissions.microphone == .granted
        guard ownerActive.value != active else { return }
        ownerActive.set(active)
        ownerTranscriber?.setPaused(!active)
        Log.audio.info("owner channel \(active ? "on" : "off", privacy: .public)")
    }

    /// Когда в звонке последний раз звучала речь (мс) и звучит ли сейчас — для отсева эха без образца голоса.
    private var callSpeaking = false
    private var callSpeechEndedAt: Double = 0
    static let echoWindowMs: Double = 1500

    private func handleOwner(_ event: TranscriptEvent) {
        // Универсальный режим «Всё сразу»: если в системном звуке тишина (звонок на телефоне или живой голос в комнате)
        // и отпечаток голоса определил ЧУЖОЙ голос на микрофоне — направляем его как вопрос собеседника.
        if case .foreignVoice(let u, let text, _, let phraseEnd) = event {
            ownerTranscriber?.questionRanges.drop(utterance: u)
            let endMs = Double(phraseEnd) / 1e6
            if !callSpeaking, endMs - callSpeechEndedAt > 2000 {
                routeForeignMicQuestion(text: text, phraseEnd: phraseEnd)
            }
            return
        }
        guard case .final(let u, let text, _, let phraseEnd, _) = event else { return }
        // Без образца голоса эхо интервьюера из динамиков неотличимо по языку: фраза микрофона, закончившаяся,
        // пока в звонке шла речь или в пределах 1,5 с после неё, считается эхом (как правило эха TurnDetector, S-07).
        if voiceGate.current.print == nil {
            let end = Double(phraseEnd) / 1e6
            if callSpeaking || end - callSpeechEndedAt < Self.echoWindowMs {
                ownerTranscriber?.questionRanges.drop(utterance: u)
                Log.metrics.notice("filtered reason=echo channel=mic")
                return
            }
        }
        // Без образца голоса — хотя бы фильтр языка микрофона: ТВ на другом языке не станет «ответом владельца».
        if voiceGate.current.print == nil, model.settings.languageFilter,
           case .drop = LanguageGate(setting: model.settings.language, terms: terms).check(text, channel: .mic) { 
            ownerTranscriber?.questionRanges.drop(utterance: u)
            return
        }
        // COPILOT-15 R-11: фразы владельца предварительные; ответ целиком распознаётся заново, когда владелец замолчал.
        ownerAssembler.phraseFinal(text: text, utterance: u, speechEnd: Double(phraseEnd) / 1e6, exchangeID: currentExchangeID?())
        startOwnerTick()
    }

    /// Фразы ответа владельца копятся до паузы (R-11).
    private var ownerAssembler = OwnerAnswerAssembler()
    private var ownerTickTask: Task<Void, Never>?
    private var ownerFinishTask: Task<Void, Never>?

    private func startOwnerTick() {
        guard ownerTickTask == nil else { return }
        ownerTickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self else { return }
                let now = Double(DispatchTime.now().uptimeNanoseconds) / 1e6
                if let answer = self.ownerAssembler.tick(at: now, speaking: self.ownerSpeaking) { self.finishOwnerAnswer(answer) }
                if !self.ownerAssembler.hasPending { break }
            }
            self?.ownerTickTask = nil
        }
    }

    /// Перебивание: экзаменатор начал говорить, пока владелец ещё не замолчал на 1 с.
    /// Немедленно синхронно фиксируем накопленные фразы владельца в его исходном обмене (`targetExchangeID`),
    /// чтобы новый доп. вопрос увидел прерванную речь, а затем доуточняем её перераспознаванием в фоне.
    func flushOwnerForInterruption() {
        guard let answer = ownerAssembler.flush() else { return }
        ownerTickTask?.cancel()
        ownerTickTask = nil
        let targetID = answer.targetExchangeID ?? currentExchangeID?()
        onOwnerSaid?(answer.provisionalText, targetID, true)
        Log.metrics.notice("owner_interrupted_flush words=\(TurnDetectorWords.count(answer.provisionalText)) phrases=\(answer.utterances.count) exchange=\(targetID ?? -1)")
        let previous = ownerFinishTask
        let generation = ownerGeneration
        let transcriber = ownerTranscriber
        ownerFinishTask = Task { [weak self] in
            await previous?.value
            let redecoded = await transcriber?.redecodeQuestion(utterances: answer.utterances, turn: -1,
                                                                provisional: answer.provisionalText, release: true)?.text
            guard let self, self.ownerGeneration == generation else { return }
            if let redecoded, redecoded != answer.provisionalText, let targetID {
                self.onOwnerAnswerRevised?(answer.provisionalText, redecoded, targetID)
            }
        }
    }

    /// Ответ закончен: звук его фраз распознаётся целиком, без Whisper; не получилось — текст фраз.
    /// Ответы идут по очереди, чтобы порядок в памяти не нарушался.
    private func finishOwnerAnswer(_ answer: OwnerAnswer) {
        let previous = ownerFinishTask
        let generation = ownerGeneration
        let transcriber = ownerTranscriber
        ownerFinishTask = Task { [weak self] in
            await previous?.value
            let redecoded = await transcriber?.redecodeQuestion(utterances: answer.utterances, turn: -1,
                                                                provisional: answer.provisionalText, release: true)?.text
            guard let self, self.ownerGeneration == generation else { return }
            let text = redecoded ?? answer.provisionalText
            self.onOwnerSaid?(text, answer.targetExchangeID, false)
            Log.metrics.notice("owner_final words=\(TurnDetectorWords.count(text)) phrases=\(answer.utterances.count) redecoded=\(redecoded != nil, privacy: .public)")
        }
    }

    /// Пауза, очистка, смена распознавателя: накопленное и ещё не готовое отбрасывается.
    private var ownerGeneration = 0
    private func resetOwnerAnswer() {
        ownerGeneration += 1
        ownerAssembler.reset()
        ownerTickTask?.cancel()
        ownerTickTask = nil
    }

    /// Шумоподавление микрофона LocalVQE (R-04, по умолчанию выключено): модель загружается при включении.
    let enhancerBox = EnhancerBox()
    private var enhancerLoading = false

    func noiseSuppressionSettingChanged() {
        updateVoiceGateActive()
        guard model.settings.micNoiseSuppression, enhancerBox.current.enhancer == nil, !enhancerLoading,
              SpeechEnhancer.isInstalled(in: AppPaths.models) else { return }
        enhancerLoading = true
        Task { [weak self] in
            let enhancer = await Task.detached(priority: .utility) { try? SpeechEnhancer.load(from: AppPaths.models) }.value
            guard let self else { return }
            self.enhancerLoading = false
            if enhancer == nil { Log.stt.error("LocalVQE load failed") }
            self.enhancerBox.update { $0.enhancer = enhancer }
        }
    }

    var voiceStatus: String {
        let s = voiceGate.current
        if !VoiceEmbedder.isInstalled(in: AppPaths.models) { return "Модель CAM++ не установлена: scripts/fetch-filter-models.py" }
        guard let print = s.print else { return "Образец голоса не записан" }
        let threshold = voiceGate.effectiveThreshold ?? print.recommendedThreshold
        return L("Образец: %.0f с речи · порог %.2f%@", print.speechSeconds, threshold, s.embedder == nil ? L(" · загружаю модель…") : "")
    }

    /// Канал для фильтра языка: звонок, весь системный звук или микрофон (R-01, Q8).
    private var gateChannel: LanguageGate.Channel {
        switch source {
        case .allSystem: .allSystem
        case .microphone: .mic
        case .app, .none: .call
        }
    }

    /// Причина отбросить реплику или nil. Тестовый звонок не фильтруется: он меряет само распознавание.
    private func filterReason(_ text: String) -> String? {
        guard testSource == nil, model.settings.languageFilter else { return nil }
        let base = model.settings.language
        let gate = LanguageGate(setting: languageLock.effectiveSetting(base), terms: terms)
        guard case .drop(let language) = gate.check(text, channel: gateChannel) else {
            // COPILOT-16 R-03: «Авто» закрепляется за языком собеседника после 3 фраз одной группы.
            if let group = languageLock.observeKept(text, base: base) {
                Log.metrics.notice("language_locked group=\(group, privacy: .public) after=\(SessionLanguageLock.phrasesToLock)")
            }
            if englishNoticeVisible { englishNoticeVisible = false }
            return nil
        }
        Log.metrics.notice("filtered reason=lang channel=\(self.gateChannel.rawValue, privacy: .public) lang=\(language, privacy: .public)")
        // R-04: две фразы подряд отброшены как английские — предлагаем разрешить английский.
        if languageLock.observeDrop(language: language, base: base) { englishNoticeVisible = true }
        return L("язык %@", language)
    }

    /// COPILOT-16 R-03/R-04: замок языка сессии и подсказка «Разрешить английский» (только состояние сессии).
    private var languageLock = SessionLanguageLock()
    private(set) var englishNoticeVisible = false

    /// Действие подсказки: английский разрешён до конца сессии (настройки не меняются).
    func allowEnglish() {
        languageLock.allowEnglish()
        englishNoticeVisible = false
        Log.metrics.notice("language_unlocked reason=owner")
    }

    /// Загрузка Silero в фоне (если включено и модель установлена) и подключение к распознаванию.
    func speechGateSettingChanged() {
        guard model.settings.neuralSpeechGate else { applySpeechGate(); return }
        guard speechGate == nil, !speechGateLoading, SileroSpeechGate.isInstalled(in: AppPaths.models) else { applySpeechGate(); return }
        speechGateLoading = true
        Task { [weak self] in
            let gate = await Task.detached(priority: .utility) { try? SileroSpeechGate.load(from: AppPaths.models) }.value
            guard let self else { return }
            self.speechGateLoading = false
            self.speechGate = gate
            if gate == nil { Log.stt.error("silero vad load failed") }
            self.applySpeechGate()
        }
    }

    var speechGateStatus: String {
        if !SileroSpeechGate.isInstalled(in: AppPaths.models) { return "Модель Silero не установлена: scripts/fetch-filter-models.py" }
        return speechGate == nil ? "Загружаю Silero…" : "Silero загружена"
    }

    /// Порог громкости по источнику: у микрофона шум комнаты громче, чем тишина в звуке звонка (COPILOT-05).
    private func applyVADConfig() {
        transcriber?.setVADConfig(source == .microphone ? StreamingTranscriber.microphoneVAD : StreamingTranscriber.Config().vad)
        updateVoiceGateActive()
    }

    private func applySpeechGate() {
        let gate = model.settings.neuralSpeechGate && testSource == nil ? speechGate : nil
        transcriber?.setSpeechGate(gate.map { g in { @Sendable samples in g.isSpeech(samples) } })
    }

    private var transcriber: StreamingTranscriber?
    private var loadingModel = false
    private var recognizerGeneration = 0
    private var stopping = false
    /// Должен ли сейчас идти захват звука (сессия, тест, ИИ-собеседование). Запуск и остановка захвата асинхронны: без
    /// этого флага остановка в конце сессии могла завершиться после старта следующей (и наоборот), и фаза расходилась
    /// с тем, что реально захватывается. Каждая асинхронная операция в конце сверяется с ним (COPILOT-12).
    private var captureWanted = false

    /// Буфер последних 30 с звука собеседника (R-04). Читает распознавание (P-04).
    let buffer = AudioRingBuffer(seconds: 30)
    private var capture: (any CallAudioCapture)?
    private var captureUpdate: Task<Void, Never>?
    private let captureEpoch = DeliveryEpoch()
    private var restartTask: Task<Void, Never>?
    private let screenGranted: () -> Bool
    private let micPermission: () -> Permissions.MicStatus
    /// Микрофон как источник (режим самопроверки, запрос владельца 2026-10-07).
    private var micSource: (any MicrophoneInput)?
    private var testSource: AudioSourceSetting?
    private var effectiveSource: AudioSourceSetting { testSource ?? sessionSourceOverride ?? model.settings.audioSource }

    // COPILOT-16 R-06: предупреждение о «Всём системном звуке» и действие «Только звонок» (источник только на сессию).
    private var sessionSourceOverride: AudioSourceSetting?
    private var allSystemDismissed = false
    private(set) var allSystemNotice: AudioSourceResolver.AllSystemNotice?

    private func refreshAllSystemNotice() {
        let notice = allSystemDismissed ? nil : AudioSourceResolver.allSystemNotice(for: source, running: Self.runningApps())
        if notice != allSystemNotice { allSystemNotice = notice }
    }

    func dismissAllSystemNotice() {
        allSystemDismissed = true
        refreshAllSystemNotice()
    }

    /// «Только звонок»: на эту сессию захватываем приложение звонка; настройка источника не меняется.
    func switchToCallOnly() {
        guard let app = allSystemNotice?.callApp else { return }
        sessionSourceOverride = .app(bundleID: app.bundleID, name: app.name)
        Log.audio.notice("source_call_only app=\(app.name, privacy: .public)")
        updateCapture(restart: false)
    }
    private var usesMicrophone: Bool { effectiveSource == .microphone }
    var recognitionReady: Bool { transcriber != nil && phase == .listening }
    private var pausedBeforeTest = false
    private var standbyBeforeTest = false
    private var transcriptBeforeTest: [TranscriptLine] = []
    private let deliveryEpoch = DeliveryEpoch()
    /// Какой источник сейчас идёт в распознавание во время ИИ-собеседования; nil — обычная работа.
    private let route = AudioRouteBox()
    private(set) var interviewRoute: AudioRoute?

    /// ИИ-собеседование (COPILOT-03): звук браузера — вопрос интервьюера, как на созвоне;
    /// микрофон — ответ владельца. В распознавание одновременно идёт только один источник.
    func beginInterviewCapture(_ source: AudioSourceSetting) async -> String? {
        if micPermission() == .notDetermined { _ = await Permissions.requestMicrophone() }
        guard !Task.isCancelled, micPermission() == .granted else { return "Нет разрешения на микрофон для Interview Copilot" }
        route.set(.call)
        interviewRoute = .call
        await beginTestCallCapture(source)
        guard !Task.isCancelled else { return nil }
        let micSource = self.micSource ?? makeMicSource()
        self.micSource = micSource
        do { try micSource.start() } catch { return L("Микрофон: %@", "\(error)") }
        let t = Double(DispatchTime.now().uptimeNanoseconds) / 1e6
        onOwnerSpeaking?(false, t)
        return nil
    }

    /// Переключение «вопрос → ответ» и обратно. Незаконченные фрагменты прошлого источника отбрасываются.
    func setInterviewRoute(_ value: AudioRoute) {
        guard interviewRoute != nil, interviewRoute != value else { return }
        route.set(value)
        interviewRoute = value
        updateVoiceGateActive()
        partialText = nil
        resetTestCallPhrase()
    }

    func endInterviewCapture() async {
        guard interviewRoute != nil else { return }
        micSource?.stop()
        route.set(nil)
        interviewRoute = nil
        updateVoiceGateActive()
        await endTestCallCapture()
    }

    func beginTestCallCapture(_ source: AudioSourceSetting) async {
        if testSource == nil {
            pausedBeforeTest = phase == .paused
            standbyBeforeTest = phase == .standby
            transcriptBeforeTest = transcript
            transcript = []
        }
        deliveryEpoch.advance()
        captureWanted = true
        testSource = source
        mic?.stop()
        ownerSpeaking = false
        setPhase(.idle)
        transcriber?.setLanguage(nil)
        transcriber?.setPromptProvider(nil)
        loadRecognizer()
        startLevelReporting()
        await updateCapture(restart: true).value
    }

    func resetTestCallPhrase() {
        transcriber?.setPaused(true)
        deliveryEpoch.advance()
        if phase == .listening { transcriber?.setPaused(false) }
    }

    func endTestCallCapture() async {
        deliveryEpoch.advance()
        testSource = nil
        transcriber?.setLanguage(model.settings.language.whisperCode)
        transcriber?.setPromptProvider(promptProvider)
        transcript = transcriptBeforeTest
        transcriptBeforeTest = []
        partialText = nil
        captureWanted = !standbyBeforeTest && !pausedBeforeTest
        if standbyBeforeTest || pausedBeforeTest {
            source = AudioSourceResolver.resolve(effectiveSource, running: Self.runningApps())
            setPhase(standbyBeforeTest ? .standby : .paused)
            await updateCapture(restart: false).value
        } else {
            // The browser stream may still deliver audio while its replacement is starting.
            setPhase(.idle)
            await updateCapture(restart: true).value
        }
    }

    private var mic: MicActivityDetector?
    private let model: AppModel
    private var observers: [NSObjectProtocol] = []
    private var levelTask: Task<Void, Never>?
    private let levelMeter = LevelMeter()

    /// Вызывается при смене состояния (перестройка меню и панели).
    var onChange: (() -> Void)?

    init(model: AppModel, capture: (any CallAudioCapture)? = nil, micSource: (any MicrophoneInput)? = nil,
         screenGranted: @escaping () -> Bool = { Permissions.screenCaptureGranted },
         micPermission: @escaping () -> Permissions.MicStatus = { Permissions.microphone }) {
        self.capture = capture
        self.screenGranted = screenGranted
        self.micPermission = micPermission
        self.micSource = micSource
        self.model = model
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.runningAppsChanged() }
            })
        }
    }

    var listeningStatus: ListeningStatus {
        switch phase {
        case .noPermission: .noPermission
        case .listening: .listening(source: source.displayName ?? "—")
        case .paused: .paused(source: source.displayName ?? "—")
        case .standby: .noSession
        case .idle, .error: .idle
        }
    }

    static func runningApps() -> [RunningAppInfo] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier,
                  id != Bundle.main.bundleIdentifier else { return nil }
            return RunningAppInfo(bundleID: id, name: app.localizedName ?? id)
        }
    }

    /// Без сессии: всё остановлено, распознавание загружено заранее — старт сессии не ждёт модель (COPILOT-09 R-02).
    @discardableResult
    func enterStandby() -> Task<Void, Never> {
        if testSource != nil { standbyBeforeTest = true }
        deliveryEpoch.advance()
        stopping = false
        captureWanted = false
        callSpeaking = false
        partialText = nil
        ownerAnswering = false
        setPhase(.standby)
        loadRecognizer()
        return updateCapture(restart: false)
    }

    /// Clear в оверлее (COPILOT-09 Q13): расшифровка на экране и «последние реплики» для следующего ответа.
    func clearTranscript() {
        transcript = []
        partialText = nil
        onChange?()
    }

    /// Загрузить модель распознавания заранее, ничего не захватывая.
    func warmUp() { loadRecognizer() }

    /// Начало сессии: расшифровка с чистого листа, захват по источнику из настроек.
    func startSession() {
        deliveryEpoch.advance()
        speakerRouter.reset()
        transcript = []
        partialText = nil
        callSpeaking = false
        languageLock.reset()
        englishNoticeVisible = false
        sessionSourceOverride = nil
        allSystemDismissed = false
        start()
    }

    /// Запуск при старте приложения и после выдачи разрешений.
    func start() {
        stopping = false
        captureWanted = true
        setPhase(.idle)
        // Микрофону разрешение «Запись экрана» не нужно.
        guard usesMicrophone || screenGranted() else {
            captureWanted = false
            updateCapture(restart: false)
            setPhase(.noPermission)
            Log.audio.notice("no screen capture permission")
            return
        }
        loadRecognizer()
        startLevelReporting()
        updateCapture(restart: true)
    }

    func togglePause() {
        switch phase {
        case .listening:
            captureWanted = false
            // Пауза глотает «собеседник замолчал»: без сброса фразы владельца считались бы эхом до следующей реплики звонка.
            callSpeaking = false
            partialText = nil
            setPhase(.paused)
            updateCapture(restart: false)
        case .paused:
            captureWanted = true
            updateCapture(restart: true)
        default:
            break
        }
    }

    /// Смена источника из меню или настроек — без перезапуска приложения (R-01).
    func sourceSettingChanged() {
        guard phase != .paused, phase != .standby else { return }
        if phase == .noPermission {
            if usesMicrophone { start() }
            return
        }
        updateCapture(restart: false)
    }

    private func runningAppsChanged() {
        guard phase != .paused, phase != .noPermission, phase != .standby else { return }
        let resolved = AudioSourceResolver.resolve(effectiveSource, running: Self.runningApps())
        if resolved != source { updateCapture(restart: false) } else { refreshAllSystemNotice() }
    }

    /// A system stream can finish starting after cancellation. Drain that operation before touching the next stream.
    @discardableResult
    private func updateCapture(restart: Bool) -> Task<Void, Never> {
        captureEpoch.advance()
        restartTask?.cancel()
        let wantsAudio = captureWanted
        let previous = captureUpdate
        previous?.cancel()
        let update = Task {
            await previous?.value
            if wantsAudio {
                guard !Task.isCancelled else { return }
                await applySource(restart: restart)
            } else {
                micSource?.stop()
                mic?.stop()
                await capture?.stop()
                buffer.clear()
            }
        }
        captureUpdate = update
        return update
    }

    private func applySource(restart: Bool, attempt: Int = 0) async {
        guard captureWanted else { return }
        let resolved = AudioSourceResolver.resolve(effectiveSource, running: Self.runningApps())
        if resolved == .microphone {
            // Режим самопроверки: системный звук не нужен, микрофон — «собеседник»; определение речи владельца выключено.
            await capture?.stop()
            guard !Task.isCancelled else { return }
            mic?.stop()
            ownerSpeaking = false
            onOwnerSpeaking?(false, Double(DispatchTime.now().uptimeNanoseconds) / 1e6)
            source = resolved
            applyVADConfig()
            let micSource = self.micSource ?? makeMicSource()
            self.micSource = micSource
            do {
                try micSource.start()
                guard captureWanted else { micSource.stop(); return }
                setPhase(.listening)
            } catch {
                setPhase(.error(String(describing: error)))
            }
            return
        }
        // Вернулись к созвону: микрофон снова только для определения речи владельца.
        if interviewRoute == nil, micSource?.isRunning == true { micSource?.stop() }
        guard screenGranted() else {
            await capture?.stop()
            guard !Task.isCancelled else { return }
            setPhase(.noPermission)
            return
        }
        startMic()
        source = resolved
        if resolved != .microphone { ownerAnswering = false }
        applyVADConfig()
        if resolved == .none {
            await capture?.stop()
            if !Task.isCancelled { setPhase(.idle) }
            return
        }
        let capture = self.capture ?? makeCapture()
        self.capture = capture
        do {
            if restart || !capture.isRunning {
                try await capture.start(resolved)
            } else {
                try await capture.switchSource(resolved)
            }
            // Сессию закончили или поставили на паузу, пока захват запускался, — не слушаем.
            guard !Task.isCancelled, captureWanted else { await capture.stop(); return }
            setPhase(.listening)
        } catch {
            // A failed switch or replacement can leave the previous (temporary) source recording.
            await capture.stop()
            guard !Task.isCancelled else { return }
            switch error {
            case AudioCaptureError.noPermission:
                setPhase(.noPermission)
            case AudioCaptureError.sourceNotRunning where attempt < 8:
                try? await Task.sleep(for: .milliseconds(500))
                guard !stopping, !Task.isCancelled else { return }
                await applySource(restart: restart, attempt: attempt + 1)
            default:
                if case AudioCaptureError.sourceNotRunning = error { source = .none }
                Log.audio.error("capture start failed: \(String(describing: error), privacy: .public)")
                setPhase(.error(String(describing: error)))
            }
        }
    }

    // MARK: Проверка перед стартом (COPILOT-09 R-03)

    /// Пиковый уровень микрофона за `seconds`; nil — нет разрешения или микрофон не запустился.
    func probeMicrophone(seconds: Double = 2) async -> Float? {
        guard Permissions.microphone == .granted else { return nil }
        let meter = LevelMeter()
        let probe = MicrophoneCapture { samples in meter.add(samples) }
        do { try probe.start() } catch { return nil }
        try? await Task.sleep(for: .seconds(seconds))
        probe.stop()
        return meter.takeDB()
    }

    /// Источник звонка по настройке и пиковый уровень его звука за `seconds` (только уровень — без распознавания).
    func probeCall(seconds: Double = 3) async -> (name: String?, peak: Float?) {
        let resolved = AudioSourceResolver.resolve(model.settings.audioSource, running: Self.runningApps())
        guard resolved != .none, resolved != .microphone, Permissions.screenCaptureGranted else { return (resolved.displayName, nil) }
        let meter = LevelMeter()
        let probe = SystemAudioCapture(onSamples: { samples in meter.add(samples) }, onStop: { _ in })
        do { try await probe.start(resolved) } catch { return (resolved.displayName, nil) }
        try? await Task.sleep(for: .seconds(seconds))
        await probe.stop()
        return (resolved.displayName, meter.takeDB())
    }

    var recognizerLoaded: Bool { transcriber != nil }

    /// Остановка и освобождение модели перед выходом.
    func shutdown() {
        stopping = true
        captureWanted = false
        recognizerGeneration += 1
        transcriberBox.set(nil)
        transcriber?.setPaused(true)
        transcriber = nil
        ownerBox.set(nil)
        ownerTranscriber?.setPaused(true)
        ownerTranscriber = nil
        resetOwnerAnswer()
        micSource?.stop()
        mic?.stop()
        updateCapture(restart: false)
    }

    /// Подсказка распознаванию из базы (настройка Audio → «Подсказывать словарь базы»).
    func setRecognitionPrompt(_ provider: (@Sendable (String) -> String?)?) {
        promptProvider = provider
        transcriber?.setPromptProvider(testSource == nil ? provider : nil)
        ownerTranscriber?.setPromptProvider(testSource == nil ? provider : nil)
    }

    private var promptProvider: (@Sendable (String) -> String?)?

    /// Язык распознавания из настроек (R-03).
    func languageSettingChanged() {
        transcriber?.setLanguage(testSource == nil ? model.settings.language.whisperCode : nil)
        ownerTranscriber?.setLanguage(model.settings.language.whisperCode)
    }

    /// Смена модели или режима точности: старая очередь больше не выдаёт текст.
    func recognitionSettingsChanged() {
        recognizerGeneration += 1
        transcriberBox.set(nil)
        transcriber?.setPaused(true)
        transcriber = nil
        ownerBox.set(nil)
        ownerTranscriber?.setPaused(true)
        ownerTranscriber = nil
        resetOwnerAnswer()
        partialText = nil
        loadRecognizer()
    }

    /// Загрузка выбранного локального движка в фоне. Без модели слушание идёт, но текста нет.
    private func loadRecognizer() {
        guard !stopping, transcriber == nil, !loadingModel else { return }
        let useParakeet = model.settings.recognitionBackend == .parakeet
            && FileManager.default.fileExists(atPath: AppPaths.parakeetModels.path)
        let path = useParakeet ? AppPaths.parakeetModels.path : AppPaths.model(model.settings.whisperModel).path
        guard FileManager.default.fileExists(atPath: path) else {
            sttStatus = L("Нет модели распознавания: %@ (scripts/fetch-models.sh)", model.settings.whisperModel)
            sttFailed = true
            Log.stt.error("whisper model missing: \(self.model.settings.whisperModel, privacy: .public)")
            return
        }
        loadingModel = true
        sttStatus = "Загружаю модель распознавания…"
        sttFailed = false
        let buffer = self.buffer
        let reducedContext = !model.settings.recognitionAccuracy
        // Гибрид для украинского (R-35): итог украинской фразы — Whisper turbo с языком uk, если файл модели есть.
        let turbo = AppPaths.model("ggml-large-v3-turbo-q5_0.bin").path
        let hybrid = useParakeet && (model.settings.ukrainianWhisperFinal || model.settings.whisperReviseAllLanguages)
            && FileManager.default.fileExists(atPath: turbo)
        let reviseAll = model.settings.whisperReviseAllLanguages
        let generation = recognizerGeneration
        Task { [weak self] in
            let result: Result<any SpeechRecognizer, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    let engine: any SpeechRecognizer
                    if useParakeet {
                        let parakeet = try await ParakeetEngine.load(from: URL(fileURLWithPath: path))
                        engine = hybrid ? HybridRecognizer(primary: parakeet, reviseAllLanguages: reviseAll,
                                                           loadVerifier: { try WhisperEngine(modelPath: turbo) }) : parakeet
                    } else { engine = try WhisperEngine(modelPath: path) }
                    return .success(engine)
                } catch { return .failure(error) }
            }.value
            self?.recognizerLoaded(result, path: path, buffer: buffer, reducedContext: reducedContext, generation: generation)
        }
    }

    private func recognizerLoaded(_ result: Result<any SpeechRecognizer, Error>, path: String, buffer: AudioRingBuffer, reducedContext: Bool, generation: Int) {
        loadingModel = false
        guard !stopping else { return }
        guard generation == recognizerGeneration else { loadRecognizer(); return }
        switch result {
        case .success(let engine):
            var config = StreamingTranscriber.Config()
            config.finalReducedContext = reducedContext
            if source == .microphone { config.vad = StreamingTranscriber.microphoneVAD }
            let deliveryEpoch = self.deliveryEpoch
            let t = StreamingTranscriber(recognizer: engine, buffer: buffer, config: config) { [weak self] event in
                let eventEpoch = deliveryEpoch.current()
                Task { @MainActor in
                    guard let self, self.recognizerGeneration == generation, deliveryEpoch.current() == eventEpoch else { return }
                    self.handle(event)
                }
            }
            t.setLanguage(testSource == nil ? model.settings.language.whisperCode : nil)
            t.setPromptProvider(testSource == nil ? promptProvider : nil)
            let gate = model.settings.neuralSpeechGate && testSource == nil ? speechGate : nil
            t.setSpeechGate(gate.map { g in { @Sendable samples in g.isSpeech(samples) } })
            let voiceGate = self.voiceGate
            t.setVoiceGate { samples in voiceGate.check(samples) }
            let enhancerBox = self.enhancerBox
            t.setAudioEnhancer { samples in enhancerBox.enhance(samples) }
            t.setPaused(phase != .listening)
            t.setHistoryHandler { [weak self] turn, old, result in
                Task { @MainActor in
                    guard let self, self.recognizerGeneration == generation else { return }
                    self.onHistoryText?(turn, old, result.text, result.language)
                }
            }
            transcriberBox.set(t)
            transcriber = t
            var ownerConfig = StreamingTranscriber.Config()
            ownerConfig.partialInterval = 3600        // промежуточный текст владельца не нужен
            ownerConfig.vad = StreamingTranscriber.microphoneVAD
            let ot = StreamingTranscriber(recognizer: engine, buffer: ownerBuffer, config: ownerConfig) { [weak self] event in
                let epoch = deliveryEpoch.current()
                Task { @MainActor in
                    guard let self, self.recognizerGeneration == generation, deliveryEpoch.current() == epoch else { return }
                    self.handleOwner(event)
                }
            }
            ot.setLanguage(model.settings.language.whisperCode)
            ot.setPromptProvider(testSource == nil ? promptProvider : nil)
            ot.setSpeechGate(gate.map { g in { @Sendable samples in g.isSpeech(samples) } })
            // Эхо интервьюера из динамиков и чужие голоса отсекает отпечаток голоса (решение исполнителя, этап 4).
            ot.setVoiceGate { samples in voiceGate.check(samples, ignoringActive: true, allowRouting: false) }
            ot.setPaused(!ownerActive.value)
            ownerBox.set(ot)
            ownerTranscriber = ot
            updateOwnerChannel()
            let name = engine is HybridRecognizer ? (model.settings.whisperReviseAllLanguages ? L("Parakeet v3 + уточнение Whisper turbo") : "Parakeet v3 + Whisper turbo (UK)")
                : engine.nativeMultilingual ? "Parakeet v3" : (path as NSString).lastPathComponent
            let fallback = model.settings.recognitionBackend == .parakeet && !engine.nativeMultilingual
                ? L(" (Parakeet не установлен, используется Whisper)") : ""
            sttStatus = L("Распознавание: %@", name + fallback)
            sttFailed = false
        case .failure(let error):
            sttStatus = L("Ошибка модели: %@", "\(error)")
            sttFailed = true
        }
        onChange?()
    }

    private func handle(_ event: TranscriptEvent) {
        if interviewRoute == .owner {
            onOwnerTranscript?(event)
            return
        }
        if case .speaker(let u, let owner, _) = event {
            speakerRouter.noteSpeaker(utterance: u, owner: owner)
            return
        }
        // Самопроверка: ответ владельца (⌃⌥A или его голос в репетиции с собеседником) — в память; для хода — как шум.
        if source == .microphone {
            switch event {
            case .final(let u, let text, _, let phraseEnd, _):
                let route = speakerRouter.route(utterance: u, ownerAnswering: ownerAnswering)
                speakerRouter.forget(utterance: u)
                if route == .ownerAnswer {
                    recordOwnerAnswer(utterance: u, text: text, phraseEnd: phraseEnd)
                    return
                }
            case .discarded(let u, _), .foreignVoice(let u, _, _, _):
                speakerRouter.forget(utterance: u)
            default:
                break
            }
        }
        if ownerAnswering, source == .microphone {
            if case .foreignVoice(_, _, _, let phraseEnd) = event { onTranscript?(.discarded(utterance: 0, phraseEnd: phraseEnd)) }
            return   // промежуточный текст ответа не показываем как реплику интервьюера
        }
        switch event {
        case .speechStarted:
            callSpeaking = true
            flushOwnerForInterruption()
        case .speechEnded(_, let at):
            callSpeaking = false
            callSpeechEndedAt = Double(at) / 1e6
        case .partial(_, let text):
            partialText = text
            onChange?()
        case .final(let u, let text, let language, let phraseEnd, _):
            partialText = nil
            if let reason = filterReason(text) {
                // R-06: серой строкой; для хода и истории — как отброшенный шум.
                transcript.append(TranscriptLine(id: u, text: text, language: language, filtered: reason))
                if transcript.count > 50 { transcript.removeFirst(transcript.count - 50) }
                onChange?()
                onFiltered?(text)
                onTranscript?(.discarded(utterance: u, phraseEnd: phraseEnd))
                return
            }
            transcript.append(TranscriptLine(id: u, text: text, language: language, provisional: true))
            if transcript.count > 50 { transcript.removeFirst(transcript.count - 50) }
            onChange?()
        case .discarded, .speaker:
            break
        case .foreignVoice(let u, let text, let similarity, let phraseEnd):
            // R-03, R-06: чужой голос — серой строкой; для хода — как шум.
            partialText = nil
            transcript.append(TranscriptLine(id: u, text: text, language: "", filtered: L("чужой голос %.2f", similarity)))
            if transcript.count > 50 { transcript.removeFirst(transcript.count - 50) }
            onChange?()
            onFiltered?(text)
            onTranscript?(.discarded(utterance: u, phraseEnd: phraseEnd))
            return
        }
        onTranscript?(event)
    }

    /// Чужой голос в микрофоне при тишине в системном звуке (телефон на громкой связи или очный экзамен) —
    /// попадает в ленту расшифровки и на определение хода без переключения источника.
    private func routeForeignMicQuestion(text: String, phraseEnd: UInt64) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let lineID = -Int(phraseEnd & 0x7FFF_FFFF)
        if let reason = filterReason(trimmed) {
            onFiltered?(trimmed)
            transcript.append(TranscriptLine(id: lineID, text: trimmed, language: "", filtered: reason))
            if transcript.count > 50 { transcript.removeFirst(transcript.count - 50) }
            onChange?()
            return
        }
        flushOwnerForInterruption()
        transcript.append(TranscriptLine(id: lineID, text: trimmed, language: "", provisional: false))
        if transcript.count > 50 { transcript.removeFirst(transcript.count - 50) }
        onChange?()
        // Сбрасываем ложный флаг речи владельца и состояние подавления в TurnDetector перед доставкой чужого голоса.
        onOwnerSpeaking?(false, Double(phraseEnd) / 1e6)
        onTranscript?(.speechStarted(utterance: 0))
        // utterance == 0 сигнализирует TurnController не делать ring re-decode из пустого системного буфера.
        onTranscript?(.final(utterance: 0, text: trimmed, language: "", phraseEnd: phraseEnd, emittedAt: DispatchTime.now().uptimeNanoseconds))
    }

    /// Ответ владельца в самопроверке: в память интервью; для хода — как шум, вопросов нет.
    private func recordOwnerAnswer(utterance u: Int, text: String, phraseEnd: UInt64) {
        onOwnerSaid?(text, currentExchangeID?(), false)
        Log.metrics.notice("owner_final words=\(TurnDetectorWords.count(text)) mode=\(self.ownerAnswering ? "self-test" : "rehearsal", privacy: .public)")
        if partialText != nil {
            partialText = nil
            onChange?()
        }
        onTranscript?(.discarded(utterance: 0, phraseEnd: phraseEnd))
    }

    /// Ссылка на распознаватель, доступная из очереди захвата.
    private let transcriberBox = TranscriberBox()

    private func makeCapture() -> SystemAudioCapture {
        let buffer = self.buffer
        let meter = levelMeter
        let box = transcriberBox
        let route = self.route
        let captureEpoch = self.captureEpoch
        return SystemAudioCapture(onSamples: { samples in
            guard route.accepts(.call) else { return }
            buffer.append(samples)
            meter.add(samples)
            box.get()?.process(samples)
        }, onStop: { [weak self] error in
            let epoch = captureEpoch.current()
            Task { @MainActor in
                guard captureEpoch.current() == epoch else { return }
                self?.captureStopped(error)
            }
        })
    }

    /// Время перезапусков захвата за последние 10 минут (R-39).
    private var captureRestarts: [Date] = []

    /// Захват остановили macOS или значок записи в строке меню (R-39). На собеседовании нельзя молча перестать слышать:
    /// перезапускаем через 1 с, не больше 5 раз за 10 минут; дальше — понятная ошибка в панели.
    private func captureStopped(_ error: Error?) {
        guard !stopping, captureWanted, phase != .paused, phase != .noPermission, phase != .standby else { return }
        let reason = error?.localizedDescription ?? "?"
        let now = Date()
        captureRestarts = captureRestarts.filter { now.timeIntervalSince($0) < 600 }
        guard captureRestarts.count < 5 else {
            Log.audio.error("capture stopped, restarts exhausted: \(reason, privacy: .public)")
            setPhase(.error(L("Захват звука остановлен macOS (%@). Пауза → Продолжить, чтобы включить снова.", "\(reason)")))
            return
        }
        captureRestarts.append(now)
        Log.audio.notice("capture_restart attempt=\(self.captureRestarts.count) reason=\(reason, privacy: .public)")
        setPhase(.error("Захват звука остановлен — перезапускаю…"))
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, !self.stopping, self.phase != .paused, self.phase != .standby else { return }
            self.updateCapture(restart: true)
        }
    }

    private func makeMicSource() -> MicrophoneCapture {
        let buffer = self.buffer
        let meter = levelMeter
        let box = transcriberBox
        let route = self.route
        return MicrophoneCapture { samples in
            guard route.accepts(.owner) else { return }
            buffer.append(samples)
            meter.add(samples)
            box.get()?.process(samples)
        }
    }

    private func startMic() {
        guard testSource == nil, micPermission() == .granted else { return }
        if mic == nil {
            mic = MicActivityDetector { [weak self] speaking in
                let t = Double(DispatchTime.now().uptimeNanoseconds) / 1e6
                Task { @MainActor in
                    self?.ownerSpeaking = speaking
                    self?.onOwnerSpeaking?(speaking, t)
                }
            }
            // R-07: тот же микрофон — в распознавание речи владельца, пока канал включён.
            let buffer = ownerBuffer, box = ownerBox, active = ownerActive
            mic?.onSamples = { samples in
                guard active.value else { return }
                buffer.append(samples)
                box.get()?.process(samples)
            }
        }
        do { try mic?.start() } catch {
            Log.audio.error("mic start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Уровень сигнала раз в 100 мс для индикатора и раз в секунду в лог (только число, без звука).
    private func startLevelReporting() {
        guard levelTask == nil else { return }
        levelTask = Task { [weak self] in
            var tick = 0
            var idle = false
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                // Без захвата (нет сессии, пауза, нет разрешения) звука нет: уровни гасит `setPhase`, а цикл не будит
                // интерфейс 10 раз в секунду весь день. В `.idle` микрофон владельца ещё работает — там
                // индикатор живой, как раньше; в `.error` индикаторы погашены.
                guard self.reportsLevels else {
                    idle = true
                    continue
                }
                if idle {
                    // Пик, накопленный за простой, не показываем первым же кадром.
                    idle = false
                    _ = self.levelMeter.takeDB()
                    _ = self.mic?.takePeakDB()
                    continue
                }
                self.levelDB = self.levelMeter.takeDB()
                self.micLevelDB = self.mic?.takePeakDB() ?? (self.source == .microphone ? self.levelDB : -120)
                self.micPeakSecond = max(self.micPeakSecond, self.micLevelDB)
                self.onLevels?()
                tick += 1
                if tick % 10 == 0, self.phase == .listening {
                    let mic = self.micPeakSecond
                    self.micPeakSecond = -120
                    Log.audio.info("level_db=\(self.levelDB, format: .fixed(precision: 1), privacy: .public) mic_db=\(mic, format: .fixed(precision: 1), privacy: .public) owner_speaking=\(self.ownerSpeaking, privacy: .public)")
                }
            }
        }
    }

    /// Есть ли что показывать на индикаторах уровня: при паузе, без сессии и без разрешения захват остановлен.
    private var reportsLevels: Bool {
        switch phase {
        case .listening, .idle: true
        // `.error` может длиться часами: индикаторы гаснут, цикл не будит интерфейс 10 раз в секунду (L3).
        case .paused, .standby, .noPermission, .error: false
        }
    }

    private func setPhase(_ new: Phase) {
        guard phase != new else { return }
        phase = new
        transcriber?.setPaused(new != .listening)
        if new != .listening { resetOwnerAnswer() }
        // Гасим до `onChange`: он перерисовывает и скрытую панель, а отдельный кадр уровней скрытая панель пропускает —
        // иначе после паузы при скрытой панели волны застывали бы на последнем значении.
        if !reportsLevels {
            levelDB = -120
            micLevelDB = -120
        }
        updateOwnerChannel()
        onChange?()
    }
}

enum AudioRoute: Equatable, Sendable {
    /// Звук созвона (браузер) — речь собеседника.
    case call
    /// Микрофон — ответ владельца.
    case owner
}

/// Маршрут доступен из очередей захвата.
final class AudioRouteBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: AudioRoute?
    func set(_ v: AudioRoute?) { lock.withLock { value = v } }
    /// Без маршрута (обычная работа) принимается любой запущенный источник.
    func accepts(_ r: AudioRoute) -> Bool { lock.withLock { value == nil || value == r } }
}

/// Флаг, доступный из очередей захвата.
final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.withLock { flag } }
    func set(_ v: Bool) { lock.withLock { flag = v } }
}

final class TranscriberBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: StreamingTranscriber?
    func set(_ t: StreamingTranscriber?) { lock.withLock { value = t } }
    func get() -> StreamingTranscriber? { lock.withLock { value } }
}

/// Пиковый RMS за интервал, потокобезопасно.
final class LevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: Float = -120

    func add(_ samples: [Float]) {
        let db = EnergyVAD.rmsDB(samples[...])
        lock.withLock { peak = max(peak, db) }
    }

    func takeDB() -> Float {
        lock.withLock {
            let v = peak
            peak = -120
            return v
        }
    }
}

/// Не допускает доставки событий старой фразы после сброса или выхода из теста.
final class DeliveryEpoch: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func advance() { lock.withLock { value += 1 } }
    func current() -> Int { lock.withLock { value } }
}
