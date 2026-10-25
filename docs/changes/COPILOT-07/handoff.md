# COPILOT-07 handoff

ID: COPILOT-07-handoff · Status: **done (0.4.0, build 23) — awaiting the owner's repeated live test (AC-06)** · Updated: 2026-10-24
Branch: `feat/copilot-07-hardening` (from `feat/copilot-06-session-memory` @ `f76c8ca`)
Links: [intent.md](intent.md), [spec.md](spec.md)

## Steps and commits
| Step | What | Commit |
|---|---|---|
| 1 | Memory by turn number (R-02), "shown is not said" (R-01), references by stems (R-03), "not a question" (R-04), salary (R-05), `exhausted` in the parallel chain (R-09), `<candidate_said>` removed (R-10) | `8622cae` |
| 2 | "I'm answering now" in the menu and panel (R-06), history: start, source, "Your answers", plural forms, permissions 600/700 (R-08), `turn_stall` (R-09) | `39b9805` |
| 3 | `--smoke-memory` (R-11), the instruction after the question (R-01), AI interview answers (R-07) and the owner's refined answers in the memory, version 0.4.0 | `c8e5ad0` |

## Found by the audit (besides the live test)
- A hint looked up its exchange by the question text: the Whisper refinement (~3 s) changed it before a slow provider
  finished the answer — the hint was lost, and with it the replacement of an unrecorded answer (06/R-07). A repeat of the same question wrote
  the hint into the wrong exchange; ⌃⌥C on a refined question saw the current question in its own history.
- The parallel chain (R-36) on an error without a fallback (`.cancelled` from URLSession) finished without `exhausted` — the panel
  stayed in "Preparing a hint…".
- The `<candidate_said>` block and its rule stayed in every system prompt, although no data had gone there since COPILOT-06.
- A session started at app launch: the 08:10 interview was recorded as the session "23:56–08:13" with no source.
- The history window did not show the owner's answers, although they are saved (decision 06/Q1); "1 вопросов".
- History files (transcripts, answers) were created with permissions 644; the voiceprint — already 600.
- The owner's answer in the self-check stayed a Parakeet draft: the Whisper refinement went to the normal branch and was lost.
- AI interview answers did not get into the interview memory — a rehearsed interview had no answer history.
- The "⌃⌥A", "⌃⌥↩", "⌃⌥C" labels in the panel and settings ignored reassigned keys; gray text — contrast below 4.5:1.
- The `turn_stall` counter was not reset on a manual turn (false diagnostics).

## Executor decisions
- Scope — Interview Copilot; the bots in `telegram-bots/` were not touched. The owner's frontend rules do not apply (CLAUDE.md, "Design").
- "Mobile and tablets" — not applicable (macOS); adaptivity — the panel width 300–…, the font, answer scrolling.
- The "do not agree" instruction is in the task after the question: placed before the history, gpt-oss-120b lost it (live run 16/18 → 29/30).
- The answer check in `--smoke-memory` is textual (`PromptScenarios.confirmsPremise`), without a second judge model: cheap and
  repeatable; "Так як…" (= "так как", "since") does not count as agreement.
- No post-processing of the answer (cutting "Так," from the start): the prompt rule passed 5/5, and editing the model's text could
  break legitimate "Так" when the candidate really said it.
- No new dependencies.

## Checks (2026-10-24)
| Check | Command | Result |
|---|---|---|
| Before changes | `swift build && swift test` | 236 tests PASS |
| Tests | `swift test` | **245 tests PASS** (+9: memory by turn, the trap, a fragment, salary, menu, file permissions, chain, answer checks) |
| Evals | `scripts/run-evals.sh` | turn 0%/0% (596 ms) · bank 94.9% / 0% false · filter-text 214/214 · memory 8/8, 0/2 — PASS |
| Audio evals | `scripts/run-evals.sh filter voice` | filter 16/16, lost 1/20, terms 8/8, noise 0/20 — PASS; voice 18/18, 89/96 — PASS |
| Secrets | `scripts/secret-scan.sh` | 0 findings |
| Build | `scripts/build-app.sh` | OK, signature "InterviewCopilot" |
| Live prompt before the fix | `--smoke-memory 3` | 16/18: the trap with a shown hint 1/3 |
| Live prompt after | `--smoke-memory 5` | **29/30**: traps 15/15, return to an answer 5/5, salary 5/5 (USD/month), fragment 4/5 — 1 FAIL: Groq 429 + Gemini 503/429 (limits with 30 requests in a row, not model behavior) |
| Window and menu live | — | NOT RUN: launching the app turns on the owner's microphone without them; checked by the MenuLayout tests |
| Live memory test with ⌃⌥A | — | NOT RUN — AC-06, owner |

## Limitations
- The model's answer is probabilistic: 15/15 on traps does not guarantee 100% on live questions; `--smoke-memory` repeats the check.
- Free limits: 30 requests in ~1 min gave 429 at Groq and Gemini; at a normal interview pace (a question every 10–30 s,
  plus speculative requests) the limit was not reached, but a long series of quick questions can switch the chain to fallback models.
- Parakeet's Ukrainian recognition remains the main source of text errors ("Кавкой", "в Мані"); the Whisper refinement
  sometimes spoils the text ("Повернемося" → "Повернемо себе").

## Next step
Owner: 0.4.0 → "Mac microphone" → "New interview" → questions from the list; after a hint — ⌃⌥A (or the menu "I'm answering now"),
an answer with numbers, ⌃⌥A. Then a review of the history (the "Your answers" section).
