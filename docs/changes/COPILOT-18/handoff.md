# COPILOT-18: Handoff

Branch `feat/copilot-18-mic-toggle` (from `feat/copilot-17-uk-question`, 83592c6). No push. Spec: [spec.md](spec.md), plan: [plan.md](plan.md).

## Status
| Step | State | Commit | Checks |
|---|---|---|---|
| P-01 baseline | DONE | — | `swift test` before the change: 543 tests, 96 suites (COPILOT-17 handoff, same tree) |
| P-02 core | DONE | see git log | `swift test` PASS: 552 tests, 97 suites (+9) |
| P-03 app wiring | DONE | see git log | `swift build` PASS |
| P-04 UI | DONE | see git log | `--ui-snapshots` 94/94 PNG; `panel-mic-toggle-on/off.png` checked by eye |
| P-05 docs, review, full check | IN PROGRESS | docs in c4f9357 | full check was started in the background (output `/private/tmp/claude-501/full.txt`, may be gone) — **NOT RUN to completion as recorded; re-run**; independent review DONE (below); full check: `swift test` 551/552 — only the timing test `TurnRedecodeTests.swift:111` (1.04 s < 1.0 s) failed while the review ran in parallel, re-run alone; evals/secret-scan/localization/build-app NOT RUN |
| H-1 owner live check | PENDING | — | — |

## Executor decisions
- **Availability.** The toggle works on call sessions only (source is not «Микрофон Mac», no test call, not the AI interview). There the
  microphone is the only input, so muting would silence everything; the button is hidden and the hotkey logs and does nothing.
- **Hotkey.** ⇧⌘M is the session ⌘-scheme binding (Q10: ⌘ keys are intercepted only during a session); outside a session ⌃⌥M. If another app
  holds ⇧⌘M (Chrome has «Profile» on it), the panel hint falls back to ⌃⌥M as for the other ⌘ keys.
- **Shared engine.** Pausing the owner transcriber cancelled the engine shared with the interviewer's transcriber (a running decode could be
  lost). The toggle uses `setPaused(_, cancelRecognizer: false)`; the default pause is unchanged.
- **«Fully ignored» includes `foreignVoice`.** A foreign voice heard by the owner channel is no longer routed as an interviewer question
  while the mic is off.
- **Level wave** is shown flat while off, so the overlay does not suggest that Copilot hears the owner.
- **Review marks:** the muted interval is stored as times only; the review transcript gets one line (English, to the model) saying the
  owner's microphone was off. Exchanges without a recorded answer are not commented as before.
- **Session start/end** call `resetOwnerMic()` (the end closes the interval before `sessions.finish()`).

## Not covered by automated tests
`ListeningController` / `App.swift` wiring (app target has no unit tests): state, channel gating, "owner speaking" suppression, silence
notice, hotkey and button. Covered by review and by H-1.

## Next
P-05 (new session): re-run the full check, run the independent review (fresh subagent, standard, relay-review brief; focus: `ListeningController` gating, App wiring/order of `resetOwnerMic`, `MicMutedInterval`, hotkey ids), fix findings; independent review (fresh subagent), fix findings, full check, `scripts/build-app.sh`; then H-1 (plan.md) together with COPILOT-17 H-1.

## Independent review (fresh subagent, sonnet, 83592c6..c4f9357): verdict mergeable, to fix in P-05
1. `ListeningController` mic-activity callback: after unmute `ownerSpeaking` stays false until the next speech onset if the owner was mid-phrase (detector sends edges only) — keep the last raw `speaking` value and apply it in `setOwnerMicOff(false)`.
2. `ownerMicSwitchAvailable` is true for `source == .none` and when `ownerSpeechContext` is off — a press would log an interval "not recorded" although nothing was recorded; require an actually possible owner channel or record the decision.
3. `resetOwnerMic()` at session end runs while phase is still `.listening` (re-activates the owner channel just before standby); and `updateOwnerChannel` now pauses with `cancelRecognizer: false` for ALL deactivations (permission, phase, standby), not only mute — pass `cancelRecognizer: !ownerMicOff` there; call the end-of-session reset after `enterStandby()` or without `updateOwnerChannel`.
4. Nit: review marker line can be dropped by the "earlier part omitted" truncation — optionally keep it in the tail.

## D9 (owner decision relayed 2026-11-24, NOT implemented yet) — one-shot «уточнение голосом»
Request: the D1 setting stays (automatic clarification off by default). New control: overlay button next to «Микрофон выкл.» + global hotkey ⇧⌘U.
Pressing arms a one-shot mode: the owner's NEXT phrase is treated as a voice clarification of the current question (existing
`OwnerQuestionDetector` decisions / `AnswerController.handleOwnerQuestion`, clarify or replace logic); after that one phrase the mode turns
itself off; pressing again while armed cancels. Armed state clearly visible on the button (`IC`/`ICDark` tokens, Reduce Motion).
To do in the next session (after the P-05 full check is recorded; do not edit `Sources` while a check runs):
- Add D9 to intent.md, R-/AC- rows to spec.md, a step to plan.md (P-05a), tests, strings (Russian single literals + en.lproj), `HotkeyAction.voiceClarify` appended last (session ⇧⌘U, otherwise ⌃⌥U).
- Suggested executor decisions to record: (1) mic off → arming is **disabled** (button dimmed, hotkey ignored with a log line) rather than implicitly turning the mic on — HIG: an action must not silently change another control's state; (2) armed timeout **15 s** without a phrase, then it disarms itself silently; (3) armed state does not survive session end; (4) the armed phrase bypasses `ownerVoiceClarification` but still uses `OwnerQuestionDetector.detect` with the forced mode (if it returns `.none`, treat as `.clarifyLastQuestion` of the phrase when an active question exists, otherwise ordinary answer).
- Then the full check, handoff → H-1 (add a D9 case to the H-1 list: arm, speak a short clarification, version «с вашего голоса» appears once; the next phrase does not).
