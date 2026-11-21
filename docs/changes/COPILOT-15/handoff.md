# COPILOT-15 — handoff

ID: COPILOT-15-handoff · Status: **in progress** · Updated: 2026-11-20
Links: [intent.md](intent.md) · [spec.md](spec.md) · [plan.md](plan.md)

## Identity
- Branch `feat/copilot-15-accurate-turns` (from `claude/stt-revision-voice-gate-193912`). Not pushed.
- HEAD at 2026-11-21: H-1 checklist commit (after `fcd0d21`); tree clean. P-11 `7292227`, P-12 prep `27692b1`.
- H-1 materials: `h1-live-check.md` (checklist for a computer-use agent, Part A alone / Part B with the owner),
  `h1-agent-prompt.md` (prompt). Not run yet.

## Progress
| Step | Status | Commit | Checks |
|---|---|---|---|
| P-01 baseline and code reading | done | (this commit) | `swift build` PASS; `swift test` PASS (428 tests, 77 suites); `scripts/run-evals.sh turn` PASS T=700: premature 0, missed 0/26, mean latency 596 ms; draft: hits 11, wasted 3 |
| P-02 stt-dense eval | done | (P-02 final commit) | `swift build -c release --product copilot-eval` PASS; `copilot-eval stt-dense` PASS (8 questions, 156 words): chunks WER 28.2% (uk 26.3 / ru 16.7 / en 40.9), whole 4.5% (uk 5.3 / ru 2.8 / en 4.5), joined 7.1%; decode per question 1557 / 266 / 171 ms; `swift test` PASS (432 tests, 78 suites) |
| P-03 QuestionAudioRange | done | bdb237a | `QuestionAudioRangeTests` 7 PASS (AC-06) |
| P-04 QuestionRedecoder | done | 8e6493e + de-flake commit | `TurnRedecodeTests` 6 PASS (AC-05 re-decode/fallback); budget timer on its own queue (global pool starved under full suite) |
| P-05 turn flow | done (code), see P-05 state | (P-05 commit) | `swift build` PASS; `swift test` PASS (447 tests, 80 suites); `scripts/run-evals.sh turn` PASS T=700 unchanged (premature 0, missed 0/26, 596 ms); `check-localization.sh` PASS (no new strings) |
| P-06 per-phrase revision removed | done | (P-06 commit) | `swift build` PASS; `swift test` PASS (444 tests, 79 suites); grep: no `phrase_end_to_revised_ms`/`allowRevision`/`revisionMaxQueueDelay` in Sources/Tests/scripts |
| P-07 history pass | done (code), live check at H-1 | (P-07 commit) | `swift build` PASS; `swift test` PASS x2 (451 tests, 80 suites); `HistoryPassSchedulerTests` 7 PASS (AC-02) |
| P-08 thresholds | done | (P-08 commit) | `swift build` PASS; `swift test` PASS (452 tests, 80 suites); `scripts/run-evals.sh turn` PASS T=1000: premature 0, missed 0/26, mean latency 791 ms; draft: hits 23, wasted 3 (question_ms=600) |
| P-09 | done | 48a353e | `DraftGatingTests` 7; `swift test` PASS (459) |
| P-10 | done | 251542e | `swift test` PASS (464); `check-localization.sh` PASS |
| P-11 | done (code), live check at H-1 | 7292227 | `swift build` PASS; `swift test` PASS (470 tests, 83 suites); `OwnerAnswerRedecodeTests` 6 PASS (AC-09, AC-07 range part); `check-localization.sh` PASS (808 keys) |
| P-12 prep | documents + metrics done; replay NOT RUN; review/full check/version bump pending | (P-12 prep commit) | `scripts/metrics.py` redecode row verified on a synthetic log |
| P-12 rest, P-13 | not started | | |

## Findings of P-01 (what the plan builds on)
- Turn text = `TurnDetector.pending` (concatenated phrase finals); `Turn` has no audio reference. `phraseFinal(text, speechEnd:)`
  has no utterance id → P-05 adds `utterance` ids to the detector and `Turn`.
- `StreamingTranscriber.runFinal` already holds each phrase's audio and emits `.speaker` before `.final` (rehearsal routing:
  `SpeakerRouter` in `ListeningController.handle`, source `.microphone`). Phrase spans (start/end positions) are known in
  `process` (`finish(at:from:)`); a per-utterance span/audio store goes there (P-03).
