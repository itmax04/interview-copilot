# COPILOT-15 — handoff

ID: COPILOT-15-handoff · Status: **in progress** · Updated: 2026-11-20
Links: [intent.md](intent.md) · [spec.md](spec.md) · [plan.md](plan.md)

## Identity
- Branch `feat/copilot-15-accurate-turns` (from `claude/stt-revision-voice-gate-193912`). Not pushed.

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
| P-08 … P-13 | not started | | |

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

## Next
P-06 + P-07 together (remove per-phrase Whisper revision, background history pass), P-08 (thresholds, independent), then P-09 (gated drafts —
restores draft adoption), P-10, P-11, P-12 per plan.md. Original design notes for P-03…P-05 (now implemented): store per-utterance span (start/end positions, audio, route) inside `StreamingTranscriber`
(recorded in `process.finish` and `runFinal`); `TurnDetector.phraseFinal` gets the utterance id and `Turn` gets
`utterances: [Int]`; `TurnController.emit` awaits an async `redecode` closure off the main actor (2 s budget, fallback to
phrase finals, serialize turns), caches the result per utterance list so the draft and the turn get the same text.
