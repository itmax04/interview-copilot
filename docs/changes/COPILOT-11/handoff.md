# COPILOT-11 handoff

ID: COPILOT-11-handoff · Status: **done (0.15.0, build 36) — H-1: the owner's live check** · Updated: 2026-10-25
Branch: `feat/copilot-11-test-call-fixes` (from `feat/copilot-10-theme-language` @ `9dcf965`)
Links: [intent.md](intent.md), [spec.md](spec.md), [plan.md](plan.md)

## Test call analysis (session 2026-10-25T08-22-18, 8 min, 47 questions)
| Metric | Value |
|---|---|
| Answer sources | Groq `gpt-oss-120b` — 42, Gemini `flash-lite` — 4, a bank card — 1 |
| First token | Groq: median 1.5 s, p90 2.1 s; Gemini: median 2.9 s |
| Input tokens per request | 5,345 … 6,960 (median 6,262): profile, instructions, facts, materials, history |
| Groq limit (free) | 8,000 tokens per minute per key → at ~6,300 per request one key handles ~1 request per minute; three keys — ~3–4 requests per minute with questions every 8–10 s |
| Errors in the log | ≈ 30 per-minute 429 refusals (retry-after 1–41 s), 3 Gemini timeouts (4 s) |

**The case with a manual switch (question 8, 07:23:28 UTC).** The turn came when all three Groq keys were rate-limited (12, 21, 37 s),
and `gemini-3.8-flash` and `gemini-flash-lite` did not fit into the 4 s timeout (their first token takes 2.4–3.8 s). The chain went around
once, "gave up" (`no_match`, 6.9 s after the end of the phrase), and the owner pressed "Answer"; the retry got an answer from `flash-lite` in 3 s.
Causes: (1) the chain does not wait for a limit reset that comes in seconds; (2) Gemini is cut off by the 4 s timeout on every
second request, and its model "cools down" for 5 minutes; (3) the parallel launch (`hedgeAfter` 1.5 s with a Groq median of 1.5 s)
fired on almost every request and sent a copy to the second Groq key, spending its per-minute limit; (4) for a screenshot the chain
first tried three Groq keys, which does not accept images (the refusal at 08:16:16), and only then Gemini.

**Works correctly.** Switching between Groq keys (key=1 → 2 → 3, visible in the log), switching to Gemini on a shared limit,
the retry-after hint, no repeated questions, honest answers about gaps (paid ads, After Effects — per the profile
instructions), STAR answers, the answer language (Ukrainian), the end of a question and the pause (`turn_end` ≈ 0.7–0.8 s after speech).

**Noticed but not changed.**
- Recognition on the Mac microphone sometimes distorts the question ("Чем Айа Ю Джис утрясняется…"), but the model restores the meaning from the context.
- Without an instruction the model invents facts about the candidate (the question "Скільки вам років?" → "Мені 27 років", an invented "campaign for
  the Bhutanese market" from a distorted phrase, "mastered Veo in two days" while the bank answer says "did not use"). This follows from
  the COPILOT-08 rule "improvise freely"; for questions about tools it is now limited by rule R-05.
- A 5–7 k token prompt is the main consumer of the Groq per-minute limit. If there are few Groq keys, it is better to add keys or
  shorten the materials/instructions; the prompt itself was not changed.

## Done
- **Chain** (`ProviderChain`):
  - `lastResort` — when all attempts have failed: waits for a key's limit reset (≤ 25 s; keys whose reset is within ≤ 3 s go in chain
    order), tries slow models (timeout/5xx) right away with a `max(3·timeout, 12 s)` timeout, a shared ceiling; a daily limit is not waited for;
    without `health` (the strong model, checks) the behavior is the same as before. Works in the sequential and parallel modes.
  - A parallel request (hedge) — only to another provider (`launch(avoiding:)`); a second key of the same provider — only
    when the first one fails.
  - `LLMProvider.acceptsImages`: Groq, Cerebras and "custom API" do not get a request with a screenshot (Gemini goes right away).
  - `Step.minFirstTokenTimeout`: Gemini steps have a 7 s floor (`ChainFactory.geminiMinFirstTokenTimeout`).
  - `ProviderHealth.keyReadyIn` — in how many seconds a key's limit resets.
- **Prompt** (`PromptBuilder.system`, the "Interview" mode with a profile): to "have you worked with X?" — an affirmative detailed
  answer (4–6 sentences), starting with "Так…", relying on the profile, without invented employers, dates, counts and percentages. The scenario
  `опыт с инструментом` ("experience with a tool") in `--smoke-memory`: 5/5 on Groq (`gpt-oss-120b`); one of the three earlier runs invented the number "8" —
  the wording about numbers was tightened.