- Consumers of `.revising` / `.revised` that P-06 must update: `ListeningController.handle` (transcript line replace, owner
  fast text → `onOwnerRevised`), `App.onTranscript` (`sessions.reviseUtterance`, `memory.reviseText`),
  `TurnController.handle`, `TestCallTrial`, `AnswerCapture` (AI interviewer), `copilot-eval/main.swift`, tests
  (`StreamingTranscriberTests`, `SpeechFilterTests`, `SpeakerRoutingTests`, `InterviewerTests`).
- Draft adoption: `AnswerController.handle` adopts when `draft.text == turn.text`, so equal re-decode text on the same audio
  is exactly the gate wanted by R-08; re-decode must be deterministic and cached per utterance list.
- The pause thresholds are also **user settings** (`AppSettings.pauseThresholdMs` 700, `questionPauseMs` 350; sliders in
  Settings; `App.applySettings` → `TurnController.setThreshold`). P-08 must change the defaults and migrate saved values
  that still equal the old defaults, otherwise the owner keeps 700/350.
- `ParakeetEngine` has one `inferenceLock`: the re-decode runs serially with phrase finals of both channels; it must run off
  the main actor.
- `.relay/handoff.md` of the previous session exists in the worktree history; the task's own handoff is this file.

## Executor decisions
(none yet)

## P-02 state
- Added: `evals/stt-dense/texts.json` (6 questions from the experiment + 2 English), `scripts/make-dense-fixtures.py`
  (audio to `evals/audio/stt-dense/`, git-ignored; already generated locally), `WordErrorRate` + `WordErrorRateTests`,
  `copilot-eval stt-dense [parakeet-dir] [fixtures-dir] [--verbose]` (modes chunks/whole/joined, thresholds whole ≤ 8%,
  joined ≤ 12%, whole ≤ chunks/2; exit 2 = NOT RUN when fixtures or model are missing).
- Measured (see table; matches the baseline 4.5% whole; chunks worse on the 2 English questions). Still to do for P-02: add `stt-dense` to the suite list note in `scripts/run-evals.sh`
  header and a section in `evals/README.md`, run `swift test`, record the numbers here, commit.

## P-03…P-05 state
- `QuestionAudioRange` (`STT/QuestionAudioRange.swift`): spans recorded in `StreamingTranscriber.process.finish`, route set on `.speaker`,
  dropped on discard/foreign voice; ring read only when ids consecutive, ≤ 30 s, still in the ring, no owner phrase filtered; else joined
  with 150 ms gaps; memory-bounded (120 s), `release` after use.
- `QuestionRedecoder` (`STT/QuestionRedecoder.swift`): one `transcribe` (reducedContext false, language nil for native multilingual),
  2 s budget, metrics `redecode` / `redecode_failed` (reasons empty|error|budget|no_audio). `StreamingTranscriber.redecodeQuestion`
  caches the result per utterance list (last 4) and can release the audio.
- Turn flow: `TurnDetector.phraseFinal(..., utterance:)`, `Turn.utterances` + `Turn.provisionalText`; `forceText` turns have no
  utterances (no re-decode). `TurnController.emit` chains turns, awaits `redecode` (App → `ListeningController.redecodeQuestion`),
  falls back to the phrase text, and calls `onQuestionText` → `replaceQuestionLines` (first line gets the whole question, others
  removed). Pause/Clear bump a generation so a pending turn is dropped. Transcript lines start `provisional` (opacity 0.5, no animation).
- Consumers: `App.turnCompleted` (memory, answers, history) already receives `turn.text` = re-decoded text.
- NOT unit-tested: `TurnController` / `ListeningController.replaceQuestionLines` (app target, no test target); needs a live check at H-1.
- **Known intermediate regression until P-09**: `AnswerController` adopts a draft only when `draft.text == turn.text`; drafts are still
  built from provisional phrase text, so they will rarely match the re-decoded turn text. Speculative drafts effectively lose their
  gain until P-09 (gated drafts). Do not "fix" by comparing to `provisionalText` (violates R-08).
- Rehearsal: owner phrases never reach `turns.handle` (routed in `ListeningController.handle`), so turn utterance ids are non-consecutive
  → joined path; `.speaker` also excludes owner spans inside `QuestionAudioRange`.
