import Foundation
import Testing
@testable import CopilotCore

/// COPILOT-17 R-06/R-07: «Точный вопрос (+2 с)».
@Suite struct PreciseQuestionSettingTests {
    @Test func effectiveWaitTable() {
        let types: [SessionType] = [.exam, .interview, .regular]
        let langs: [RecognitionLanguage] = [.uk, .ru, .en, .auto]
        for type in types {
            for mode in PreciseQuestionMode.allCases {
                for lang in langs {
                    let expected = lang == .uk && (mode == .on || (mode == .auto && type == .exam))
                    #expect(PreciseQuestionMode.waits(mode: mode, session: type, language: lang) == expected,
                            "\(type) \(mode) \(lang)")
                }
            }
        }
        #expect(PreciseQuestionMode.waits(mode: .on, session: nil, language: .uk))
        #expect(!PreciseQuestionMode.waits(mode: .auto, session: nil, language: .uk))
    }

    @Test func oldSettingsFileDefaultsToAuto() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(decoded.preciseQuestion == .auto)
        var s = AppSettings(); s.preciseQuestion = .off
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back.preciseQuestion == .off)
    }
}