- **Overlay**: `PanelResizeHandle` — 6 pt strips on the sides and 18 pt in the corners (a resize cursor, events by
  `NSEvent.mouseLocation`, the panel is not activated), a grip icon in the bottom-right corner; a collapsed panel does not stretch in height;
  the width 280–1000 pt (was 300–520) is remembered through `onResizedByUser` — `apply` no longer brings back the slider width on
  every settings change (that is what got in the way); the height — up to 4,000 pt. The geometry — `PanelResizing` in Core.
- **An interviewer monologue is not a question** (`PromptBuilder`, the "no answer" rule): before the fix the model answered the interviewer's
  story about themselves and the company (a live measurement 0/6: "Дякую, Олено, за представлення, я Олексій…"). Now — "—" (the panel: "Not a question");
  if the story ends with a question or a request — an answer only to that. The `интервьюер…` ("interviewer…") scenarios: 12/12; a regular call — the same rule.
- **"Delete all…"** on the "Questions" tab (`QuestionsView`, `BankController.deleteAllCards`): the confirmation "Delete all questions (N)?",
  unavailable during preparation; the résumé, instructions and materials are not affected.
- Version 0.15.0 (build 36).

## Executor decisions
- A key is not waited for longer than 25 s: longer than that the owner is left without a hint and the answer is no longer needed; then — an error and the "Retry" button, as before.
- The experience rule does not allow inventing **specifics** (employers, dates, numbers): an affirmative answer without numbers withstands
  follow-up questions ("in which project?", "how many?"), and one with numbers does not. The facts about *which tasks* the tool
  was used for are phrased by the model from the profile and general knowledge about the tool.
- The owner's instructions take precedence over the built-in rules (COPILOT-08), so the lines from the **profile instructions** "Не утверждай, что я
  запускал платную рекламу…" ("Don't claim I ran paid ads…") and "After Effects, Premiere, Figma, Photoshop не приписывай…" ("Don't attribute After Effects…"), as well as the paragraph "Чего у меня пока нет…" ("What I don't have yet…")
  in "Facts about me", override the new rule. I did not change the owner's files — this is their data; they remove what is needed in the "Profile" window.
- The 7 s timeout for Gemini is at the chain factory level, not a setting: the user's "First-token timeout" (4 s) stays for the others.

## Checks (2026-10-25)
| Command | Result |
|---|---|
| `swift test` | PASS — 356 tests in 55 suites (new: `ChainResilienceTests` 9, `ExperienceRuleTests` 4, `PanelResizingTests` 5, `EmptyQuestionBankTests` 1) |
| `scripts/run-evals.sh` | PASS — bank, filter-text, memory, materials (5 PASS, 0 FAIL) |
| `scripts/secret-scan.sh` | PASS — 0 findings |
| `scripts/check-localization.sh` | PASS — 793 keys, 0 without a translation |
| `scripts/build-app.sh` | PASS — `dist/InterviewCopilot.app` is signed |
| `--smoke-memory` "experience with a tool" | PASS 5/5 (Groq `gpt-oss-120b`) |
| `--smoke-panel-resize` | PASS — 9/9: 4 sides, 4 corners, the middle (a 401×680 panel) |
| `--smoke-memory` in full | 27/28; the trap scenario "Kafka only in the hint" (the question in a distorted transcript "Ви чи ви згадували, що працювали з Кавкой?") — 14/15 on repeats: the "have you worked with X?" rule sometimes answers "Так…" to the trap; the other scenarios — no failures |

## Acceptance
| AC | Evidence | Status |
|---|---|---|
| AC-01 | `allKeysLimitedThenAnswerAfterReset` (both modes), `slowModelIsGivenTimeWhenNothingElseIsLeft` | PASS in tests; a live check under real limits — H-1 |
| AC-02 | `dailyLimitIsNotWaitedFor` | PASS |
| AC-03 | `screenshotSkipsProvidersWithoutImages` | PASS |
| AC-04 | the live scenario 5/5, `ExperienceRuleTests` | PASS |
| AC-05 | `--smoke-panel-resize`, `PanelResizingTests` | PASS; the mouse drag itself in a live window — H-1 |
| AC-06 | the checks above | PASS |

## Not verified
- Dragging with the mouse in the running app (no screen capture and input in this environment): the strips and their sides were checked
  on the real window, the arithmetic — by tests.
- Waiting for a limit under real key exhaustion — only on test providers.

## Next step
H-1: launch 0.15.0, drag the overlay by the corners and sides, go through the test interview again; remove from the profile instructions
the two lines about paid ads and "don't attribute" (if desired). Then — the decision on merging COPILOT-09…11 into `main`.
