import Foundation
import Testing
@testable import CopilotCore

/// Живой тест модели (plan.md P-04): «текст не пуст, язык верный». Нужна модель из `scripts/fetch-models.sh`;
/// без неё тест помечается как пропущенный (не удаляется и не ослабляется).
@Suite("WhisperEngine — R-03", .serialized)
struct WhisperEngineTests {
    static let modelPath = NSString(string: "~/Library/Application Support/InterviewCopilot/models/ggml-small-q5_1.bin")
        .expandingTildeInPath
    static let hasModel = FileManager.default.fileExists(atPath: modelPath)
    static let audioDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../evals/audio").standardized

    @Test(.enabled(if: hasModel, "нет модели: scripts/fetch-models.sh ggml-small-q5_1.bin"),
          arguments: [("uk-about-me", "uk", "себе"), ("ru-about-me", "ru", "себе"), ("en-about-me", "en", "yourself")])
    func transcribesFixture(file: String, language: String, keyword: String) throws {
        let engine = try WhisperEngine(modelPath: Self.modelPath)
        let samples = try AudioFileReader.read16kMono(Self.audioDir.appendingPathComponent("\(file).wav"))
        // Автоопределение языка.
        let auto = try engine.transcribe(samples, language: nil, prompt: nil, reducedContext: true)
        #expect(auto.language == language)
        #expect(!auto.text.isEmpty)
        #expect(auto.text.lowercased().contains(keyword))
        // Явный язык.
        let fixed = try engine.transcribe(samples, language: language, prompt: nil, reducedContext: true)
        #expect(fixed.text.lowercased().contains(keyword))
    }

    @Test(.enabled(if: hasModel)) func silenceGivesNoSpeech() throws {
        let engine = try WhisperEngine(modelPath: Self.modelPath)
        let r = try engine.transcribe([Float](repeating: 0, count: 32_000), language: "en", prompt: nil, reducedContext: true)
        #expect(r.text.isEmpty)
        #expect(r.noSpeechProbability == 1)
    }

    @Test func missingModelThrows() {
        #expect(throws: WhisperError.self) { try WhisperEngine(modelPath: "/nonexistent/model.bin") }
    }

    @Test func collapsesLoopedPhrases() {
        #expect(WhisperEngine.clean("Ви не вели, що ми збираємо, що ми збираємо, що ми збираємо, що ми збираємо")
                == "Ви не вели, що ми збираємо,")
        #expect(WhisperEngine.clean("It's to, it's to, it's to, it's to, it's to") == "It's to,")
        // Обычная речь с одиночными повторами не трогается.
        let normal = "Tell me, tell me about a project you are proud of"
        #expect(WhisperEngine.clean(normal) == normal)
    }

    @Test func cleanRemovesAnnotations() {
        #expect(WhisperEngine.clean("  [Music] Hello  (applause) world ") == "Hello world")
    }
}
