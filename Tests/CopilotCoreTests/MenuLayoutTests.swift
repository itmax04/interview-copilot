import Testing
@testable import CopilotCore

@Suite("MenuLayout — R-15")
struct MenuLayoutTests {
    @Test func sectionsFollowDesignOrder() {
        let sections = MenuLayout.sections(for: MenuState())
        #expect(sections.map { $0.map(\.action) } == [
            [.listeningSource, .togglePause],
            [.mode, .models, .language],
            [.profile, .questionBank, .editProfile, .practice],
            [.answerNow, .screenshot, .togglePanel, .sessionHistory],
            [.status],
            [.settings, .quit],
        ])
    }

    @Test func deviationsFromPicture() {
        let items = MenuLayout.sections(for: MenuState()).flatMap { $0 }
        func item(_ a: MenuAction) -> MenuItemSpec { items.first { $0.action == a }! }
        // A-3: ⌃⌥ вместо ⌘ для клавиш помощника.
        for a in [MenuAction.togglePause, .answerNow, .screenshot, .togglePanel] {
            #expect(item(a).hotkey?.modifiers == HotkeyBinding.ctrlOpt)
        }
        #expect(item(.answerNow).hotkey?.displayString == "⌃⌥↩")
        #expect(item(.screenshot).hotkey?.displayString == "⌃⌥S")
        #expect(item(.settings).shortcut == .command(","))
        #expect(item(.quit).shortcut == .command("q"))
        // Локальный тестовый звонок доступен из меню.
        #expect(item(.practice).enabled == true)
        #expect(item(.practice).badge == nil)
        // Подпись языка (UK/RU/EN).
        #expect(item(.language).title == "Language: Auto (UK/RU/EN)")
        // A-4: строка статуса — счётчик запросов, не квота.
        #expect(item(.status).title.contains("req"))
        #expect(item(.status).enabled == false)
    }

    @Test func listeningDotReflectsState() {
        let listening = MenuLayout.sections(for: MenuState(listening: .listening(source: "Chrome")))[0][0]
        #expect(listening.title == "Listening — Chrome")
        #expect(listening.statusDot == .green)
        let paused = MenuLayout.sections(for: MenuState(listening: .paused(source: "Chrome")))[0]
        #expect(paused[0].statusDot == .gray)
        #expect(paused[1].title == "Resume listening")
        let noPermission = MenuLayout.sections(for: MenuState(listening: .noPermission))[0][0]
        #expect(noPermission.statusDot == .red)
        #expect(noPermission.hasSubmenu == false)
    }

    @Test func bankErrorShownInMenu() {
        var s = MenuState(bankCardCount: 20)
        s.bankError = "Question bank: ошибка в строке 7: пустой ответ"
        let item = MenuLayout.sections(for: s).flatMap { $0 }.first { $0.action == .questionBank }
        #expect(item?.title == "Question bank: ошибка в строке 7: пустой ответ")
    }

    @Test func reboundHotkeyShownInMenu() {
        var s = MenuState()
        s.hotkeys[.togglePanel] = HotkeyBinding(keyCode: 0x26 /* J */, modifiers: HotkeyBinding.ctrlOpt)
        let item = MenuLayout.sections(for: s).flatMap { $0 }.first { $0.action == .togglePanel }
        #expect(item?.hotkey?.displayString == "⌃⌥J")
        #expect(item?.hotkey?.menuKeyEquivalent == "j")
    }

    @Test func dynamicTitles() {
        let s = MenuState(mode: .bankOnly, profileName: "Senior iOS", bankCardCount: 17, strongModelName: "Claude")
        let items = MenuLayout.sections(for: s).flatMap { $0 }
        #expect(items.contains { $0.title == "Mode: Question bank only" })
        #expect(items.contains { $0.title == "Models: Gemini → DeepSeek → Claude" })
        #expect(items.contains { $0.title == "Profile: Senior iOS" })
        #expect(items.contains { $0.title == "Question bank (17 cards)…" })
        #expect(items.contains { $0.title == "Screenshot → Claude" })
    }
}
