import Testing
@testable import CopilotCore

@Suite struct SessionLanguageLockTests {
    let ru1 = "Расскажите про ваш опыт работы с базами данных"
    let ru2 = "Как вы организуете тестирование в команде"
    let ru3 = "Что такое индексы и зачем они нужны"
    let en1 = "Tell me about your experience with distributed systems"
    let en2 = "How would you design a rate limiter for this service"

    @Test func locksAfterThreeSlavicPhrases() {
        var lock = SessionLanguageLock()
        let r1 = lock.observeKept(ru1, base: .auto)
        #expect(r1 == nil)
        let r2 = lock.observeKept(ru2, base: .auto)
        #expect(r2 == nil)
        #expect(lock.effectiveSetting(.auto) == .auto)
        let r3 = lock.observeKept(ru3, base: .auto)
        #expect(r3 == "slavic")
        #expect(lock.effectiveSetting(.auto) == .uk)
        // Закреплённый язык: целая английская фраза отбрасывается на любом канале.
        let gate = LanguageGate(setting: lock.effectiveSetting(.auto))
        #expect(gate.check(en1, channel: .call) == .drop(language: "en"))
    }

    @Test func noLockOnMixedOrShortPhrases() {
        var lock = SessionLanguageLock()
        _ = lock.observeKept(ru1, base: .auto)
        _ = lock.observeKept(en1, base: .auto)
        _ = lock.observeKept(ru2, base: .auto)
        _ = lock.observeKept("Да, понятно", base: .auto)   // короткая — не считается
        _ = lock.observeKept("Ок", base: .auto)
        #expect(lock.lockedGroup == nil)
        #expect(lock.effectiveSetting(.auto) == .auto)
        _ = lock.observeKept(ru3, base: .auto)
        #expect(lock.lockedGroup == nil)   // серия была прервана английской фразой: ru2, ru3 — только две
    }

    @Test func explicitLanguageNeverLocks() {
        var lock = SessionLanguageLock()
        for t in [ru1, ru2, ru3] { _ = lock.observeKept(t, base: .ru) }
        #expect(lock.lockedGroup == nil)
        #expect(lock.effectiveSetting(.ru) == .ru)
    }

    @Test func resetPerSession() {
        var lock = SessionLanguageLock()
        for t in [ru1, ru2, ru3] { _ = lock.observeKept(t, base: .auto) }
        lock.allowEnglish()
        lock.reset()
        #expect(lock == SessionLanguageLock())
        #expect(lock.effectiveSetting(.auto) == .auto)
    }

    @Test func unlockAllowsEnglish() {
        var lock = SessionLanguageLock()
        for t in [ru1, ru2, ru3] { _ = lock.observeKept(t, base: .auto) }
        lock.allowEnglish()
        #expect(lock.effectiveSetting(.auto) == .auto)
        #expect(LanguageGate(setting: lock.effectiveSetting(.auto)).check(en1, channel: .call) == .keep)
        // Явный uk/ru тоже открывается для английского; повторно не закрепляется.
        #expect(lock.effectiveSetting(.uk) == .auto)
        for t in [ru1, ru2, ru3] { _ = lock.observeKept(t, base: .auto) }
        #expect(lock.effectiveSetting(.auto) == .auto)
    }

    @Test func twoConsecutiveEnglishDropsRaiseNoticeOnce() {
        var lock = SessionLanguageLock()
        let r4 = lock.observeDrop(language: "en", base: .uk)
        #expect(!r4)
        let r5 = lock.observeDrop(language: "en", base: .uk)
        #expect(r5)
        let r6 = lock.observeDrop(language: "en", base: .uk)
        #expect(!r6)
        let r7 = lock.observeDrop(language: "en", base: .uk)
        #expect(!r7)
    }

    @Test func noticeNeedsConsecutiveEnglishDropsInSlavicSession() {
        var lock = SessionLanguageLock()
        let r8 = lock.observeDrop(language: "en", base: .uk)
        #expect(!r8)
        let rde = lock.observeDrop(language: "de", base: .uk)   // другой язык прерывает серию
        #expect(!rde)
        let r9 = lock.observeDrop(language: "en", base: .uk)
        #expect(!r9)
        _ = lock.observeKept(ru1, base: .uk)                    // оставленная фраза тоже
        let r10 = lock.observeDrop(language: "en", base: .uk)
        #expect(!r10)
        // Английская сессия и «Авто» без замка — подсказка не нужна.
        var en = SessionLanguageLock()
        let r11a = en.observeDrop(language: "en", base: .en)
        let r11b = en.observeDrop(language: "en", base: .en)
        #expect(!r11a && !r11b)
        var auto = SessionLanguageLock()
        let r12a = auto.observeDrop(language: "en", base: .auto)
        let r12b = auto.observeDrop(language: "en", base: .auto)
        #expect(!r12a && !r12b)
    }

    @Test func noticeInLockedAutoSession() {
        var lock = SessionLanguageLock()
        for t in [ru1, ru2, ru3] { _ = lock.observeKept(t, base: .auto) }
        let r13 = lock.observeDrop(language: "en", base: .auto)
        #expect(!r13)
        let r14 = lock.observeDrop(language: "en", base: .auto)
        #expect(r14)
    }

    @Test func englishGroupLocksToEnglish() {
        var lock = SessionLanguageLock()
        _ = lock.observeKept(en1, base: .auto)
        _ = lock.observeKept(en2, base: .auto)
        let r15 = lock.observeKept("Can you walk me through your last project", base: .auto)
        #expect(r15 == "en")
        #expect(lock.effectiveSetting(.auto) == .en)
    }
}

@Suite struct SessionLanguageLockTermsTests {
    @Test func termOnlyEnglishPhrasesDoNotLockEnglish() {
        var lock = SessionLanguageLock()
        for t in ["Docker Kubernetes Terraform", "Docker Kubernetes Terraform", "Docker Kubernetes Terraform"] {
            _ = lock.observeKept(t, base: .auto)
        }
        #expect(lock.lockedGroup == nil)
    }
}
