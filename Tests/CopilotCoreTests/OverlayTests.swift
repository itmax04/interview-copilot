import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Testing
@testable import CopilotCore

@Suite("Оверлей — COPILOT-09 этап 2")
struct OverlayTests {
    private func complete(_ h: inout AnswerHistory, _ q: String, _ text: String) -> (entry: Int, version: Int) {
        let ids = h.begin(question: q, turnID: nil, kind: .hint)
        h.update(entry: ids.entry, version: ids.version) { $0.text = text; $0.status = .complete }
        return ids
    }

    @Test func historyFollowsLatestUntilUserBrowsesBack() {
        var h = AnswerHistory()
        #expect(h.current == nil && h.position == nil && h.isViewingLatest)
        _ = complete(&h, "Расскажите о себе.", "A")
        _ = complete(&h, "Какой опыт со SwiftUI?", "B")
        #expect(h.current?.question == "Какой опыт со SwiftUI?" && h.position == "2 / 2" && !h.hasUnseenNew)
        #expect(h.previous?.question == "Расскажите о себе.")

        // Листаем назад — новый ответ не перебивает просмотр, появляется значок.
        h.selectPrevious()
        _ = complete(&h, "Как вы тестируете?", "C")
        #expect(h.current?.question == "Расскажите о себе." && h.position == "1 / 3" && h.hasUnseenNew)
        h.selectNext()
        #expect(h.hasUnseenNew)
        h.selectNext()
        #expect(h.isViewingLatest && !h.hasUnseenNew)
        h.selectPrevious(); h.selectLatest()
        #expect(h.position == "3 / 3" && !h.hasUnseenNew)
        // Границы.
        h.selectNext()
        #expect(h.position == "3 / 3")
    }

    @Test func lateTokensOnlyReachTheirOwnVersion() {
        var h = AnswerHistory()
        let first = h.begin(question: "Q1", turnID: 1, kind: .hint)
        h.update(entry: first.entry, version: first.version) { $0.text = "начало"; $0.status = .streaming }
        // Новый вопрос прерывает незаконченные ответы.
        let second = h.begin(question: "Q2", turnID: 2, kind: .hint)
        h.cancelUnfinished(except: second.version)
        #expect(h.entry(first.entry)?.versions[0].status == .cancelled)
        #expect(h.entry(second.entry)?.versions[0].status == .waiting)
        h.update(entry: second.entry, version: second.version) { $0.text = "ответ 2" }
        #expect(h.entry(first.entry)?.versions[0].text == "начало")
        // Обновление несуществующей версии ничего не меняет.
        let before = h
        h.update(entry: second.entry, version: 9_999) { $0.text = "чужой" }
        h.update(entry: 9_999, version: second.version) { $0.text = "чужой" }
        #expect(h == before)
    }

    @Test func repeatedAnswerPressIsRecognizedOnlyWhileAnswerIsComing() {
        var h = AnswerHistory()
        let t0 = Date(timeIntervalSince1970: 1_792_400_000)
        #expect(!h.isRepeat(of: "Q", at: t0))
        let ids = h.begin(question: "Какой у вас опыт со SwiftUI?", turnID: 1, kind: .hint, at: t0)
        #expect(h.isRepeat(of: " какой у вас опыт со SwiftUI? ", at: t0.addingTimeInterval(1)))
        #expect(!h.isRepeat(of: "Какой у вас опыт со SwiftUI?", at: t0.addingTimeInterval(3)))   // позже — новый ход
        #expect(!h.isRepeat(of: "Другой вопрос", at: t0.addingTimeInterval(1)))
        h.update(entry: ids.entry, version: ids.version) { $0.text = "A"; $0.status = .complete }
        #expect(!h.isRepeat(of: "Какой у вас опыт со SwiftUI?", at: t0.addingTimeInterval(1)))   // ответ готов — можно повторить
    }

    @Test func versionsAndRemovalOfNotAQuestion() {
        var h = AnswerHistory()
        let a = complete(&h, "Q1", "длинный ответ")
        let v = h.beginVersion(of: a.entry, kind: .refine, instruction: "короче")
        #expect(v != nil && h.current?.versions.count == 2 && h.current?.selectedVersion == 1)
        #expect(h.current?.current?.kind == .refine && h.current?.current?.instruction == "короче")
        h.selectVersion(0)
        #expect(h.current?.current?.text == "длинный ответ")
        h.selectVersion(5)
        #expect(h.current?.selectedVersion == 0)
        #expect(h.beginVersion(of: 9_999, kind: .strong) == nil)

        // «—» от модели: вопрос убирается, показывается предыдущий.
        let b = h.begin(question: "Ну вот", turnID: 2, kind: .hint)
        h.remove(entry: b.entry)
        #expect(h.entries.count == 1 && h.current?.id == a.entry && h.isViewingLatest)
        h.remove(entry: a.entry)
        #expect(h.current == nil && h.selected == nil)
    }

