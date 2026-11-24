# COPILOT-15 — H-1 report
Date: 2026-11-21 · Commit: `e8fcd2a` · App version: `0.15.1 (37)` · Machine: Apple M1 · Provider worked: yes (Groq `openai/gpt-oss-120b`)

> **Scope note:** Part A was executed end-to-end by the agent using synthetic audio. For Part B, the owner requested measurement without their participation ("замерь без меня"); therefore, B.1 (10 Ukrainian questions + spare #11) and B.6 metrics were executed as a **synthetic-voice dry run (`say -v Lesya`)** via All system audio. All criteria that strictly require the owner's real voice or explicit decision (real-voice AC-10, Fallback B owner decision, live B.3 owner answers, optional B.4 rehearsal owner half, B.5 thresholds feel) are recorded as **NOT RUN**.

## Preparation and settings
| # | Result | Observed |
|---|---|---|
| 0.1 | PASS | Branch `feat/copilot-15-accurate-turns`, HEAD `e8fcd2a` (after `27692b1`), clean working tree |
| 0.2 | PASS | `swift build && swift test` exited 0: 470 tests in 83 suites passed (16.8 s) |
| 0.3 | PASS | `scripts/build-app.sh` exited 0 (62.1 s); `dist/InterviewCopilot.app` built and signed (`InterviewCopilot`) |
| 0.4 | PASS | No prior `InterviewCopilot` process running |
| 0.5 | PASS | All 8 fixtures present in `evals/audio/stt-dense/*-full.wav` (`en1, en2, ru1, ru2, uk1–uk4`) |
| 0.6 | PASS | `open dist/InterviewCopilot.app` launched cleanly; menu bar icon present; no app permission dialogs |
| 0.7 | PASS | `T0 = 2026-11-21 14:36:04` |
| 1.1 | PASS | «Пауза конца вопроса T»: **1000 ms** (schema 7 migration from 700 succeeded) |
| 1.2 | PASS | «Пауза после вопроса со знаком «?»: **600 ms** (schema 7 migration from 350 succeeded) |
| 1.3 | PASS | `Parakeet v3 — локально` + Whisper turbo ON; Today status: `"Распознавание: Parakeet v3 + уточнение Whisper turbo"`. Note: «Уточнять через Whisper и русский/английский» was also ON |
| 1.4 | PASS | «Начинать ответ заранее, не дожидаясь паузы»: **ON** |
| 1.5 | PASS | «Учитывать мои ответы в подсказках (на созвоне)»: **ON** |
| 1.6 | PASS | «Репетиция с собеседником»: **OFF** (enrolled voiceprint present from 2026-10-23, manual threshold `0.60`, «Только мой голос в микрофоне» ON) |
| 1.7 | PASS (adjusted via UI) | Initially set to `Українська` (audio source initially `Микрофон Mac`); switched via UI to `Авто (UK/RU/EN)` and `Весь системный звук` for Part A |

## Part A
| # | Result (PASS/FAIL/NOT RUN) | Observed (numbers, short reason) |
|---|---|---|
| A.1 | PASS | Groq (`openai/gpt-oss-120b`) responded to synthetic `Milena` question; hint card appeared with leading `❓` understood-question line (`first_token` 12.9 s cold start on Turn 1) |
| A.2.1 | NOT RUN | Overlay sets `sharingType = .none` (invisible to `screencapture`), so ~50% opacity and absence of animation could not be verified visually; AX snapshots confirmed incremental provisional text updates during speech before turn replacement |
| A.2.2 | PASS | Each of the 8 questions collapsed to **1** final line in the transcript strip after turn completion |
| A.2.3 | PASS | 6 word errors / 156 reference words (3.8% WER; 5 sub, 1 ins, 0 del); **0 words lost at phrase cuts** |
| A.2.4 | FAIL | Understood-question line (`❓` / `Понятый вопрос:`) appeared on A.1 (Turn 1) but was **absent on 0 / 8** A.2 cards (Turns 2–9) |
| A.2.5 | PASS | Copy button tested on Turn 1 (which displayed `Понятый вопрос:`) and Turn 9 (`en2`): `pbpaste` excluded `❓` on both |
| A.2.6 | PASS | Exactly **8** `turn_end` events (turns 2–9); 0 splits, 0 merges |
| A.2.7 | FAIL | **13 `redecode` lines** on 8 turns (expected 8); all 13 `source=ring`, `decode_ms` median **138 ms** (p90 **195 ms** ≤ 2000), `redecode_failed=0`. Five `?`-ended turns (turns 4, 6, 7, 8, 9; 600 ms pause) triggered duplicate re-decodes because `redecodeQuestion` caches only completed results without in-flight coalescing while `DraftGate` raced `TurnController.emit` |
| A.2.8 | PASS | A.2 `C15 redecode decode_ms` median **138 ms** ≤ 2000 (PASS); `AC-03 turn_end → first_token` median **936 ms** (p90 1256 ms) ≤ 2500 (PASS); `AC-01` median **496 ms** ≤ 1000 (PASS); `C4-AC-01 speech_end → first_token` median **1589 ms** (p90 1898 ms; exceeds legacy 1000 ms script threshold, within COPILOT-15 AC-03 spec budget ≤ 3000 ms / p90 ≤ 5000 ms) |
| A.2.9 | PASS | `draft_start=2, draft_used=2, draft_cancelled=0` in A.2 (turns 2–3, 1000 ms pause); `7/7` adopted across full Part A. Note: 6/8 `?`-ended turns in A.2 missed the draft window due to the A.2.7 race |
| A.2.10 | PASS | 8 `whisper_history` lines (uk: 3 `applied`, 1 `unchanged`; ru/en: 4 `applied` because `whisperReviseAllLanguages` was ON); every line occurred strictly after its `turn_end` (+2591 to +2893 ms); hint card body byte-identical from +1.5 s to +8.0 s |
| A.2.11 | PASS | Per-question memory flat across all 8 questions (`1013 → 1027–1035 MB`, peak 1035 MB); `scripts/footprint-monitor.sh 10` peak **1047 MB** ≤ 1536 MB (PASS) |
| A.3.1 | NOT RUN | Enrolled owner voiceprint present (`2026-10-23`, threshold `0.60`); synthetic `Lesya` rejected/inaudible (`mic_db=-50 dB`, `owner_speaking=false`). Covered by B.3 (requires real owner voice) |
| A.3.2 | NOT RUN | Same as A.3.1 (note: one incidental mic event during A.1 logged `owner_final words=4 phrases=1 redecoded=true` with `redecode turn=-1 decode_ms=71` and no Whisper revision) |
| A.3.3 | NOT RUN | Same as A.3.1 |
| A.4 | PASS | Rehearsal ON + Mac microphone: synthetic `Milena` scored `voice_speaker owner=false similarity=0.40`, produced `turn_end` + `redecode` (`source=joined`, 92 ms) + Groq hint card, and 0 `owner_final mode=rehearsal`. Rehearsal toggle restored to OFF |
| A.5 | PASS | Pause pressed <0.2 s after `ru1-full.wav`: no hint card, no `turn_end`, no crash; after resuming («Продолжить слушать»), `ru2-full.wav` produced `turn_end`, `redecode` (130 ms), and Groq hint normally |

### `metrics.py` table for Part A (A.2 8-question replay: `14:48:01`–`14:50:41`)
```
| Метрика | n | медиана, мс | p90, мс | порог (медиана) | результат |
|---|---|---|---|---|---|
| AC-01 phrase_end → transcript_final | 8 | 496 | 564 | ≤ 1000 | PASS |
| AC-02 turn_end → card_shown | 0 | — | — | ≤ 500 | NOT RUN |
| AC-03 turn_end → first_token | 8 | 936 | 1256 | ≤ 2500 | PASS |
| C15 redecode decode_ms | 13 | 138 | 195 | ≤ 2000 | PASS |
| C4-AC-01 speech_end → first_token | 8 | 1589 | 1898 | ≤ 1000 | FAIL |

Опережающие запросы: начато 2, пригодилось 2, отменено 0
  первые слова с опережающим запросом: медиана 1412 мс (n=2)
  первые слова без него: медиана 1640 мс (n=6)

Языки итоговых реплик: {'en': 2, 'ru': 2, 'uk': 4}
```

### `metrics.py` table for full Part A (`T0 = 14:36:04`–`14:57:25`)
```
| Метрика | n | медиана, мс | p90, мс | порог (медиана) | результат |
|---|---|---|---|---|---|
| AC-01 phrase_end → transcript_final | 23 | 498 | 789 | ≤ 1000 | PASS |
| AC-02 turn_end → card_shown | 0 | — | — | ≤ 500 | NOT RUN |
| AC-03 turn_end → first_token | 17 | 1060 | 2054 | ≤ 2500 | PASS |
| C15 redecode decode_ms | 25 | 127 | 164 | ≤ 2000 | PASS |
| C4-AC-01 speech_end → first_token | 17 | 1683 | 2702 | ≤ 1000 | FAIL |

Опережающие запросы: начато 7, пригодилось 7, отменено 0
  первые слова с опережающим запросом: медиана 1428 мс (n=7)
  первые слова без него: медиана 1914 мс (n=10)

Языки итоговых реплик: {'en': 5, 'ru': 10, 'uk': 8}
```

Per-question word errors (A.2.3, 6 / 156 total, 0 phrase-cut deletions): `uk1` 2 (`Kubernetes`, `пам'яттю`), `uk2` 1 (`PostgreSQL`), `uk3` 0, `uk4` 0, `ru1` 1 (`продакшене`), `ru2` 0, `en1` 0, `en2` 2 (`PostgreSQL` → 2 words).

## Part B
> **Synthetic-voice dry run only (`say -v Lesya`, All system audio, `T1 = 2026-11-21 18:09:12`–`18:13:20`).** Real owner voice was NOT run because the owner asked to measure without them.

| Q | Understood line (synthetic dry run) | One turn | Language uk | Terms ok (synthetic `Lesya`) |
|---|---|---|---|---|
| 1 | yes (shown, matches) | yes (1) | yes (`uk`) | n/a (`проект`→`проєкт` in Whisper) |
| 2 | no (shown, but LLM hallucinated Q1 legal topic due to garbled `iOS-застосунку`) | yes (1) | yes (`uk`) | no (`iOS-застосунку` misheard in Parakeet & Whisper) |
| 3 | partly (shown; `Swift` ok, `async/await` → `wait-групи`) | yes (1) | yes (`uk`) | no (`Swift` ok, `async/await` misheard in both) |
| 4 | yes (shown, exact match) | yes (1) | yes (`uk`) | yes (`баг`) |
| 5 | no (shown, kept garbled `UI-тести`) | yes (1) | yes (`uk`) | no (`UI-тести` misheard; `модульні тести`, `снапшоти` ok) |
| 6 | yes (shown; LLM repaired `дейблайн` → `дедлайн`) | yes (1) | yes (`uk`) | partly (STT `дейблайн`, LLM repaired `дедлайн`) |
| 7 | yes (shown, matches) | yes (1) | yes (`uk`) | yes (Parakeet `кодрев'ю`, Whisper `код-рев'ю`) |
| 8 | no (`❓` line omitted by LLM) | yes (1) | yes (`uk`) | yes (exact text) |
| 9 | partly (shown; LLM guessed `Swift`, lost `SwiftUI`) | yes (1) | yes (`uk`) | no (`SwiftUI` misheard in both) |
| 10 | no (`❓` line omitted by LLM) | yes (1) | yes (`uk`) | yes (exact text) |
| 11 (spare, 2 s pause) | part 1 preempted; part 2 yes | **split (2 turns)** (expected at T=1000 ms) | yes (`uk` ×2) | yes |

- **Total "yes" (real owner voice):** **NOT RUN** → **AC-10 NOT RUN** *(synthetic dry run: 4 / 10 "yes", 2 / 10 "partly", 4 / 10 "no"; `❓` line present on 8 / 10 questions Q1–Q10, omitted on Q8 & Q10; note `Lesya` uk_UA TTS mispronounces English acronyms `iOS`/`async/await`/`UI`/`SwiftUI`)*.
- **Fallback B:** **NOT RUN (owner decision pending)**; default remains `"B off"`. Synthetic `Lesya` showed 0 / 12 `uk → ru` drift (12 / 12 `lang=uk`), but per `spec.md` synthetic voices do not reproduce real-voice `uk → ru` drift.
- **Owner answers (B.3):** **NOT RUN** (requires owner's real voice due to enrolled voiceprint).
- **Rehearsal (B.4):** **NOT RUN** (optional; requires owner's real voice).
- **Thresholds feel (B.5):** **NOT RUN** (requires owner feedback; synthetic spare Q11 confirmed a 2 s mid-question pause splits into 2 turns at T=1000 ms and the second turn preempts the first hint).

### `metrics.py` table for Part B (synthetic dry run, clean app-only PID `94627`, `18:09:12`–`18:13:20`)
*(Note: two concurrent `swiftpm-testing-helper` runs logged to the same subsystem during this window; filtered to `InterviewCopilot` PID `94627` for true live numbers.)*
```
| Метрика | n | медиана, мс | p90, мс | порог (медиана) | результат |
|---|---|---|---|---|---|
| AC-01 phrase_end → transcript_final | 15 | 484 | 1071 | ≤ 1000 | PASS |
| AC-02 turn_end → card_shown | 0 | — | — | ≤ 500 | NOT RUN |
| AC-03 turn_end → first_token | 12 | 1064 | 2083 | ≤ 2500 | PASS |
| C15 redecode decode_ms | 19 | 118 | 190 | ≤ 2000 | PASS |
| C4-AC-01 speech_end → first_token | 12 | 1802 | 3349 | ≤ 1000 | FAIL |

Опережающие запросы: начато 4, пригодилось 4, отменено 0
  первые слова с опережающим запросом: медиана 1498 мс (n=4)
  первые слова без него: медиана 2290 мс (n=8)

Языки итоговых реплик: {'en': 2, 'uk': 13}
```
*(All 12 interviewer turns were `lang=uk`; the 2 `en` + 1 `uk` extras were ambient mic captures. `redecode_failed=0`; `whisper_history`: 7 `applied`, 5 `unchanged`, 0 `stale`/`replaced`/`reset`. Duplicate `redecode` recurred on 4 interviewer turns — 16 interviewer re-decodes for 12 turns.)*

## Problems found (for P-13)
1. **Understood-question line (`❓` / R-10) frequently omitted by Groq (`openai/gpt-oss-120b`):** Appeared on 1/1 in A.1, **0/8** in A.2 (turns 2–9), and **8/10** in Part B synthetic run (omitted on Q8 and Q10). Seen in overlay `AnswerCardView` (`UnderstoodLine.split`) on multi-turn sessions where prior `AnswerRecord` entries in memory lack `❓`. Repro: run ≥ 3 consecutive LLM hint turns with Groq.
2. **Understood-question line (`❓` / R-10) silently rewrites/hallucinates garbled terms:** On Part B synthetic Q2 (`iOS-застосунку` garbled by TTS/STT), Groq replaced the garbled phrase in the `❓` line with topic context from Q1; on Q3/Q6/Q9 it rewrote garbled words (`wait-групи`, `дедлайн`, `Swift`), violating R-10's "restate only, do not correct or invent" rule. Repro: feed a question with a misheard term after an earlier turn.
3. **Duplicate in-flight `redecode` on `?`-ended turns (600 ms pause):** Observed **13 `redecode` calls for 8 turns** in A.2 (turns 4, 6, 7, 8, 9) and **16 interviewer `redecode` calls for 12 turns** in Part B (turns 5, 6, 7, 10). Cause: `StreamingTranscriber.redecodeQuestion` caches only completed results (`redecodeCache`) with no in-flight deduplication; when `transcript_final` arrives ~480–510 ms after `speech_end`, `DraftGate`'s `redecode` is still running when `turn_end` fires at 600 ms, so `TurnController.emit` queues a second identical Parakeet pass behind it and drops the draft (+100–250 ms wasted compute/latency, and low draft adoption on `?` questions: 2/8 in A.2, 4/12 in Part B).
4. **Legacy `C4-AC-01` threshold in `scripts/metrics.py`:** `metrics.py` still flags `speech_end → first_token` as FAIL above 1000 ms (observed median 1589 ms in A.2, 1802 ms in Part B synthetic) even though COPILOT-15 `spec.md` AC-03 defines the budget for the new 1000/600 ms thresholds + re-decode as median ≤ 3000 ms, p90 ≤ 5000 ms (which both runs pass).
5. **Groq 429 TPM recovery observed on rapid 11-question run:** On Part B synthetic turn 12, Groq returned HTTP 429 (`8000 TPM` limit) and recovered after 663 ms (no user-visible failure, worth noting for long dense calls).

## Not run
- **A.2.1 (visual dimming ~50% / no animation):** Overlay uses `sharingType = .none` and is hidden from `screencapture`; requires direct visual confirmation on screen.
- **A.3.1–A.3.3 (synthetic owner channel):** Enrolled owner voiceprint rejects synthetic voice (expected per checklist).
- **Real-voice Part B (AC-10, B.2 Fallback B owner decision, B.3 live owner answers, B.4 optional rehearsal owner half, B.5 thresholds feel):** Owner explicitly requested measurement without them ("замерь без меня"); requires a short live pass with the owner's real voice to close AC-10 and lock the R-14 Fallback B decision.
- **`AC-02 turn_end → card_shown` in `metrics.py`:** 0 bank hits on the synthetic questions against the active `Test` profile (max similarity 0.510).
