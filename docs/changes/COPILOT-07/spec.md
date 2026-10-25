# COPILOT-07: Specification — audit and finishing

ID: COPILOT-07-spec · Status: **accepted** (2026-10-24) · Version: 1 · Date: 2026-10-24 · Owner: itmax04
Links: [intent.md](intent.md) · [handoff.md](handoff.md)

## Requirements
- **R-01. Shown is not said.** In the prompt history an answer without a recording is `Candidate: (not recorded)`, the hint shown is
  a separate line `Shown suggestion (may not have been said)`. The model checks a reference to the past ("Ви згадували…?")
  only against `Candidate:` lines; without them it does not agree ("Так", "Да", "Yes", "as I said" are forbidden at the start of the answer).
  The instruction is placed right after the question (in the task), not before the history. Refines 06/R-04, 06/R-07.
- **R-02. An exchange by turn number.** `SessionExchange.turnID`: a hint finds its exchange even if the Whisper refinement has already
  replaced the question text or the same question was asked twice; the current turn is not in its own history. Old history files are readable.
- **R-03. References by word stems.** `ReferenceDetector`: "повернемо", "повернімо", "ви згадува", "ви казал", "вы говорил",
  "вы упоминал", "you were saying"… (the live text "Повернемо себе до…" is a reference).
- **R-04. Not a question.** Fragments that only announce a question ("Є таке питання", "У меня вопрос", "I have a question") get
  the answer "—"; such an exchange without an answer is removed from the memory.
- **R-05. Salary without a profile** — a market range for the role and level, per month, gross, in USD (unless the conversation sets a currency).
- **R-06. "I'm answering now" is visible.** In the self-check ("Mac microphone") a menu item "I'm answering now / Finish my answer"
  with a hotkey and a hint in the panel footer; key labels everywhere come from the current shortcuts.
- **R-07. AI interview answers go into the memory**, like answers on a call.
- **R-08. History.** A session without content starts with the first line and gets the source name; the window has a
  "Your answers" section; the plural forms "вопрос/вопроса/вопросов". History files — permissions 600, folder 700 (old ones are fixed at launch).
- **R-09. Reliability.** The parallel chain: an error without a fallback ends with `exhausted` (the panel does not stay in
  "Preparing a hint…"). The `turn_stall` diagnostic counter is reset on any turn.
- **R-10. Cleanup.** The unused `<candidate_said>` path (`CandidateContext`) was removed: since COPILOT-06 the owner's answers go into
  the interview memory, but the block and its rule were still in every request. The text of the "Use my answers" setting was updated.
- **R-11. A live prompt check** — `--smoke-memory [N]`: synthetic scenarios through the chain from the settings, automatic
  text checks (`PromptScenarios`).

## Acceptance criteria
| AC | Criterion | Check |
|---|---|---|
| AC-01 | The "you mentioned" trap is not confirmed — both without history and when the term is only in the hint shown | `--smoke-memory` (≥ 5 runs) |
| AC-02 | A return to a recorded answer keeps its facts; salary — a range in USD; a fragment — "—" | `--smoke-memory` |
| AC-03 | A hint is bound to its turn after the text refinement; a fragment is removed; history file permissions | `swift test` |
| AC-04 | The "I'm answering now" item only in the self-check, with a hotkey | `swift test` (MenuLayout) |
| AC-05 | No regressions: tests, the turn/bank/filter-text/memory evals, secret-scan, the .app build | the full CLAUDE.md check |
| AC-06 | A repeated live memory test with ⌃⌥A records answers and gives hints based on them | owner |
