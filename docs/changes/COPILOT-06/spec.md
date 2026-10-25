# COPILOT-06: Specification — interview memory

ID: COPILOT-06-spec · Status: **accepted** (2026-10-23) · Version: 1 · Date: 2026-10-23 · Owner: itmax04
Links: [intent.md](intent.md) · [handoff.md](handoff.md)

## Requirements
- **R-01. Exchanges.** Each interviewer turn (01/R-05) is a new exchange; the owner's microphone phrases on a call (05/R-07) that passed
  the filters are its answer; the hint shown is `hint` (for review). `InterviewMemory`, `SessionExchange`.
- **R-02. Short memory.** The request gets the 4 last exchanges in full (question ≤ 300, answer ≤ 500 characters), an `<interview_history>` block
  with "N min ago". The current question is not in the history.
- **R-03. Long memory.** Older exchanges are indexed with bge-m3 (the same model as the bank, locally); for a question — up to 3 similar ones
  (threshold 0.55) in an `<earlier_in_interview>` block. A reference to the past ("вернёмся", "вы говорили", "раніше", "earlier you mentioned"…)
  — threshold 0.35 and a note for the model (`ReferenceDetector`).
- **R-04. No inventions.** A prompt rule: rely on the history, do not contradict or repeat it; do not invent past answers —
  if a reference is not found, answer on the merits without "as I said". An answer without a recording — "(answer not recorded)".
- **R-05. Sessions.** A new session — launch, a change of the call app, silence between turns > 30 min, the "New interview" menu item:
  the previous session is saved to the history (`SessionRecord.exchanges`), the memory is cleared. Old history files are readable.
- **R-07. The hint instead of an unrecorded answer** (2026-10-23, after the live test). If the owner's answer is not recorded,
  the history gets the hint shown (≤ 300 characters, no markup) marked "suggestion shown on screen, may not have been
  said": facts (numbers, technologies, names) stay consistent, but the model does not claim the candidate said it.
- **R-08. "I'm answering now" in the self-check** — ⌃⌥A (reassignable in Hotkeys). In the "Mac microphone" mode speech until the second
  press is the owner's answer into the memory (not a question, no turn and no hint); the panel shows "Your answer is being recorded". It turns off when
  the source changes; not needed on a call (answers are heard through a separate channel).
- **R-06. Data.** The history is local, retention R-18 (30 days); the request goes through the PII filter (01/R-12); no text is written to logs.

## Acceptance criteria
| AC | Criterion | Check |
|---|---|---|
| AC-01 | Returns to early topics (explicit and implicit) find the right exchange — all cases of the set | `memory` eval |
| AC-02 | New topics do not pull in old exchanges — no more than 1 case | `memory` eval |
| AC-03 | Prompt: history blocks as data, the "do not invent" rule, the PII filter | `swift test` |
| AC-04 | Sessions are isolated, old history files are readable | `swift test` |
| AC-05 | In a live interview a return to a topic after 20+ min gives a hint based on what was said | owner |
