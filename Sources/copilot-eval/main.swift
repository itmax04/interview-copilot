import CopilotCore
import CopilotEmbeddings
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)

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
    finish(code)
}

/// Выход без статических деструкторов: ggml-metal при выходе через exit() падает на освобождении устройства.
func finish(_ code: Int32) -> Never {
    fflush(stdout)
    _exit(code)
}

switch args.first {
case "stt", "stt-parakeet", "stt-hybrid":
    // stt-hybrid <parakeet-dir> <whisper.bin> <file.wav>… — итог как в приложении: украинский через Whisper uk (R-35).
    let useParakeet = args.first == "stt-parakeet" || args.first == "stt-hybrid"
    let hybridWhisper: String? = args.first == "stt-hybrid" && args.count > 2 ? args[2] : nil
    args.removeFirst()
    if hybridWhisper != nil { args.remove(at: 1) }
    let lang = option("--lang")
    let repeats = Int(option("--repeat") ?? "1") ?? 1
    let fullContext = flag("--full-context")
    guard args.count >= 2 else { fail("usage: copilot-eval stt <model.bin> <file.wav>... [--lang xx] [--full-context] [--repeat N]") }
    let memBefore = ProcessMemory.footprintMB()
    let loadStart = Date()
    let engine: any SpeechRecognizer
    do {
        if useParakeet {
            let parakeet = try await ParakeetEngine.load(from: URL(fileURLWithPath: args[0]))
            if let hybridWhisper {
                engine = HybridRecognizer(primary: parakeet, loadVerifier: { try WhisperEngine(modelPath: hybridWhisper) })
            } else { engine = parakeet }
        }
        else { engine = try WhisperEngine(modelPath: args[0]) }
    } catch { fail("\(error)", code: 1) }
    print(String(format: "model=%@ load_ms=%.0f mem_after_load_mb=%.0f (before %.0f)",
                 (args[0] as NSString).lastPathComponent, Date().timeIntervalSince(loadStart) * 1000,
                 ProcessMemory.footprintMB(), memBefore))
    var peak = ProcessMemory.footprintMB()
    for path in args.dropFirst() {
        let samples: [Float]
        do { samples = try AudioFileReader.read16kMono(URL(fileURLWithPath: path)) } catch { fail("\(path): \(error)", code: 1) }
        for _ in 0..<repeats {
            do {
                let r = try engine.transcribeFinal(samples, language: lang, prompt: nil, reducedContext: !fullContext)
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
    finish(0)
case "stt-stream":
    // Потоковый прогон в реальном времени: файлы подаются кусками по 20 мс с паузой 1 с между ними,
    // меряется «конец фразы → итоговый текст» (синтетическая оценка AC-01).
    args.removeFirst()
    let lang = option("--lang")
    // --gain 0.033 — имитация тихого собеседника в Meet (−30 дБ).
    let gain = Float(option("--gain") ?? "1") ?? 1
    let usePrompt = flag("--prompt-bank")
    let useParakeet = flag("--parakeet")
    let fast = flag("--fast")
    guard args.count >= 2 else { fail("usage: copilot-eval stt-stream <model.bin> <file.wav>... [--lang xx] [--gain k]") }
    let engine: any SpeechRecognizer
    do {
        if useParakeet {
            let parakeet = try await ParakeetEngine.load(from: URL(fileURLWithPath: args[0]))
            // --hybrid <whisper.bin>: двухэтапный итог как в приложении (R-35, R-37).
            if let whisper = option("--hybrid") {
                engine = HybridRecognizer(primary: parakeet, loadVerifier: { try WhisperEngine(modelPath: whisper) })
            } else { engine = parakeet }
        }
        else { engine = try WhisperEngine(modelPath: args[0]) }
    } catch { fail("\(error)", code: 1) }
    let buffer = AudioRingBuffer(seconds: 30)
    final class Collector: @unchecked Sendable {
        let lock = NSLock()
        var latencies: [Double] = []
        var partials = 0
        var ended = 0
    }
    let collector = Collector()
    var config = StreamingTranscriber.Config()
    config.finalReducedContext = fast
    let transcriber = StreamingTranscriber(recognizer: engine, buffer: buffer, config: config) { event in
        switch event {
        case .speechEnded:
            collector.lock.withLock { collector.ended += 1 }
        case .partial:
            collector.lock.withLock { collector.partials += 1 }
        case .final(let u, let text, let language, let phraseEnd, let emitted):
            let ms = Double(emitted - phraseEnd) / 1e6
            collector.lock.withLock { collector.latencies.append(ms) }
            print(String(format: "final utt=%d lang=%@ phrase_end_to_final_ms=%.0f text=%@", u, language, ms, text))
        case .revised(let u, let text, let language):
            print(String(format: "revised utt=%d lang=%@ text=%@", u, language, text))
        default: break
        }
    }
    transcriber.setLanguage(lang)
    if usePrompt, let cards = try? QuestionBankParser.load(URL(fileURLWithPath: "profile.example/questions.yaml")) {
        transcriber.setPromptProvider { language in RecognitionVocabulary.prompt(cards: cards, language: language) }
    }
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
        do { play(try AudioFileReader.read16kMono(URL(fileURLWithPath: path)).map { $0 * gain }) } catch { fail("\(path): \(error)", code: 1) }
        play(silence)
    }
    let deadline = Date().addingTimeInterval(30)
    while Date() < deadline && collector.lock.withLock({ collector.latencies.count < collector.ended }) {
        try? await Task.sleep(for: .milliseconds(20))
    }
    let pending = collector.lock.withLock { collector.ended - collector.latencies.count }
    let l = collector.lock.withLock { collector.latencies.sorted() }
    let median = l.isEmpty ? 0 : (l.count % 2 == 1 ? l[l.count / 2] : (l[l.count / 2 - 1] + l[l.count / 2]) / 2)
    print(String(format: "finals=%d partials=%d median_ms=%.0f max_ms=%.0f peak_mem_mb=%.0f",
                 l.count, collector.lock.withLock { collector.partials }, median, l.last ?? 0, ProcessMemory.footprintMB()))
    if pending > 0 { fail("stt-stream: \(pending) final result(s) did not arrive", code: 1) }
    finish(0)
case "filter-text":
    // Eval `filter` по тексту (COPILOT-05 R-05): evals/filter/text-cases.jsonl → совпадение с ожиданием, без моделей.
    args.removeFirst()
    let path = args.first ?? "evals/filter/text-cases.jsonl"
    guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { fail("\(path): нет файла", code: 1) }
    let verbose = flag("--verbose")
    var total = 0, ok = 0
    var byTag: [String: (ok: Int, total: Int)] = [:]
    for line in raw.split(separator: "\n") where !line.isEmpty {
        guard let c = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: String],
              let text = c["text"], let setting = c["setting"].flatMap(RecognitionLanguage.init(rawValue:)),
              let channel = c["channel"].flatMap(LanguageGate.Channel.init(rawValue:)), let expect = c["expect"] else { continue }
        let verdict = LanguageGate(setting: setting, terms: TermDictionary()).check(text, channel: channel)
        let got: String = if case .keep = verdict { "keep" } else { "drop" }
        total += 1
        let tag = c["tag"] ?? "-"
        var t = byTag[tag] ?? (0, 0)
        t.total += 1
        if got == expect { ok += 1; t.ok += 1 } else if verbose { print("FAIL [\(tag)] \(setting.rawValue)/\(channel.rawValue) expect=\(expect) got=\(got): \(text)") }
        byTag[tag] = t
    }
    for (tag, t) in byTag.sorted(by: { $0.key < $1.key }) { print("  \(tag): \(t.ok)/\(t.total)") }
    let passed = ok == total
    print("filter-text: cases=\(total) correct=\(ok) \(passed ? "PASS" : "FAIL")")
    finish(passed ? 0 : 1)
case "filter":
    // Eval `filter` по звуку (COPILOT-05 AC-01, AC-02, AC-04): Silero → Parakeet → фильтр языка, по одному файлу.
    // Упрощение: файл — одна реплика (сегментация энергетическим детектором здесь не участвует).
    args.removeFirst()
    let manifest = args.first ?? "evals/filter/audio-cases.json"
    let dir = URL(fileURLWithPath: option("--dir") ?? "evals/audio/filter")
    let useGate = !flag("--no-vad")
    let useLang = !flag("--no-lang")
    let threshold = Float(option("--vad-threshold") ?? "0.5") ?? 0.5
    let verbose = flag("--verbose")
    guard let data = FileManager.default.contents(atPath: manifest),
          let cases = (try? JSONSerialization.jsonObject(with: data)) as? [[String: String]] else { fail("\(manifest): нет манифеста (scripts/make-filter-fixtures.py)", code: 1) }
    let engine: ParakeetEngine
    do { engine = try await ParakeetEngine.load(from: AppPaths.parakeetModels) } catch { fail("Parakeet: \(error)", code: 1) }
    let gate: SileroSpeechGate? = useGate ? (try? SileroSpeechGate.load(from: AppPaths.models, threshold: threshold)) : nil
    if useGate && gate == nil { fail("Silero не установлена: scripts/fetch-filter-models.py", code: 1) }
    let terms = TermDictionary()
    var foreign = (filtered: 0, total: 0), wanted = (lost: 0, total: 0), noise = (utterances: 0, total: 0)
    var termsKept = (ok: 0, total: 0), termsLatin = 0
    var vadMs: [Double] = []
    for c in cases {
        guard let file = c["file"], let expect = c["expect"], let setting = c["setting"].flatMap(RecognitionLanguage.init(rawValue:)),
              let channel = c["channel"].flatMap(LanguageGate.Channel.init(rawValue:)) else { continue }
        let samples: [Float]
        do { samples = try AudioFileReader.read16kMono(dir.appendingPathComponent(file)) } catch { fail("\(file): \(error)", code: 1) }
        var outcome = "keep"
        var prob: Float = 1
        var text = ""
        if let gate {
            let started = Date()
            prob = gate.speechProbability(samples)
            vadMs.append(Date().timeIntervalSince(started) * 1000)
            if !gate.isSpeech(samples) { outcome = "none" }
        }
        if outcome != "none" {
            text = (try? engine.transcribe(samples, language: setting.whisperCode, prompt: nil, reducedContext: false).text) ?? ""
            if text.trimmingCharacters(in: .whitespaces).isEmpty
                || HallucinationFilter.isLikely(text, audioSeconds: Double(samples.count) / 16_000) { outcome = "none" }
            else if useLang, case .drop = LanguageGate(setting: setting, terms: terms).check(text, channel: channel) { outcome = "drop" }
        }
        switch expect {
        case "drop": foreign.total += 1; if outcome != "keep" { foreign.filtered += 1 }
        case "keep": wanted.total += 1; if outcome != "keep" { wanted.lost += 1 }
        default: noise.total += 1; if outcome != "none" { noise.utterances += 1 }
        }
        if c["tag"] == "terms" {
            // AC-02 — фильтр не отбросил вопрос с терминами. Латиница в тексте — свойство распознавания (справочно).
            termsKept.total += 1
            if outcome == "keep" { termsKept.ok += 1 }
            if text.unicodeScalars.contains(where: { $0.value < 0x80 && CharacterSet.letters.contains($0) }) { termsLatin += 1 }
        }
        let ok = (expect == outcome) || (expect == "drop" && outcome == "none")
        if !ok || verbose {
            print("\(ok ? "ok  " : "FAIL") \(file) expect=\(expect) got=\(outcome) vad=\(String(format: "%.2f", prob)) text=\(text.prefix(70))")
        }
    }
    let foreignRate = foreign.total == 0 ? 1 : Double(foreign.filtered) / Double(foreign.total)
    let lostRate = wanted.total == 0 ? 0 : Double(wanted.lost) / Double(wanted.total)
    let pass = foreignRate >= 0.9 && lostRate <= 0.05 && noise.utterances <= 1 && termsKept.ok == termsKept.total
    print(String(format: "filter: vad=%@ lang=%@ AC-01 foreign_filtered=%d/%d (%.0f%%, ≥90%%) wanted_lost=%d/%d (%.0f%%, ≤5%%) · AC-02 terms_kept=%d/%d (latin_in_text=%d) · AC-04 noise_utterances=%d/%d (≤1) · vad_ms_median=%.0f %@",
                 useGate ? "on" : "off", useLang ? "on" : "off", foreign.filtered, foreign.total, foreignRate * 100,
                 wanted.lost, wanted.total, lostRate * 100, termsKept.ok, termsKept.total, termsLatin, noise.utterances, noise.total,
                 vadMs.sorted().dropFirst(vadMs.count / 2).first ?? 0, pass ? "PASS" : "FAIL"))
    finish(pass ? 0 : 1)
case "turn":
    // Eval `turn` (R-05): evals/turn/cases.jsonl → преждевременные/пропущенные ходы, задержка.
    args.removeFirst()
    let threshold = Double(option("--threshold-ms") ?? "700") ?? 700
    let verbose = flag("--verbose")
    let path = args.first ?? "evals/turn/cases.jsonl"
    let cases: [TurnEval.Case]
    do { cases = try TurnEval.load(URL(fileURLWithPath: path)) } catch { fail("\(path): \(error)", code: 1) }
    var config = TurnDetector.Config(thresholdMs: threshold)
    if let q = option("--question-ms").flatMap(Double.init) { config.questionThresholdMs = q }
    config.questionStarters = flag("--question-starters")
    let summary = TurnEval.run(cases, config: config)
    if verbose {
        for r in summary.results {
            print("\(r.id): expected=\(r.expected.map { String(Int($0)) } ?? "null") fired=\(r.firedAt.map { String(Int($0)) } ?? "none")\(r.forced ? " forced" : "") draft=\(r.draftAt.map { String(Int($0)) } ?? "none")")
        }
    }
    for r in summary.results where r.premature || r.missed {
        print("FAIL \(r.id): expected=\(r.expected.map { String(Int($0)) } ?? "null") fired=\(r.firedAt.map { String(Int($0)) } ?? "none")\(r.premature ? " premature" : "")\(r.missed ? " missed" : "")")
    }
    print(String(format: "turn: cases=%d T=%.0fms premature=%d (%.1f%%, порог ≤10%%) missed=%d/%d (%.1f%%, порог ≤5%%) mean_latency_ms=%.0f %@",
                 summary.cases, threshold, summary.premature, summary.prematureRate * 100, summary.missed, summary.withExpected,
                 summary.missedRate * 100, summary.meanLatencyMs, summary.passed ? "PASS" : "FAIL"))
    // COPILOT-04 R-01, R-04: когда модель получает вопрос — по опережающему запросу или по ходу.
    print(String(format: "draft: hits=%d mean_start_ms=%.0f wasted_requests=%d (question_ms=%.0f, starters=%@)",
                 summary.draftHits, summary.meanDraftLatencyMs, summary.draftWasted, config.questionThresholdMs,
                 config.questionStarters ? "on" : "off"))
    finish(summary.passed ? 0 : 1)
case "exit-check":
    // Проверка выхода через exit() после освобождения моделей (как applicationWillTerminate в приложении).
    do {
        let e = try LlamaEmbedder(modelPath: AppPaths.model(AppSettings.defaultEmbeddingModel).path)
        _ = try e.embed(["проверка"])
        let w = try WhisperEngine(modelPath: AppPaths.model(AppSettings.defaultWhisperModel).path)
        _ = try w.transcribe([Float](repeating: 0.1, count: 16_000), language: "en", prompt: nil, reducedContext: true)
    } catch { fail("\(error)", code: 1) }
    print("models released, calling exit(0)")
    exit(0)
case "bank":
    // Eval `bank` (AC-04): evals/bank/cases.jsonl против profile.example/questions.yaml.
    //   copilot-eval bank [cases.jsonl] [--model file.gguf] [--threshold 0.xx | --tune] [--sweep] [--verbose]
    // По умолчанию — конфигурация приложения: модель и порог из AppSettings.
    args.removeFirst()
    let modelFile = option("--model") ?? AppSettings.defaultEmbeddingModel
    let tune = flag("--tune")
    let fixedThreshold = option("--threshold").flatMap(Double.init) ?? (tune ? nil : AppSettings().bankThreshold)
    let sweep = flag("--sweep")
    let verbose = flag("--verbose")
    let casesPath = args.first ?? "evals/bank/cases.jsonl"
    let bankPath = "profile.example/questions.yaml"
    let spec = EmbeddingModels.spec(for: modelFile)
    let memBefore = ProcessMemory.footprintMB()
    let embedder: LlamaEmbedder
    do { embedder = try LlamaEmbedder(modelPath: AppPaths.model(spec.file).path, prefix: spec.prefix) } catch { fail("\(error)", code: 1) }
    do {
        let cards = try QuestionBankParser.load(URL(fileURLWithPath: bankPath))
        let builder = BankIndexBuilder(embedder: embedder, cacheDirectory: nil)
        let t0 = Date()
        let index = try builder.build(cards)
        let buildMs = Date().timeIntervalSince(t0) * 1000
        let cases = try BankEval.load(URL(fileURLWithPath: casesPath))
        let t1 = Date()
        let rows = try BankEval.rank(cases, index: index, builder: builder)
        let perQueryMs = Date().timeIntervalSince(t1) * 1000 / Double(max(1, cases.count))
        let range = stride(from: 0.50, through: 0.95, by: 0.01).map { ($0 * 100).rounded() / 100 }
        let summary = fixedThreshold.map { BankEval.summarize(rows, threshold: $0) } ?? BankEval.bestThreshold(rows, range: range)
        if sweep {
            for t in stride(from: 0.50, through: 0.95, by: 0.05) {
                let s = BankEval.summarize(rows, threshold: t)
                print(String(format: "  threshold=%.2f top1=%.1f%% false=%.1f%%", t, s.top1Accuracy * 100, s.falseMatchRate * 100))
            }
        }
        if verbose { summary.failures.forEach { print($0) } }
        let langs = summary.perLanguage.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.correct)/\($0.value.total)" }.joined(separator: " ")
        print(String(format: "bank: model=%@ cards=%d cases=%d threshold=%.2f top1=%.1f%% (%@) top3=%.1f%% false=%d/%d (%.1f%%) index_ms=%.0f query_ms=%.0f mem_mb=%.0f→%.0f %@",
                     spec.file, cards.count, cases.count, summary.threshold, summary.top1Accuracy * 100, langs,
                     summary.top3Accuracy * 100, summary.falseMatches, summary.outOfBank, summary.falseMatchRate * 100,
                     buildMs, perQueryMs, memBefore, ProcessMemory.footprintMB(), summary.passed ? "PASS" : "FAIL"))
        finish(summary.passed ? 0 : 1)
    } catch { fail("\(error)", code: 1) }
default:
    print("usage: copilot-eval <stt|bank|turn> [options]")
    exit(args.isEmpty ? 0 : 64)
}
