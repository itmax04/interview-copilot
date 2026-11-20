# COPILOT-15 — handoff

ID: COPILOT-15-handoff · Status: **in progress** · Updated: 2026-11-20
Links: [intent.md](intent.md) · [spec.md](spec.md) · [plan.md](plan.md)

## Identity
- Branch `feat/copilot-15-accurate-turns` (from `claude/stt-revision-voice-gate-193912`). Not pushed.

## Progress
| Step | Status | Commit | Checks |
|---|---|---|---|
| P-01 baseline and code reading | done | (this commit) | `swift build` PASS; `swift test` PASS (428 tests, 77 suites); `scripts/run-evals.sh turn` PASS T=700: premature 0, missed 0/26, mean latency 596 ms; draft: hits 11, wasted 3 |
| P-02 … P-13 | not started | | |

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

## Next
P-02: the `stt-dense` eval.