- `first_token ms_from_turn_end` now includes the re-decode time (turn is delivered after it) — intended, matches AC-03.
- Not run: replay / real Parakeet through the app path (needs live session).

## P-06 state
- Removed `.revising`/`.revised`, `Config.allowRevision`/`revisionMaxQueueDelay`, `scheduleRevision` and its queue; consumers updated
  (ListeningController, App, TurnController, TestCallTrial, AnswerCapture, copilot-eval, `SpeakerRouter.decide`). Owner answers now
  keep their provisional text (`onOwnerRevised`/`ownerFastText` removed); `memory.reviseText`, `sessions.reviseUtterance` and
  `reviseOwnerUtterance` stay for P-07 (history pass). Tests: removed `RevisionBacklogTests`, `ownerChannelSkipsWhisperRevision`,
  `finalFollowsRouteDecidedAtRevising`; `trialAndAnswerUsePhraseFinals` replaces the revised-text one.
- `HybridRecognizer.revise` remains (used by P-07).

## P-07 state
- `HistoryPassScheduler` (`STT/HistoryPassScheduler.swift`): one in flight, newest waiting replaces older (`replaced`), job queued > 8 s is dropped
  unrun (`droppedStale`; "result older than 8 s of queue" is read as queue wait, measured at start), waits while `isBusy` (utterance in
  progress; resumed by `kick()` at the end of every `runFinal`), `reset()` on pause drops waiting job and in-flight result. Metric
  `whisper_history turn= outcome=applied|replaced|stale|unchanged|reset`.
- `StreamingTranscriber.submitHistoryPass(utterances:turn:text:)` uses question audio stashed by `redecodeQuestion` (last 3, ≤ ~2 MB each);
  runs `recognizer.revise` only if `revisionNeeded` (hybrid: uk). Called from `App.turnCompleted` after `memory.addQuestion`.
- Result → `App.onHistoryText` → `memory.reviseText(old,to:new,scope:.questions)` (whole-word) + `SessionController.reviseQuestion`
  (first phrase gets the whole text, others removed) + `saveMemory`. Never touches the hint or the displayed transcript.
- Executor decisions: owner-channel history pass (R-11 "only when idle") NOT done — owner answers keep provisional text; dead
  `reviseOwnerUtterance` removed. Not run: live replay of a dense call (needs a live session; H-1).

## P-08 state
- `TurnDetector.Config` 1000/600; `AppSettings.pauseThresholdMs` 1000, `questionPauseMs` 600; schema 7 migrates saved 700 → 1000 and
  350 → 600 only (owner-chosen values and schema ≥ 7 stay). `copilot-eval turn` default `--threshold-ms` 1000. `TurnEval` limit formula
  already follows `config` (no code change); `evals/turn/cases.jsonl` expectations are speech-end-relative, unchanged.
  Tests updated: `TurnDetectorTests` (timings), `SettingsStoreTests` (+ `pauseDefaultsMigrate`).
- Draft hit count rose (11 → 23) because the turn now fires later than the phrase final; real adoption still waits for P-09.

## P-09 state
- `DraftGate` (`Turns/DraftGate.swift`, `@MainActor`): `offer(utterances:)` requests a re-decode of the audio so far, starts the draft only with
  that text; same list requested once; `cancel()` (speaker continues / pause / Clear) drops the pending request and cancels a started draft;
  `turnFired()` drops a late request but leaves a started draft for the turn. `TurnDetector.draftSnapshot(at:)` adds phrase numbers (no numbers → no draft).
- `TurnController.tick` offers the snapshot to the gate; draft re-decode uses `ListeningController.redecodeQuestion(release: false)` (audio stays
  for the turn); result is cached per utterance list, so the turn's re-decode returns identical text → `AnswerController` adopts (`draft.text == turn.text`).
  `speechStarted` cancels via `onDraftCancel` → `answers.cancelDraft()`. With `speculativeAnswers` off nothing is offered. Without a `draftRedecode` closure
  (tests/eval) the old phrase-text draft path remains.
- Tests: `DraftGatingTests` (7). `swift build && swift test` PASS (459); `run-evals.sh turn` PASS (T=1000, premature 0%, missed 0%, mean latency 791 ms; drafts hit=23).
- Not run: live check that drafts are adopted on a real call (H-1). The "Known intermediate regression" above is resolved in code.

