import Foundation

/// Энергетический детектор речи (VAD) для микрофона владельца (R-02) и сегментации речи собеседника (R-03).
/// Работает кадрами по 20 мс. Уровень шума — минимум энергии кадров за скользящее окно: в речи всегда есть
/// провалы между словами, а постоянный фон (вентилятор) поднимает минимум и речью не считается.
public struct EnergyVAD: Sendable {
    public struct Config: Sendable {
        public var sampleRate = 16_000
        public var frameMs = 20
        /// Абсолютный минимум уровня речи, dBFS.
        public var minSpeechDB: Float = -50
        /// Насколько речь должна быть громче шума, dB.
        public var marginDB: Float = 10
        /// Сколько кадров подряд выше порога, чтобы включить «говорит».
        public var attackFrames = 3
        /// Сколько миллисекунд тишины, чтобы выключить «говорит».
        public var hangoverMs = 300
        /// Окно оценки шума, мс.
        public var noiseWindowMs = 3000

        public init() {}
    }

    public let config: Config
    public private(set) var isSpeech = false
    public private(set) var noiseFloorDB: Float = -60
    public private(set) var lastFrameDB: Float = -120
    private var above = 0
    private var belowMs = 0
    private var pending: [Float] = []
    private var history: [Float] = []
    private var historyIndex = 0

    public init(config: Config = Config()) {
        self.config = config
    }

    public var frameSize: Int { config.sampleRate * config.frameMs / 1000 }

    public static func rmsDB(_ frame: ArraySlice<Float>) -> Float {
        guard !frame.isEmpty else { return -120 }
        var sum: Float = 0
        for s in frame { sum += s * s }
        let rms = (sum / Float(frame.count)).squareRoot()
        return rms > 0 ? max(-120, 20 * log10(rms)) : -120
    }

    /// Подать сэмплы; возвращает изменения состояния (true — началась речь, false — закончилась) по порядку.
    @discardableResult
    public mutating func process(_ samples: [Float]) -> [Bool] {
        processEvents(samples).map(\.isSpeech)
    }

    /// Позиция перехода — конец обработанного кадра относительно начала этого блока.
    public struct Event: Sendable, Equatable {
        public let isSpeech: Bool
        public let sampleOffset: Int
    }

    public mutating func processEvents(_ samples: [Float]) -> [Event] {
        let carried = pending.count
        pending.append(contentsOf: samples)
        var changes: [Event] = []
        let n = frameSize
        var offset = 0
        while pending.count - offset >= n {
            let frame = pending[offset..<(offset + n)]
            offset += n
            if let change = processFrame(Self.rmsDB(frame)) {
                changes.append(Event(isSpeech: change, sampleOffset: offset - carried))
            }
        }
        pending.removeFirst(offset)
        return changes
    }

    private mutating func processFrame(_ db: Float) -> Bool? {
        lastFrameDB = db
        let windowFrames = max(1, config.noiseWindowMs / config.frameMs)
        if history.count < windowFrames {
            history.append(db)
        } else {
            history[historyIndex] = db
            historyIndex = (historyIndex + 1) % windowFrames
        }
        noiseFloorDB = max(-90, history.min() ?? db)
        let threshold = max(config.minSpeechDB, noiseFloorDB + config.marginDB)
        let loud = db > threshold
        if loud {
            above += 1
            belowMs = 0
            if !isSpeech && above >= config.attackFrames {
                isSpeech = true
                return true
            }
        } else {
            above = 0
            belowMs += config.frameMs
            if isSpeech && belowMs >= config.hangoverMs {
                isSpeech = false
                return false
            }
        }
        return nil
    }

    public mutating func reset() {
        isSpeech = false
        above = 0
        belowMs = 0
        pending.removeAll()
        history.removeAll()
        historyIndex = 0
    }
}
