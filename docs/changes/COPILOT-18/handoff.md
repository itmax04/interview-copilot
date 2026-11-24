# COPILOT-18: Handoff

Branch `feat/copilot-18-mic-toggle` (from `feat/copilot-17-uk-question`, 83592c6). No push. Spec: [spec.md](spec.md), plan: [plan.md](plan.md).

## Status
| Step | State | Commit | Checks |
|---|---|---|---|
| P-01 baseline | DONE | — | `swift test` before the change: 543 tests, 96 suites (COPILOT-17 handoff, same tree) |
| P-02 core | DONE | see git log | `swift test` PASS: 552 tests, 97 suites (+9) |
| P-03 app wiring | DONE | see git log | `swift build` PASS |
| P-04 UI | DONE | see git log | `--ui-snapshots` 94/94 PNG; `panel-mic-toggle-on/off.png` checked by eye |
| P-05 docs, review, full check | IN PROGRESS | docs in c4f9357 | full check was started in the background (output `/private/tmp/claude-501/full.txt`, may be gone) — **NOT RUN to completion as recorded; re-run**; independent review subagent launched, result not received — **re-run the review** |
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