## P-10 state
- `PromptBuilder.system(..., understoodLine:)` appends `understoodLineRule` (first line "❓ <question as understood>", restate only, no correction/invention, then
  the answer in the usual format; "—" replies carry no line) before the owner's instructions; only `hintRequest` sets it (interview and regular calls).
  `strongRequest`, `screenshotRequest` (coding), bank cards (no LLM) unchanged. `UnderstoodLine.split/answer` (CopilotCore).
- UI: `AnswerCardView` shows the line dimmed above the answer (fontSize-3, 55% white, accessibility label); previous-answer preview, copy button,
  `onComplete` and `AnswerRecord.text` (memory/history) use the answer without the line; mouse selection still takes the line.
  New string `"Понятый вопрос: %@"` + English. `PromptScenarios.firstLine` skips the line so eval checks look at the answer.
- Executor decisions: `refine` (chips) works on the answer text without the line (the rewritten version has no line unless the model keeps it); the line adds ~30 output tokens, `maxTokens` not raised.
- Checks: `swift build && swift test` PASS (464); `scripts/run-evals.sh memory bank` PASS (offline — they do not call the LLM, so "line vs re-decoded question" is NOT RUN, needs Groq key / H-1);
  `scripts/check-localization.sh` PASS (808 keys).

## P-11 state
- `OwnerAnswerAssembler` (`Turns/`): owner phrases (after echo/language filters in `ListeningController.handleOwner`) collect until the owner is silent
  ≥ 1000 ms and the mic VAD says not speaking; `finishOwnerAnswer` calls the owner transcriber's `redecodeQuestion(release: true)` (own ring `ownerBuffer`, own
  `questionRanges`), falls back to the phrase text, answers are delivered in order, then `onOwnerSaid` (memory + history) — one answer per pause instead of per phrase.
  Pause / recognizer change drop a pending answer (`resetOwnerAnswer`). Filtered phrases are dropped from `questionRanges`.
- No Whisper on the owner channel: the owner transcriber never gets `setHistoryHandler`, and `QuestionRedecoder` uses `transcribe` only (test counts `revise` = 0).
- Fallback B: `StreamingTranscriber.Config.hintWaitsForWhisper` (default false) → `QuestionRedecoder.Config(waitsForWhisper:)`: after the Parakeet pass `revise` (Whisper turbo)
  text replaces it when available; budget 6 s. To enable at H-1/P-13: set `config.hintWaitsForWhisper = true` where the interviewer `StreamingTranscriber.Config()` is built in
  `ListeningController` (not exposed in the UI, R-13). It is NOT wired to any setting yet; one-line change.
- Executor decisions: rehearsal / ⌃⌥A self-test answers (owner voice on the interviewer transcriber) keep provisional phrase text — their spans are marked owner and excluded from
  question audio by design (R-03), so no own-range re-decode there. AC-07 covered at the range level (`rehearsalQuestionExcludesOwner`) plus existing `SpeakerRoutingTests`.
- Not run: live owner channel (H-1).

## P-12 prep state
- Docs updated: `docs/ARCHITECTURE.md` (flow diagram, §7 events, §9 row), `AGENTS.md` (flow thresholds), `evals/README.md` (replay section, live only).
- `scripts/metrics.py`: new row `C15 redecode decode_ms` (≤ 2000) and `redecode_failed` count.
- Replay of the dense fixture as a continuous call: NOT RUN (needs the app with live audio; offline numbers are in P-02). Do it at H-1 together with the live check.
- Still for P-12 after H-1 prep: independent review of the diff (fresh subagent, strong tier: concurrency in transcriber/scheduler/owner tasks), full check
  (`swift test && scripts/run-evals.sh && scripts/secret-scan.sh && scripts/check-localization.sh && scripts/build-app.sh`), version bump, `build-app.sh`.

## Next
H-1 (owner live check; checklist `h1-live-check.md`, agent prompt `h1-agent-prompt.md`), then P-12 rest and P-13 per plan.md. (Old note: P-11, P-12 per plan.md.) Original design notes for P-03…P-05 (now implemented): store per-utterance span (start/end positions, audio, route) inside `StreamingTranscriber`
(recorded in `process.finish` and `runFinal`); `TurnDetector.phraseFinal` gets the utterance id and `Turn` gets
`utterances: [Int]`; `TurnController.emit` awaits an async `redecode` closure off the main actor (2 s budget, fallback to
phrase finals, serialize turns), caches the result per utterance list so the draft and the turn get the same text.
