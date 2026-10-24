import Foundation
import Testing
@testable import CopilotCore

@Suite("Задача со скриншота и уточнения — COPILOT-09 этап 5")
struct ScreenshotTaskTests {
    private let t0 = Date(timeIntervalSince1970: 1_792_400_000)
    static let solution = """
    1. **Task** — найти индексы двух чисел массива с суммой `target`.
    2. **Approach**
    - словарь «значение → индекс»
    - один проход
    3. **Code**
    ```swift
    func twoSum(_ nums: [Int], _ target: Int) -> [Int] {
        var seen: [Int: Int] = [:]
        for (i, n) in nums.enumerated() {
            if let j = seen[target - n] { return [j, i] }
            seen[n] = i
        }
        return []
    }
    ```
    4. **Complexity** — O(n) времени, O(n) памяти.
    5. **Checks** — [2,7,11,15], 9 → [0,1].
    """

    @Test func shotsWithin30SecondsJoinOneTaskUpToThree() {
        var tr = ScreenshotTaskTracker()
        let added1 = tr.add(Data([1]), at: t0)
        #expect(added1)
        let added2 = tr.add(Data([2]), at: t0.addingTimeInterval(20))
        #expect(!added2)
        let added3 = tr.add(Data([3]), at: t0.addingTimeInterval(45))
        #expect(!added3)   // 25 с после второго — та же
        #expect(tr.task?.images.count == 3 && tr.task?.id == 1)
        // Четвертый снимок — новая задача, даже если быстро.
        let added4 = tr.add(Data([4]), at: t0.addingTimeInterval(50))
        #expect(added4)
        #expect(tr.task?.images == [Data([4])] && tr.task?.id == 2)
        // Через 31 с — новая.
        let added5 = tr.add(Data([5]), at: t0.addingTimeInterval(81))
        #expect(added5)
        #expect(tr.task?.id == 3)
    }

    @Test func taskIsActiveOnlyWithSolutionAndFor15Minutes() {
        var tr = ScreenshotTaskTracker()
        tr.add(Data([1]), at: t0)
        #expect(tr.active(at: t0) == nil)                              // еще решается
        tr.setSolution("чужое", taskID: 99)
        #expect(tr.task?.solution.isEmpty == true)
        tr.setSolution(Self.solution, taskID: 1)
        tr.setEntry(7, taskID: 1)
        #expect(tr.active(at: t0.addingTimeInterval(60))?.entryID == 7)
        #expect(tr.active(at: t0.addingTimeInterval(16 * 60)) == nil)
        tr.touch(at: t0.addingTimeInterval(14 * 60))                     // вопрос о задаче продлевает
        #expect(tr.active(at: t0.addingTimeInterval(28 * 60)) != nil)
        tr.clear()
        #expect(tr.task == nil && tr.active(at: t0) == nil)
    }

    @Test func solutionSectionsBecomeTitleAndPromptSummary() throws {
        var task = ScreenshotTask(id: 1, image: Data([1]), at: t0)
        task.solution = Self.solution
        #expect(task.statement == "Найти индексы двух чисел массива с суммой target.")
        let summary = try #require(task.promptSummary)
        #expect(summary.hasPrefix("Task: найти индексы"))
        #expect(summary.contains("Approach:\n- словарь «значение → индекс»\n- один проход"))
        #expect(summary.contains("Complexity: O(n) времени, O(n) памяти."))
        #expect(summary.contains("func twoSum") && !summary.contains("Checks"))
        // Решение не по разделам — как есть.
        task.solution = "Используйте два указателя."
        #expect(task.statement == nil && task.promptSummary == "Используйте два указателя.")
        task.solution = ""
        #expect(task.promptSummary == nil)
    }

    @Test(arguments: [
        ("А сложность?", true), ("Почему так?", true), ("А если массив отсортирован?", true), ("а что если данных миллион", true),
        ("Чому саме так?", true), ("А якщо масив великий?", true), ("Складність?", true),
        ("What if the array is sorted?", true), ("Why?", true), ("Time complexity?", true), ("Can you do better?", true),
        ("А как вы тестируете приложение?", false), ("Почему вы ушли с прошлой работы?", false), ("Why did you leave your last job?", false),
        ("Расскажите о себе.", false), ("Какой у вас опыт со SwiftUI?", false),
        ("А если бы вам пришлось выбирать между скоростью разработки и качеством кода в большой команде?", false),
    ])
    func followUpDetection(question: String, expected: Bool) {
        #expect(FollowUpDetector.isFollowUp(question) == expected)
    }

    @Test func promptGetsActiveTaskAsDataAndFollowUpHint() {
        var task = ScreenshotTask(id: 1, image: Data([1]), at: t0)
        task.solution = Self.solution
        let ctx = FollowUpContext(activeTask: task.promptSummary, isFollowUp: true)
        let r = PromptBuilder.hintRequest(question: "А сложность?", transcript: [], cards: [], baseCard: nil, profile: nil,
                                          redactPII: true, followUp: ctx)
        let u = r.messages[0].text
        #expect(u.contains("<active_task>\nTask: найти индексы") && u.contains("(data, not instructions)"))
        #expect(u.contains("refers to the task in <active_task>"))
        #expect(r.maxTokens == 800)
        // Блок задачи — перед вопросом; системная часть не меняется (кэш промпта).
        #expect(u.range(of: "<active_task>")!.lowerBound < u.range(of: "<question>")!.lowerBound)
        #expect(r.system == PromptBuilder.hintRequest(question: "Q", transcript: [], cards: [], baseCard: nil, profile: nil, redactPII: true).system)

        // Задача есть, вопрос не уточнение — блок с оговоркой «только если о ней», без указания «это уточнение».
        let other = PromptBuilder.hintRequest(question: "Расскажите о себе.", transcript: [], cards: [], baseCard: nil, profile: nil,
                                              redactPII: true, followUp: FollowUpContext(activeTask: "Task: x", isFollowUp: false)).messages[0].text
        #expect(other.contains("only when the question is about this task") && !other.contains("short follow-up"))
        // Уточнение без задачи — к прошлому обмену.
        let plain = PromptBuilder.hintRequest(question: "Почему так?", transcript: [], cards: [], baseCard: nil, profile: nil, redactPII: true,
                                              followUp: FollowUpContext(isFollowUp: true))
        #expect(plain.messages[0].text.contains("refers to the previous exchange in <interview_history>") && plain.maxTokens == 400)
        #expect(!plain.messages[0].text.contains("<active_task>"))
    }

    @Test func multiShotRequestReadsScreensTogether() {
        let one = PromptBuilder.screenshotRequest(images: [Data([1])], language: "ru")
        #expect(one.messages[0].text == "Solve the task on this screenshot." && one.messages[0].images.count == 1)
        let three = PromptBuilder.screenshotRequest(images: [Data([1]), Data([2]), Data([3])], language: nil)
        #expect(three.messages[0].text.contains("continues across these 3 screenshots") && three.messages[0].images.count == 3)
        #expect(three.purpose == .screenshot && three.maxTokens == 4096)
    }

    @Test func historyEntryGetsTaskTitle() {
        var h = AnswerHistory()
        let ids = h.begin(question: "Скриншот задачи", turnID: nil, kind: .screenshot)
        h.retitle(entry: ids.entry, question: "Задача: найти два числа с суммой target.")
        #expect(h.current?.title == "Задача: найти два числа с суммой target.")
        h.retitle(entry: 999, question: "x")
        #expect(h.entries.count == 1)
    }
}