    @Test func historyKeepsLimit() {
        var h = AnswerHistory()
        for i in 0..<(AnswerHistory.limit + 5) { _ = complete(&h, "Q\(i)", "A\(i)") }
        #expect(h.entries.count == AnswerHistory.limit)
        #expect(h.entries.first?.question == "Q5" && h.current?.question == "Q\(AnswerHistory.limit + 4)")
        h.clear()
        #expect(h.entries.isEmpty && h.current == nil)
    }

    @Test(arguments: [
        ("Эээ, какой у вас опыт со SwiftUI? И как вы тестируете?", "Какой у вас опыт со SwiftUI?"),
        ("Uh tell me about yourself? thanks", "Tell me about yourself?"),
        ("расскажите о себе", "Расскажите о себе"),
    ])
    func titleIsFirstQuestionWithoutFillers(input: String, expected: String) {
        #expect(AnswerHistory.title(for: input) == expected)
    }

    @Test func longTitleIsTruncated() {
        let t = AnswerHistory.title(for: String(repeating: "слово ", count: 40))
        #expect(t.count == 80 && t.hasSuffix("…"))
    }

    @Test func refineKeepsQuestionAndAddsPreviousAnswerAsData() {
        let base = LLMRequest(system: "sys", messages: [LLMMessage(role: .user, text: "Question: Какой опыт?")], maxTokens: 400, purpose: .hint)
        let r = PromptBuilder.refine(base, previousAnswer: "Пять лет SwiftUI.", instruction: "Make it shorter")
        #expect(r.system == "sys" && r.maxTokens == 800)
        #expect(r.messages[0].text.hasPrefix("Question: Какой опыт?"))
        #expect(r.messages[0].text.contains("<previous_answer>\nПять лет SwiftUI.\n</previous_answer>"))
        #expect(r.messages[0].text.contains("candidate's request: Make it shorter"))
        let empty = LLMRequest(system: "s", messages: [], maxTokens: 400, purpose: .hint)
        #expect(PromptBuilder.refine(empty, previousAnswer: "x", instruction: "y") == empty)
    }

    @Test func sessionHotkeysUseCommandAndDoNotCollideWithAlwaysOnOnes() {
        let s = HotkeyBinding.sessionDefaults
        #expect(s[.answerNow]?.displayString == "⌘↩")
        #expect(s[.screenshot]?.displayString == "⇧⌘↩")
        #expect(s[.chat]?.displayString == "⇧⌘Space")
        #expect(s[.clearTranscript]?.displayString == "⇧⌘⌫")
        #expect(s[.previousAnswer]?.displayString == "⌘←" && s[.nextAnswer]?.displayString == "⌘→")
        #expect(s.values.allSatisfy { $0.isValidGlobal && $0.modifiers & UInt32(cmdKey) != 0 })
        #expect(Set(s.values).isDisjoint(with: Set(HotkeyBinding.defaults.values)))
        #expect(Set(s.values).count == s.count)
        // У каждого действия оверлея есть ⌃⌥-сочетание, работающее и вне сессии.
        for action in [HotkeyAction.chat, .clearTranscript, .previousAnswer, .nextAnswer] {
            #expect(HotkeyBinding.defaults[action]?.modifiers == HotkeyBinding.ctrlOpt)
        }
    }

    @Test(arguments: [
        (255, 0, 255, true), (234, 51, 247, true), (255, 64, 255, true),
        (255, 255, 255, false), (30, 30, 30, false), (200, 140, 200, false), (255, 0, 0, false), (0, 0, 255, false),
    ])
    func probeColorSurvivesColorSpaces(r: Int, g: Int, b: Int, expected: Bool) {
        #expect(VisibilityProbe.isProbe(r: r, g: g, b: b) == expected)
    }

    @Test func probeVerdictHasUnclearMiddle() {
        #expect(VisibilityProbe.verdict(share: 0.9) == .visible)
        #expect(VisibilityProbe.verdict(share: 0.01) == .hidden)
        #expect(VisibilityProbe.verdict(share: 0.15) == .unclear)
    }

    @Test func visibilityProbeCountsProbeColorOnlyInsideRect() throws {
        let w = 40, h = 20
        let ctx = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // Левая половина — пурпурная метка.
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w / 2, height: h))
        let image = try #require(ctx.makeImage())
        #expect(VisibilityProbe.fraction(in: image, rect: CGRect(x: 0, y: 0, width: 20, height: 20), step: 1) == 1)
        #expect(VisibilityProbe.fraction(in: image, rect: CGRect(x: 20, y: 0, width: 20, height: 20), step: 1) == 0)
        let whole = VisibilityProbe.fraction(in: image, rect: CGRect(x: 0, y: 0, width: 40, height: 20), step: 1)
        #expect(abs(whole - 0.5) < 0.01)
        #expect(VisibilityProbe.fraction(in: image, rect: CGRect(x: 0, y: 0, width: 40, height: 20)) > 0.3)
        // Прямоугольник вне снимка — ноль, а не сбой.
        #expect(VisibilityProbe.fraction(in: image, rect: CGRect(x: 100, y: 100, width: 10, height: 10)) == 0)
    }
}
