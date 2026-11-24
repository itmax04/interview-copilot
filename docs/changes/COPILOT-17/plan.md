# COPILOT-17: Plan

ID: COPILOT-17-plan · Status: **draft** (for the owner's review) · Date: 2026-11-23
Links: [intent.md](intent.md) · [spec.md](spec.md) · [handoff.md](handoff.md)

Branch: `feat/copilot-17-uk-question` (from `feat/copilot-16-source-language`, 50e65b6). Commit after every step; no push
without the owner's permission. After every step update `handoff.md` (done, commit, checks PASS/FAIL/NOT RUN, next step).
Quick check per step: `swift build && swift test`. A command that does not exist yet is written NOT RUN, never invented.

| Step | What | Requirements | Check |
|---|---|---|---|
| P-01 | Baseline at the branch start: `swift build && swift test`, `scripts/run-evals.sh`, secret-scan, localization; record the test count; measure the baseline decode time and (if a recent session log exists) first-token time with `scripts/metrics.py` | AC-03/06/08 baselines | handoff |
| P-02 | Eval first for the exam rule: `evals/exam-followup/cases.jsonl` (≥ 24 new-ticket, ≥ 24 follow-up, synthetic) + `copilot-eval` subcommand + `run-evals.sh` line. Expect the new-ticket openers to fail before P-03 | R-04 | `scripts/run-evals.sh` — exam-followup FAIL expected, count recorded |
| P-03 | `FollowUpDetector.isExamFollowUp`: start-anchored new-ticket openers (uk/ru/en); tune the list on the eval; existing tests unchanged | R-03 | `ExamFollowUpTests` (+ new cases); exam-followup eval PASS (AC-04) |
| P-04 | `ParakeetLanguage` mapping (pure) + `language:` pass-through in `ParakeetEngine.transcribe` behind a seam; `useLanguageHint` flag | R-01, R-02 | `ParakeetLanguageHintTests` (AC-01) |
| P-05 | Real-model check on synthetic `say -v Lesya` audio (with/without the hint, English-term sentences, `LanguageGate` pass); record numbers; if a term regression is found, apply the R-02 decision and record it under "Executor decisions" | R-02, R-08 | AC-02, AC-03 numbers in the handoff |
| P-06 | Whisper corrects the ticket root: handler on `onHistoryText` in the app wiring → `ActiveTopic`/`AnswerHistory`/`InterviewMemory` update with guards and the `ticket_root_updated` log; panel title refresh | R-05, R-08 | `ActiveTopicUpdateTests`, UI snapshot (AC-05) |
| P-07 | `preciseQuestion` setting (`AppSettings`, effective-value function, session start wiring to `hintWaitsForWhisper`), Settings row with the +2 s explanation, `hint_wait_whisper` log, timeout fallback test | R-06, R-07 | `PreciseQuestionSettingTests`, `SettingsStoreTests`, stalled-recognizer test (AC-07, AC-08); `scripts/check-localization.sh` |
| P-08 | `QuestionAudioStore` (CopilotCore): WAV + numbers-only sidecar, permissions, backup exclusion, retention, count/size; wiring at turn delivery (call channel only, background queue); Settings row, «Удалить сохранённое аудио» with confirmation | R-09, R-10 | `QuestionAudioStoreTests` (AC-09, AC-10); `scripts/check-localization.sh` |
| P-09 | «Удалить всю историю» also wipes `question-audio/`; retention on app start and session end | R-10 | `SessionStoreTests`, `QuestionAudioStoreTests` |
| P-10 | Documents (AGENTS.md "no audio" wording and §6, ARCHITECTURE §3/§4/§9, CLAUDE.md latest task); independent review of the whole diff (fresh subagent, standard tier, briefed per relay-review); fix findings; full check and `scripts/build-app.sh` | R-11, AC-11…AC-13, AC-15 | full check command |
| H-1 | **Owner live check of a Ukrainian call** (test call with a Ukrainian voice, or a real exam-style call): (a) questions come out as Ukrainian text, turn 1 is not English; (b) «К билету» shows the corrected title about 2 s after the question; (c) «назвіть…», «що таке…» start a new ticket, short clarifications still stay in the ticket; (d) with «Точный вопрос (+2 с)» on, the hint starts ≈ 2 s later and does not stall; try it off; (e) English IT terms inside a Ukrainian question are still readable; (f) switch the audio saving on for one session, check that files appear in the app folder with permissions 600, that the settings row shows count/size, and that «Удалить всю историю» removes them. Executor extracts numbers from the log (`hint_wait_whisper`, `ticket_root_updated`, `question_audio_saved`) | AC-14 | owner's answer; numbers in the handoff |
| P-11 | Apply H-1 findings (term regression → R-02 decision, opener list, wait default); final handoff with the AC evidence table and unverified items; ask the owner for acceptance | AC-14, AC-15 | handoff; owner acceptance |

Order: P-02 → P-03 (eval first); P-04 → P-05; P-06; P-07; P-08 → P-09. P-03, P-04, P-06 are independent of each other;
P-07 needs nothing from P-06; P-08 is independent of P-03…P-07. P-10 after all code. H-1 after P-10.

Tiers (relay): P-02, P-03, P-04, P-06, P-07, P-08, P-09 — standard (pure logic plus small UI); P-05 and P-10 documents — light;
the P-10 review — standard (fresh subagent; the audio store touches personal data, so the reviewer checks the permissions and
the "no text in files/logs" rule explicitly); H-1 — owner. No stage needs the strong tier: there are no open design
trade-offs left (the owner decided D1–D5) and no concurrency redesign — P-06's race guard is a plain identity check.

Out of this plan: cloud STT, the STT bake-off, the Whisper vocabulary prompt (see intent.md).
