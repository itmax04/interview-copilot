import Foundation
import Testing
@testable import CopilotCore

@Suite("SettingsStore — R-18")
struct SettingsStoreTests {
    private func makeStore() -> (SettingsStore, UserDefaults, String) {
        let suite = "com.itmax04.interviewcopilot.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (SettingsStore(defaults: defaults), defaults, suite)
    }

    @Test func defaultsMatchSpec() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let s = store.load()
        #expect(s.recognitionBackend == .parakeet)
        #expect(s.mode == .bankAndHint)                       // R-08
        #expect(s.chain == [.groq, .cerebras, .gemini, .deepseek, .anthropic])   // R-09, R-36: быстрые первыми
        #expect(s.hedgeAfter == 1.5)                           // R-36
        #expect(s.firstTokenTimeout == 4)                      // R-09
        #expect(s.pauseThresholdMs == 700)                     // R-05
        #expect(s.bankThreshold == 0.74)                       // R-07, порог по eval bank (P-06)
        #expect(s.embeddingModel == "bge-m3-q8_0.gguf")        // ADR-0001 п. 6
        #expect(s.piiFilterEnabled)                            // R-12
        #expect(s.historyRetentionDays == 30)                  // R-18
        #expect(s.monthlyBudgetUSD == 5)                       // R-18
        #expect(s.panelWidth == 380)                           // R-16
        #expect(s.geminiFreeTier)                              // R-20
        #expect(s.modelIDs.anthropic == "claude-sonnet-5-5")
    }

    @Test func roundTrip() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        var s = AppSettings()
        s.mode = .generateAlways
        s.language = .uk
        s.recognitionAccuracy = false
        s.recognitionBackend = .whisper
        s.whisperModel = "ggml-large-v3-turbo-q5_0.bin"
        s.audioSource = .microphone
        s.modelIDs.gemini = "gemini-x"
        s.panelFontSize = .large
        store.save(s)
        #expect(store.load() == s)
    }

    @Test func clampsOutOfRangeValues() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        var s = AppSettings()
        s.pauseThresholdMs = 50
        s.panelOpacity = 0.1
        s.panelWidth = 900
        s.bankThreshold = 1.5
        s.chain = [.anthropic, .anthropic]
        s.modelIDs.deepseek = "   "
        let saved = store.save(s)
        #expect(saved.pauseThresholdMs == 400)
        #expect(saved.panelOpacity == 0.7)
        #expect(saved.panelWidth == 520)
        #expect(saved.bankThreshold == 0.99)
        #expect(saved.chain == [.anthropic, .gemini, .deepseek, .groq, .cerebras])
        // Пустое поле не подменяется при вводе, но для запроса берётся ID по умолчанию.
        #expect(saved.modelIDs.deepseek == "   ")
        #expect(saved.modelIDs.effective(.deepseek) == "deepseek-flash")
        #expect(store.load() == saved)
    }

    @Test func missingFieldsFallBackToDefaults() throws {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(#"{"mode":"bankOnly","unknownField":1}"#.utf8), forKey: SettingsStore.defaultsKey)
        let s = store.load()
        #expect(s.mode == .bankOnly)
        #expect(s.pauseThresholdMs == 700)
        #expect(s.recognitionAccuracy)
    }

    @Test func oldDefaultThresholdIsMigrated() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(#"{"bankThreshold":0.85,"mode":"bankOnly"}"#.utf8), forKey: SettingsStore.defaultsKey)
        let s = store.load()
        #expect(s.bankThreshold == 0.74)
        #expect(s.schemaVersion == AppSettings.currentSchema)
        // Значение, выбранное владельцем, не трогаем.
        defaults.set(Data(#"{"bankThreshold":0.9}"#.utf8), forKey: SettingsStore.defaultsKey)
        #expect(store.load().bankThreshold == 0.9)
    }

    @Test func corruptDataGivesDefaults() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not json".utf8), forKey: SettingsStore.defaultsKey)
        #expect(store.load() == AppSettings())
    }

    @Test func settingsJSONNeverContainsKeys() throws {
        // Ключи живут только в Keychain (R-23): в модели настроек нет полей для них.
        let json = String(decoding: try JSONEncoder().encode(AppSettings()), as: UTF8.self).lowercased()
        #expect(!json.contains("apikey"))
        #expect(!json.contains("secret"))
    }
    @Test func previousWhisperDefaultUpgradesButCurrentSelectionIsPreserved() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"schemaVersion":4,"whisperModel":"ggml-medium-q5_0.bin"}"#.utf8))
        #expect(old.migrated().whisperModel == AppSettings.defaultWhisperModel)
        var current = AppSettings()
        current.whisperModel = "ggml-medium-q5_0.bin"
        #expect(current.migrated().whisperModel == current.whisperModel)
        var custom = old
        custom.whisperModel = "custom.bin"
        #expect(custom.migrated().whisperModel == "custom.bin")
    }

}
