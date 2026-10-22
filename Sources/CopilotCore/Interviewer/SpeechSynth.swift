@preconcurrency import AVFoundation
import Foundation

/// WAV PCM 16 бит моно в памяти — голос интервьюера для страницы (на диск не пишется).
public enum WAVEncoder {
    public static func encode(_ samples: [Float], sampleRate: Int) -> Data {
        var data = Data(capacity: 44 + samples.count * 2)
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        data.append(contentsOf: Array("data".utf8)); u32(bytes)
        for s in samples { u16(UInt16(bitPattern: Int16((max(-1, min(1, s)) * 32767).rounded()))) }
        return data
    }
}

public enum SpeechSynthError: Error, CustomStringConvertible {
    case noVoice(String)
    case empty

    public var description: String {
        switch self {
        case .noVoice(let lang): "В macOS нет голоса для языка \(lang). Добавьте его: Системные настройки → Универсальный доступ → Устный контент → Системный голос."
        case .empty: "Синтез речи не вернул звук"
        }
    }
}

/// Голос интервьюера: встроенный синтез речи macOS (бесплатно, без сети), COPILOT-03.
public enum SpeechSynth {
    public static func locale(_ language: String) -> String {
        switch language {
        case "uk": "uk-UA"
        case "ru": "ru-RU"
        default: "en-US"
        }
    }

    public static func voice(for language: String) -> AVSpeechSynthesisVoice? {
        let code = locale(language)
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == code }
        // Лучшее качество из установленных; новелти-голоса (Bells, Bubbles…) не выбираются.
        return voices.filter { !$0.voiceTraits.contains(.isNoveltyVoice) }.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: code)
    }

    /// Речь → WAV. Тишина 0,8 с до и 0,7 с после: как у фраз тестового звонка, VAD успевает закрыть фразу.
    @MainActor
    public static func wav(_ text: String, language: String, rate: Float = AVSpeechUtteranceDefaultSpeechRate) async throws -> Data {
        guard let voice = voice(for: language) else { throw SpeechSynthError.noVoice(locale(language)) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate
        let synthesizer = AVSpeechSynthesizer()
        let collector = Collector()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            collector.continuation = continuation
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                collector.add(pcm)
            }
            // Завершающий пустой буфер иногда не приходит — выходим по таймауту с тем, что уже есть.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(20))
                collector.finish()
            }
        }
        _ = synthesizer
        let (samples, sampleRate) = collector.result
        guard !samples.isEmpty, sampleRate > 0 else { throw SpeechSynthError.empty }
        let lead = [Float](repeating: 0, count: Int(0.8 * Double(sampleRate)))
        let tail = [Float](repeating: 0, count: Int(0.7 * Double(sampleRate)))
        return WAVEncoder.encode(lead + samples + tail, sampleRate: sampleRate)
    }

    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var samples: [Float] = []
        private var sampleRate = 0
        private var done = false
        var continuation: CheckedContinuation<Void, Error>?

        var result: ([Float], Int) { lock.withLock { (samples, sampleRate) } }

        func add(_ pcm: AVAudioPCMBuffer) {
            let n = Int(pcm.frameLength)
            if n == 0 { finish(); return }
            var chunk = [Float](repeating: 0, count: n)
            if let f = pcm.floatChannelData {
                for i in 0..<n { chunk[i] = f[0][i] }
            } else if let s = pcm.int16ChannelData {
                for i in 0..<n { chunk[i] = Float(s[0][i]) / 32768 }
            } else if let s = pcm.int32ChannelData {
                for i in 0..<n { chunk[i] = Float(s[0][i]) / 2_147_483_648 }
            }
            lock.withLock {
                sampleRate = Int(pcm.format.sampleRate)
                samples.append(contentsOf: chunk)
            }
        }

        func finish() {
            let c = lock.withLock { () -> CheckedContinuation<Void, Error>? in
                guard !done else { return nil }
                done = true
                let c = continuation
                continuation = nil
                return c
            }
            c?.resume()
        }
    }
}
