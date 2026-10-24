import Foundation
import Testing
@testable import CopilotCore

@Suite("Тема и язык интерфейса — COPILOT-10")
struct AppearanceLanguageTests {
    @Test func defaultsFollowTheSystemAndOldSettingsStillLoad() throws {
        let fresh = AppSettings()
        #expect(fresh.theme == .system && fresh.interfaceLanguage == .system)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"panelZoom":1.2}"#.utf8))
        #expect(old.theme == .system && old.interfaceLanguage == .system)
        var s = AppSettings()
        s.theme = .dark
        s.interfaceLanguage = .en
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back.theme == .dark && back.interfaceLanguage == .en)
    }

    @Test(arguments: [
        (["ru-UA"], InterfaceLanguage.ru), (["uk-UA", "en"], .ru), (["be"], .ru),
        (["en-US", "ru"], .en), (["de-DE"], .en), ([], .en),
    ])
    func systemLanguageResolves(preferred: [String], expected: InterfaceLanguage) {
        #expect(InterfaceLanguage.system.resolved(preferred: preferred) == expected)
        #expect(InterfaceLanguage.en.resolved(preferred: ["ru"]) == .en)
        #expect(InterfaceLanguage.ru.resolved(preferred: ["en"]) == .ru)
    }
}
