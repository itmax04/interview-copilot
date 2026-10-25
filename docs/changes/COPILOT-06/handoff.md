# COPILOT-06 handoff

ID: COPILOT-06-handoff · Updated: 2026-10-23 · Branch: `feat/copilot-06-session-memory` (from `feat/copilot-05-speech-filter` @ `ff1b27b`)
Links: [intent.md](intent.md), [spec.md](spec.md)

## Done (version 0.3.0, build 20)
- `InterviewMemory` / `SessionExchange` / `MemoryContext` / `ReferenceDetector` (CopilotCore/Memory); the
  `<interview_history>` and `<earlier_in_interview>` blocks in the prompt, the "do not invent past answers" rule.
- The history context is computed in the background before a request (normal, speculative, strong model); embeddings — the bank's bge-m3.
- `SessionRecord.exchanges` with compatible reading of old files; "New interview" in the menu; automatic boundaries: a change of the call
  app, silence > 30 min.
- The `<candidate_said>` block (05/R-07) is no longer sent: the owner's answers are already in the history exchanges.

## Checks
- `swift test` — 233 tests PASS (+10: memory, references, prompt, history compatibility, menu).
- The `memory` eval — returns to a topic 8/8 (6 with an explicit reference, 2 implicit), new topics without extra old ones 0/2 — PASS.
- The turn / bank / filter-text evals — unchanged.
- NOT RUN: a live 30+ minute interview (AC-05).

## Executor decisions
- The owner's answers in the AI interview do not go into the memory (their own path 03/R-32) — a candidate for the next iteration.
- The 0.55 / 0.35 thresholds — from the `memory` eval; on live misses — tuning on the owner's recordings.

## The owner's live test (2026-10-23 23:36–23:40, v0.3.0) and review
- Source — "Mac microphone" (self-check): the owner read the questions, answers are not recorded (in this mode the microphone is
  the interviewer). Session: 21 exchanges, 0 answers, 21 hints. The "remembers my answer" check is not covered — a call (Meet) is needed.
- Voice: all phrases accepted, similarity 0.63–0.83 (the sample was re-recorded on the Mac microphone — the boundary is reliable).
- Bug: the trap "Ви згадували Kafka" — the hint "Так, я активно працював із Kafka". Cause: with a reference and a non-empty
  short memory the prompt said "use the matching exchange above". Fixed (0.3.1): with nothing found on the topic — "the candidate did not
  say this, do not confirm the premise"; with something found — "do not confirm if it is not there".
- Bug: the memory got the Parakeet draft text, not the Whisper refinement. Fixed: `InterviewMemory.reviseText`
  on the `revised` event.
- Observation: without recorded answers the model improvises numbers (rule 04/R-05) and does not see its past hints
  (only real answers go into the prompt) — the salary from hint #8 was not repeated in #16. A candidate for improvement:
  pass the hint shown when the answer is not recorded, marked "suggested, not necessarily said".
- Checks 0.3.1 (build 21): 234 tests PASS; the memory eval 8/8, 0/2.

## Improvements at the owner's request (0.3.2, build 22)
- R-07: `MemoryContext.Item.shownHint` — the hint instead of an unrecorded answer; the prompt rule "do not claim it was said".
- R-08: `HotkeyAction.ownerAnswer` (⌃⌥A, at the end of allCases — the numbers of earlier keys do not change), `ListeningController.ownerAnswering`,
  an indicator in the panel.
- Checks: 236 tests PASS; the memory eval 8/8, 0/2. NOT RUN: a live self-check with ⌃⌥A.

## Live test 0.3.2 (2026-10-24 08:10, "Mac microphone", Українська, 16 questions)
- ⌃⌥A was not pressed (no "owner answering" in the log), answers were not recorded — the memory of answers was not checked.
- The hint instead of an answer works: the salary from hint #4 was repeated in #12, mentoring in #13 is consistent with #7.
- The Kafka trap: "Так, я працював з Kafka" — Kafka was only in the hint shown as #14. The fragment "Є таке питання."
  got a placeholder. "Повернемо себе до…" was not recognized as a reference. Fixes — [COPILOT-07](../COPILOT-07/spec.md).
