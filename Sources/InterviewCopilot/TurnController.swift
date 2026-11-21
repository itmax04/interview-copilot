import CopilotCore
import Foundation

/// Определение хода в приложении: события распознавания и микрофона → `TurnDetector` (R-05, S-07, S-08).
@MainActor
final class TurnController {
    private var detector: TurnDetector
    private var timer: Timer?
    /// Вызывается при завершённом ходе (дальше — поиск по базе и генерация, P-06…P-08).
    var onTurn: ((Turn) -> Void)?
    /// Повторное распознавание вопроса целиком (COPILOT-15 R-01): фразы хода, номер хода, предварительный текст →
    /// итоговый текст; nil — не вышло, остаётся текст фраз (R-05). Не задан — ход сразу по тексту фраз.
    var redecode: (([Int], Int, String) async -> String?)?
    /// Итоговый текст хода пришёл: заменить строки фраз в расшифровке (R-04).
    var onQuestionText: (([Int], String) -> Void)?
    /// Опережающий запрос (COPILOT-04 R-01): текст законченной реплики до истечения паузы T.
    var onDraft: ((String) -> Void)?
    /// Выключено в настройках — `onDraft` не вызывается.
    var draftsEnabled = true
    /// Auto Generate (COPILOT-09 Q4): выключено — ход только вручную (⌃⌥↩ / Answer), реплики копятся до нажатия.
    var autoEnabled = true
    private(set) var lastTurn: Turn?
    private var lastDraft: String?
    /// Последняя отфильтрованная реплика (COPILOT-05 S-08): ⌃⌥↩ в течение 15 с отвечает на неё.
    private var lastFiltered: (text: String, at: Double)?
    private var lastFinalAt: Double = 0
    static let filteredAnswerWindowMs: Double = 15_000

    init(thresholdMs: Int) {
        detector = TurnDetector(config: TurnDetector.Config(thresholdMs: Double(thresholdMs)))
    }

    static func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }

    func setThreshold(_ ms: Int, questionMs: Int) {
        detector.config.thresholdMs = Double(ms)
        detector.config.questionThresholdMs = Double(questionMs)
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.01   // система объединяет пробуждения; на паузу T (≥ 350 мс) 10 мс не влияют
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        detector.reset()
        lastDraft = nil
        generation += 1
    }

    func handle(_ event: TranscriptEvent) {
        guard timer != nil else { return } // пауза: события не копятся (S-08)
        switch event {
        case .speechStarted:
            detector.interviewerStartedSpeaking(at: Self.now())
        case .speechEnded(_, let at):
            detector.interviewerStoppedSpeaking(at: Double(at) / 1e6)
        case .discarded(_, let phraseEnd), .foreignVoice(_, _, _, let phraseEnd):
            detector.phraseDiscarded(speechEnd: Double(phraseEnd) / 1e6)
        case .partial, .speaker:
            // Ход — по итогам фраз; весь вопрос перераспознаётся при завершении хода (COPILOT-15).
            break
        case .final(let utterance, let text, _, let phraseEnd, _):
            finalsSinceTurn += 1
            lastFinalAt = Self.now()
            detector.phraseFinal(text, speechEnd: Double(phraseEnd) / 1e6, utterance: utterance)
            if let turn = detector.takeRequestedForce(at: Self.now()) { emit(turn) }
        }
    }

    func ownerSpeaking(_ speaking: Bool, at t: Double) {
        guard timer != nil else { return }
        detector.setOwnerSpeaking(speaking, at: t)
    }

    /// ⌃⌥↩ — «Answer now». Если последней была отфильтрованная реплика (не старше 15 с) — ответ на неё (COPILOT-05 S-08).
    func forceTurn() {
        let now = Self.now()
        if let f = lastFiltered, now - f.at <= Self.filteredAnswerWindowMs, f.at > lastFinalAt {
            lastFiltered = nil
            emit(detector.forceText(f.text, at: now))
            return
        }
        if let turn = detector.force(at: now) { emit(turn) }
    }

    /// Clear (COPILOT-09 Q13): накопленные реплики не войдут в следующий ход.
    func clearPending() {
        generation += 1
        detector.reset()
        lastDraft = nil
        lastFiltered = nil
    }

    /// Фильтр отбросил реплику (COPILOT-05 R-06): запоминаем для ⌃⌥↩.
    func filtered(_ text: String) {
        lastFiltered = (text, Self.now())
    }

    /// Клик по серой строке панели — ответ на неё (COPILOT-05 S-08).
    func answerFiltered(_ text: String) {
        guard timer != nil else { return }
        lastFiltered = nil
        emit(detector.forceText(text, at: Self.now()))
    }

    private var finalsSinceTurn = 0
    private var lastStallLog: Double = 0

    private func tick() {
        guard autoEnabled else { return }
        let now = Self.now()
        if let turn = detector.tick(at: now) {
            emit(turn)
            return
        }
        // Опережающий запрос — только если ход ещё не наступил: итог, пришедший после паузы, сразу даёт ход.
        if draftsEnabled, let text = detector.draft(at: now), text != lastDraft {
            lastDraft = text
            Log.metrics.notice("draft_start words=\(TurnDetectorWords.count(text)) at_ms=\(Int(now))")
            onDraft?(text)
        }
        // Диагностика (R-38): итоги идут, а ходов нет — раз в минуту пишем, на каком условии стоит.
        if finalsSinceTurn >= 5, now - lastStallLog > 60_000 {
            lastStallLog = now
            Log.metrics.notice("turn_stall finals_since_turn=\(self.finalsSinceTurn) \(self.detector.debugState(at: now), privacy: .public)")
        }
    }

    /// Растёт при паузе и Clear: ход, ждавший повторного распознавания, после них не выдаётся.
    private var generation = 0
    /// Ходы выдаются по очереди: следующий ждёт повторного распознавания предыдущего.
    private var emitChain: Task<Void, Never>?

    private func emit(_ turn: Turn) {
        lastDraft = nil
        finalsSinceTurn = 0
        Log.metrics.notice("turn_end turn=\(turn.id) speech_end_ms=\(Int(turn.speechEndedAt)) fired_ms=\(Int(turn.firedAt)) forced=\(turn.forced) words=\(TurnDetectorWords.count(turn.text))")
        guard let redecode, !turn.utterances.isEmpty else {
            deliver(turn)
            return
        }
        let previous = emitChain
        let gen = generation
        emitChain = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, gen == self.generation else { return }
            var final = turn
            let text = await redecode(turn.utterances, turn.id, turn.provisionalText)
            if gen == self.generation {
                // Не вышло (R-05) — остаётся текст фраз; строки расшифровки всё равно сливаются в одну и перестают быть черновыми.
                final.text = text ?? turn.provisionalText
                self.onQuestionText?(turn.utterances, final.text)
            }
            guard gen == self.generation else { return }
            self.deliver(final)
        }
    }

    private func deliver(_ turn: Turn) {
        lastTurn = turn
        onTurn?(turn)
    }
}

enum TurnDetectorWords {
    static func count(_ text: String) -> Int { text.split { $0.isWhitespace }.count }
}
