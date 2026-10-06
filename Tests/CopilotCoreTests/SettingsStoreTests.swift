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
        #expect(s.mode == .bankAndHint)                       // R-08
        #expect(s.chain == [.gemini, .deepseek, .anthropic])   // R-09
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
        s.audioSource = .app(bundleID: "com.google.Chrome", name: "Google Chrome")
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
        #expect(saved.chain == [.anthropic, .gemini, .deepseek])
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
}
