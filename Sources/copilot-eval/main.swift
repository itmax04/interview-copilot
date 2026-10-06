import CopilotCore
import Foundation

// CLI для evals и замеров (evals/README.md).
//   copilot-eval stt <model.bin> <file.wav>... [--lang uk|ru|en] [--full-context] [--repeat N]
// Наборы `bank` и `turn` подключаются на P-05 и P-06.
var args = Array(CommandLine.arguments.dropFirst())

@MainActor func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return v
}

@MainActor func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}

func fail(_ message: String, code: Int32 = 64) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

switch args.first {
case "stt":
    args.removeFirst()
    let lang = option("--lang")
    let repeats = Int(option("--repeat") ?? "1") ?? 1
    let fullContext = flag("--full-context")
    guard args.count >= 2 else { fail("usage: copilot-eval stt <model.bin> <file.wav>... [--lang xx] [--full-context] [--repeat N]") }
    let memBefore = ProcessMemory.footprintMB()
    let loadStart = Date()
    let engine: WhisperEngine
    do { engine = try WhisperEngine(modelPath: args[0]) } catch { fail("\(error)", code: 1) }
    print(String(format: "model=%@ load_ms=%.0f mem_after_load_mb=%.0f (before %.0f)",
                 (args[0] as NSString).lastPathComponent, Date().timeIntervalSince(loadStart) * 1000,
                 ProcessMemory.footprintMB(), memBefore))
    var peak = ProcessMemory.footprintMB()
    for path in args.dropFirst() {
        let samples: [Float]
        do { samples = try AudioFileReader.read16kMono(URL(fileURLWithPath: path)) } catch { fail("\(path): \(error)", code: 1) }
        for _ in 0..<repeats {
            do {
                let r = try engine.transcribe(samples, language: lang, reducedContext: !fullContext)
                peak = max(peak, ProcessMemory.footprintMB())
                let probs = r.languageProbabilities.sorted { $0.key < $1.key }
                    .map { String(format: "%@=%.2f", $0.key, $0.value) }.joined(separator: " ")
                print(String(format: "%@ audio_s=%.2f elapsed_ms=%.0f lang=%@ [%@] no_speech=%.2f avg_p=%.3f text=%@",
                             (path as NSString).lastPathComponent, r.audioSeconds, r.elapsedMs, r.language, probs,
                             r.noSpeechProbability, r.averageTokenProbability, r.text))
            } catch { fail("\(path): \(error)", code: 1) }
        }
    }
    print(String(format: "peak_mem_mb=%.0f", peak))
case "stt-stream":
    // Потоковый прогон в реальном времени: файлы подаются кусками по 20 мс с паузой 1 с между ними,
    // меряется «конец фразы → итоговый текст» (синтетическая оценка AC-01).
    args.removeFirst()
    let lang = option("--lang")
    guard args.count >= 2 else { fail("usage: copilot-eval stt-stream <model.bin> <file.wav>... [--lang xx]") }
    let engine: WhisperEngine
    do { engine = try WhisperEngine(modelPath: args[0]) } catch { fail("\(error)", code: 1) }
    let buffer = AudioRingBuffer(seconds: 30)
    final class Collector: @unchecked Sendable {
        let lock = NSLock()
        var latencies: [Double] = []
        var partials = 0
    }
    let collector = Collector()
    let transcriber = StreamingTranscriber(recognizer: engine, buffer: buffer) { event in
        switch event {
        case .partial:
            collector.lock.withLock { collector.partials += 1 }
        case .final(let u, let text, let language, let phraseEnd, let emitted):
            let ms = Double(emitted - phraseEnd) / 1e6
            collector.lock.withLock { collector.latencies.append(ms) }
            print(String(format: "final utt=%d lang=%@ phrase_end_to_final_ms=%.0f text=%@", u, language, ms, text))
        default: break
        }
    }
    transcriber.setLanguage(lang)
    let silence = [Float](repeating: 0, count: 16_000)
    func play(_ samples: [Float]) {
        var i = 0
        let start = Date()
        while i < samples.count {
            let chunk = Array(samples[i..<min(i + 320, samples.count)])
            buffer.append(chunk)
            transcriber.process(chunk)
            i += 320
            let due = start.addingTimeInterval(Double(i) / 16_000)
            let wait = due.timeIntervalSinceNow
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        }
    }
    play(silence)
    for path in args.dropFirst() {
        do { play(try AudioFileReader.read16kMono(URL(fileURLWithPath: path))) } catch { fail("\(path): \(error)", code: 1) }
        play(silence)
    }
    Thread.sleep(forTimeInterval: 2)
    let l = collector.lock.withLock { collector.latencies.sorted() }
    let median = l.isEmpty ? 0 : (l.count % 2 == 1 ? l[l.count / 2] : (l[l.count / 2 - 1] + l[l.count / 2]) / 2)
    print(String(format: "finals=%d partials=%d median_ms=%.0f max_ms=%.0f peak_mem_mb=%.0f",
                 l.count, collector.lock.withLock { collector.partials }, median, l.last ?? 0, ProcessMemory.footprintMB()))
case "bank", "turn":
    fail("copilot-eval \(args[0]): набор ещё не реализован (P-05/P-06)", code: 2)
default:
    print("usage: copilot-eval <stt|bank|turn> [options]")
    exit(args.isEmpty ? 0 : 64)
}
