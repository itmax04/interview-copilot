# COPILOT-01: Completion report

Status: **ready for acceptance (H-5)** · Date: 2026-10-07 · Branch: `feat/copilot-01` · Executor: Claude Code
Links: [spec.md](spec.md) (AC-01…AC-14), [plan.md](plan.md), [handoff.md](handoff.md) (full log of checks and decisions),
[test-plan.md](test-plan.md) (what and how to test next), [ADR-0001](../../decisions/ADR-0001-stack.md).

## Summary
`dist/InterviewCopilot.app` builds, signs and runs on a MacBook Air M1 8 GB: it listens to Meet in Chrome,
transcribes uk/ru/en, finds the answer in the bank or generates a hint through Gemini, and takes a screenshot of a task.
Speed (AC-01…AC-03) and memory (AC-05) are within limits on a live call. **The main limitation is transcription accuracy
on compressed Meet audio from a phone** (AC-10: the owner's assessment "better, but inaccurate"), details below.

## Launch
```bash
open ~/Desktop/1/interview-copilot/dist/InterviewCopilot.app
```
Parrot in the menu bar → menu; floating panel — ⌃⌥H. First launch — a wizard (permissions → Gemini key → models).
Rebuild: `scripts/build-app.sh` (needs the "InterviewCopilot" / "InterviewCopilot Dev" signing certificate).

## Acceptance criteria
Call metrics — `scripts/metrics.py --start "2026-10-07 11:00:00"` (H-4, attempt 3, whisper medium, questions in Russian).

| AC | Criterion | How checked | Result | Evidence |
|---|---|---|---|---|
| AC-01 | Utterance text ≤ 1 s after the phrase ends (median) | Meet call phone → Mac, `scripts/metrics.py` | **PASS** (ru/uk) | Median 684 ms, p90 956 ms, n=24 (attempt 3); attempt 1 — 511 ms. Synthetic medium: ru 846 ms, uk 1140 ms (single-language session) |
| AC-02 | A card ≤ 0.5 s after the turn completes (median) | Same | **PASS** | 84 ms, p90 86 ms, n=4; through speakers — 0.09–0.13 s (n=5) |
| AC-03 | First words ≤ 2.5 s (median, Gemini Free) | Same | **PASS** | 978 ms, p90 1592 ms, n=11 (Gemini Flash-Lite after skipping the slow 3.8 Flash). Before the fix — 4850 ms (FAIL, attempt 1) |
| AC-04 | ≥ 85% of paraphrases, ≤ 10% false | `scripts/run-evals.sh bank` | **PASS** | bge-m3, threshold 0.74: top-1 94.9% (uk 13/13, ru 12/13, en 12/13), false 0/12, top-3 100%; holdout set 91.7% / 0% |
| AC-05 | Memory ≤ 1.5 GB over 10 minutes | `scripts/footprint-monitor.sh 10` | **PASS** (with a caveat) | 10 minutes in a row: maximum 1119 MB (app running, listening to Chrome, no speech); on the call — 1166 MB, peak 1172 MB (not 10 minutes of continuous speech) |
| AC-06 | No keys or personal data in the repository | `scripts/secret-scan.sh` (tree, index, full history) + `.gitignore` | **PASS** | "0 findings"; self-test on planted keys/email/phone — 5/5 found |
| AC-07 | 429/invalid Gemini key → the next provider with a label; without keys — a clear error | Unit tests (mock, SSE fixtures) + live failures | **PASS** (mock) / manual check with an invalid key **NOT RUN** | 22 ProviderChain/provider tests; live: 503 "high demand", 429 quota, a 4 s timeout on gemini-3.8-flash → fallback to Flash-Lite with the label "Gemini (gemini-flash-lite-latest)". DeepSeek/Anthropic live — NOT RUN (no keys) |
| AC-08 | Three modes per S-01…S-03 | AnswerRouter unit tests + call | **PASS** | `AnswerRouterTests` (3 tests); live: a bank card (S-01), "Not in the bank" in Question bank only, generation in Bank + hint (S-03) |
| AC-09 | Hotkeys while Chrome is active; the panel does not take focus | Manual check | **Partial** | Focus: `lsappinfo front` before/after showing the panel — unchanged (PASS). Key presses while Chrome is active — the executor cannot send synthetic key presses; logs show the owner used ⌃⌥S. Owner confirmation — H-5 |
| AC-10 | uk/ru/en: ≥ 4 of 5 phrases understandable per language, correct language | Owner assessment on a call | **FAIL / needs a decision** | Owner: "already better, but still inaccurate". Cause — compressed Meet audio from a phone in the same room (Chrome captions were even worse on it). Done: whisper medium instead of small, gain for quiet audio, conversation language. English live — NOT RUN (owner's decision). See "Limitations" |
| AC-11 | The menu matches menu-v2.webp with the R-15 deviations | Owner's screenshot | **PASS** (awaiting confirmation) | [evidence/menu-2026-10-06-owner.png](evidence/menu-2026-10-06-owner.png); order and deviations (⌃⌥, "soon", UK/RU/EN, request counter) — `MenuLayoutTests` |
| AC-12 | History is saved, deleted and purged by retention | `SessionStoreTests` | **PASS** | 5 tests: save/load, unique IDs, delete one and all, 30-day retention, no audio fields; live — `sessions/*.json` |
| AC-13 | Without permission — the no-permission state, no crash | Log + code; visually — owner | **Partial** | Log `no screen capture permission`, process alive, the permissions window opened by itself (2026-10-06 22:17). Not visually confirmed by the owner before granting permissions — check at H-5 (see test-plan.md) |
| AC-14 | `swift build`, `swift test`, `scripts/build-app.sh` on a clean clone | Clone from GitHub into an empty folder | **PASS** | See "Clean clone" below |

## Clean clone (AC-14)
The first attempt (commit `d046738`) **failed**: `.gitignore` with the pattern `models/` (macOS, case-insensitive) hid
`Sources/CopilotCore/Models/ModelDownloader.swift`. Found by the P-13 review, fixed (`/models/`), the file added in `cc1c06e`.
Rerun on commit `cc1c06e` (clone from GitHub into an empty scratchpad folder):
`swift build` — Build complete (35 s); `swift test` — 143 tests in 21 suites PASS; `scripts/build-app.sh` — OK,
`codesign -dvv` → `Identifier=com.itmax04.interviewcopilot`, `Authority=InterviewCopilot`; `scripts/secret-scan.sh` — 0 findings.

## Independent review (P-13)
`/code-review high` on the branch against spec.md and CLAUDE.md — 10 findings, **all fixed** in `cc1c06e`, each with a regression test:
1. P0 — `ModelDownloader.swift` not in Git (AC-14) → `.gitignore` patterns anchored with `/`.
2. P1 — a new utterance interrupted the final of the previous one (text was lost) → only the partial pass is interrupted.
3. P1 — "Turn back on" in Budget was immediately undone → the limit fires only when crossing the threshold.
4. P1 — pause did not cancel generation and let a queued final through (S-08) → generation is cancelled, a pause "epoch".
5. P1 — after a pause the turn detector kept "owner speaking"/waiting for an old phrase → full reset.
6. P1 — the PII filter cut years ("2019-2022"), numbers and technology names → precise phone and link patterns.
7. P1 — bank cards went to the model without the PII filter (R-12) → the filter applies to cards too.
8. P2 — a 404 (typo in a model ID) broke the chain → any HTTP error moves to the next provider.
9. P2 — the AC-03 metric mixed hints with screenshots and the strong model → `kind=hint`.
10. P2 — Gemini cached tokens were counted twice → the cache is subtracted for Gemini and DeepSeek.

## Checks (final run)
| Command | Result |
|---|---|
| `swift build` | PASS |
| `swift test` | PASS — 143 tests in 21 suites (Swift Testing) |
| `scripts/run-evals.sh` | turn: 36 cases, premature 0%, missed 0%; bank: 94.9% / 0% |
| `scripts/secret-scan.sh` | 0 findings |
| `scripts/build-app.sh` | `dist/InterviewCopilot.app`, `Authority=InterviewCopilot` |
| `scripts/fetch-models.sh` | SHA256 matches for all models |

## Added at the owner's request (2026-10-07)
**The self-check mode "Microphone (practice, no call)"** — the Listening menu or Settings → Audio: the owner speaks into the Mac
microphone without Meet, the app transcribes the question and answers (a card or a hint). The Screen Recording permission is not needed,
only the microphone. This extends R-01; R-02 applies to calls. Checked via speakers → microphone: cards 74–102 ms after the turn,
a hint in 0.83 s.

## Limitations and risks
1. **Transcription accuracy on compressed audio (AC-10).** Medium is the largest model that fits 1 s and 1.5 GB on an M1 8 GB.
   The owner chose it (option 1) over large-v3-turbo (2–2.5 s, ~1.8 GB). What helps: choosing the language in the Language menu;
   the other person on a laptop/headset; the phone not in the same room as the Mac. Frequent ru ↔ uk switches within a call are a weak spot.
2. **Free Gemini quota.** The main `gemini-3.8-flash` on a free key answered 503/429/slowly; the chain moves to
   `gemini-flash-lite-latest` (a separate quota). The executor used up the daily 3.8 Flash quota with measurements on 2026-10-06.
3. **Keychain and a self-signed certificate.** After every rebuild macOS asks once for access to the key
   ("Always Allow"). This goes away if the owner marks the certificate as trusted for code signing (the executor did not change trust).
4. **Memory 1.1–1.2 GB** of 1.5: ~300 MB of headroom. If the Mac slows down — Settings: model `ggml-small-q5_1.bin` (0.5 GB, less accurate).
5. **Not checked live:** DeepSeek and Anthropic (no keys), English questions on a call, ⌃⌥C, AC-13 visually,
   ⌃⌥H/⌃⌥↩ while Chrome is active. All listed in [test-plan.md](test-plan.md).
6. **Dependencies outside ADR-0001: none.** Models (whisper medium/small, bge-m3) — from official repositories with SHA256.

## What the owner needs to do for H-5
1. Go through the acceptance checklist in [test-plan.md](test-plan.md), section "Owner acceptance" (≈ 15 minutes).
2. Decide on AC-10: accept the current accuracy with the recommendations or request another iteration (a larger model / cloud recognition — a separate intent).
3. Accept the NOT RUN items: live DeepSeek/Anthropic until keys are available.
4. Merging into `main` and a PR — only on a separate command from the owner.

## Local recognition — update 2026-10-08, v0.1.1

Owner priority: RU/UK/EN accuracy on an M1 8 GB, a free local option first.
The main engine is now Parakeet v3 via FluidAudio 0.17.7; the alternative is Whisper large-v3-turbo
with full context for the final text. Selected in Audio, no restart. Cloud recognition is not used.

On the first 10 test recordings of Google FLEURS per language (30 files, 575 words, CC BY 4.0):

| Mode | Errors | WER | UK | RU | EN |
|---|---:|---:|---:|---:|---:|
| Old medium, reduced | 54 | 9.39% | 15.29% | 9.28% | 4.74% |
| Medium, full | 46 | 8.00% | 15.88% | 5.67% | 3.79% |
| Turbo, full | 27 | 4.70% | 7.65% | 2.58% | 4.27% |
| Parakeet v3, built-in adapter, Auto | 26 | 4.52% | 4.71% | 4.12% | 4.74% |

Source: https://huggingface.co/datasets/google/fleurs, configs uk_ua/ru_ru/en_us,
parquet revision 168de341b3db6859a9bac1c50a2ef5e3b47647e0. WER ignores case and punctuation;
numbers in words and digits are not equated. The human recordings are kept outside Git.
The Parakeet/Turbo difference is one error; superiority on arbitrary calls is not proven.
Synthetic set: 24 files, 511 words (quieter, AAC 8 kHz, noise, long questions and negations):
old medium — 3 errors, medium full — 2, Turbo and Parakeet — 0.

The built-in adapter was checked on all 54 files. After removing the token cap, the final Turbo was rechecked
on the 30 human files: the same 27 errors. An EN → RU → UK stream through StreamingTranscriber:
3/3 texts and languages correct, 14 partials, latency to final 461/486/519 ms (median 486 ms).
This is real-time file feeding; capturing a real call was not checked.

Fixed: snapshotting the audio/language of a closed phrase before queueing, VAD positions inside a block,
keeping several phrases from one block, full Whisper context for the final and the token limit for the final.
The interim Whisper stays fast. Parakeet does not use competing uk/ru passes
and does not restrict the alphabet — English terms may stay inside a Cyrillic phrase.
Results of the old model are not delivered after switching; downloading does not resume on quit.
Pinned Parakeet model: 23 files, 460 MiB, SHA256 verified by the installer.
The original keys, profile and history were not changed.

PASS: 151 tests; turn eval 36 cases; bank eval top1 94.9%, top3 100%, false 0/12;
secret scan 0 findings; app build 0.1.1 (build 2) and codesign --verify --strict.
NOT RUN: the owner's live microphone/call, language mixing inside a phrase through capture,
the app's total memory on a call, visual acceptance of Audio and identical audio on parakeet-ai.com.
AC-10 stays at H-4; AC-01 for the accurate Whisper may exceed 1 s, which matches
the owner's new priority "accuracy over latency".

Repeatable test: `scripts/eval-local-stt.py /path/manifest.json /path/results.json`.
Manifest: an array of objects id/language/condition/path/expected. Keep the owner's data outside Git.
Installing the pinned models: `scripts/fetch-parakeet.py`; dependencies and decisions — ADR-0001.


## Test call — 2026-10-08, v0.1.2

A free local mode with fixed voices in the browser; it checks real audio capture,
not feeding a file directly into STT. 15 synthetic phrases, 5 per language; audio mono16k PCM,
800 ms of silence before the phrase and 700 ms after. Conditions: a normal question, a negation, quiet speech,
call compression, technology names and a number. Chrome browser, Parakeet v3 engine.
WER: word edit distance, case/punctuation ignored, ё=е, apostrophes normalized;
numbers keep their original spelling. For example, "two point four" → "2.4" increases the raw WER
even when the meaning is preserved. The synthetic pronunciation of names also affects the result.

| Language | Phrases | Words | Errors | Raw WER | Median STT after speech |
|---|---:|---:|---:|---:|---:|
| RU | 5 | 96 | 7 | 7.29% | 517 ms |
| UK | 5 | 97 | 9 | 9.28% | 501 ms |
| EN | 5 | 123 | 4 | 3.25% | 495 ms |
| All | 15 | 316 | 20 | 6.33% | 501 ms |

System problems 0/15. Without technical phrases: RU 0/77, UK 2/78, EN 0/101.
The JSON was saved with the browser button and checked: all 15 results. Synthetic results
do not prove the same accuracy in a live interview and are not a comparison with Parakeet AI.
Unclear human speech and noise are not measured yet; the next step is identical recordings with a reference
for Parakeet and Whisper, especially negations, names, numbers and technical terms.

PASS: 157 unit tests; bank/turn eval; secret scan 0; strict app signing; local routes,
WAV byte ranges and unchanged audio resources; rejection of a wrong Origin/Host/token,
paths to arbitrary files, a repeated begin and a stale ended; cancel and close;
saved user settings matched before/after the final control test.
Details of the full audio run boundary and the final changes — handoff.md.
