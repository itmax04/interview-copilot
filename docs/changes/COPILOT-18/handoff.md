# COPILOT-18: Handoff

Branch `feat/copilot-18-mic-toggle` (from `feat/copilot-17-uk-question`, 83592c6). No push. Spec: [spec.md](spec.md), plan: [plan.md](plan.md).

## Status
| Step | State | Commit | Checks |
|---|---|---|---|
| P-01 baseline | DONE | — | `swift test` before the change: 543 tests, 96 suites (COPILOT-17 handoff, same tree) |
| P-02 core | DONE | see git log | `swift test` PASS: 552 tests, 97 suites (+9) |
| P-03 app wiring | DONE | see git log | `swift build` PASS |
| P-04 UI | DONE | see git log | `--ui-snapshots` 94/94 PNG; `panel-mic-toggle-on/off.png` checked by eye |
| P-05 docs, review, full check | DONE (D9 pending, below) | c4f9357 docs, 8440086 review fixes | full check on tree 8440086 (run sequentially, no parallel build) — see "Full check" |
| P-05a D9 one-shot voice clarification | DONE; widened forced mode added (owner decision 2026-11-24), full check PASS on d5e3b21 | b9c2f74 code, 3d791e5 docs | see "D9 — done" |
| H-1 owner live check | DONE — owner: «все окей» (a–f), build d5e3b21 | f2d7a42 | owner verdict only, no log numbers |
| P-06 final handoff, AC table | DONE — accepted by owner 2026-11-24 | see git log | table below |

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

## D9 (owner decision relayed 2026-11-24) — request (implemented, see "D9 — done") — one-shot «уточнение голосом»
Request: the D1 setting stays (automatic clarification off by default). New control: overlay button next to «Микрофон выкл.» + global hotkey ⇧⌘U.
Pressing arms a one-shot mode: the owner's NEXT phrase is treated as a voice clarification of the current question (existing
`OwnerQuestionDetector` decisions / `AnswerController.handleOwnerQuestion`, clarify or replace logic); after that one phrase the mode turns
itself off; pressing again while armed cancels. Armed state clearly visible on the button (`IC`/`ICDark` tokens, Reduce Motion).
To do in the next session (after the P-05 full check is recorded; do not edit `Sources` while a check runs):
- Add D9 to intent.md, R-/AC- rows to spec.md, a step to plan.md (P-05a), tests, strings (Russian single literals + en.lproj), `HotkeyAction.voiceClarify` appended last (session ⇧⌘U, otherwise ⌃⌥U).
- Suggested executor decisions to record: (1) mic off → arming is **disabled** (button dimmed, hotkey ignored with a log line) rather than implicitly turning the mic on — HIG: an action must not silently change another control's state; (2) armed timeout **15 s** without a phrase, then it disarms itself silently; (3) armed state does not survive session end; (4) the armed phrase bypasses `ownerVoiceClarification` but still uses `OwnerQuestionDetector.detect` with the forced mode (if it returns `.none`, treat as `.clarifyLastQuestion` of the phrase when an active question exists, otherwise ordinary answer).
- Then the full check, handoff → H-1 (add a D9 case to the H-1 list: arm, speak a short clarification, version «с вашего голоса» appears once; the next phrase does not).

## Full check (tree 8440086, run sequentially; output file `/private/tmp/claude-501/full2.txt`)
- `swift test`: **PASS**, 553 tests in 97 suites (exit 0). The earlier single failure of the timing test `TurnRedecodeTests.swift:111`
  (1.04 s < 1.0 s) happened while the review subagent ran in parallel (551/552); on the sequential run it did not fail, so no separate rerun was needed.
- `scripts/run-evals.sh`: **PASS** (output tail only was kept: filter-text 236/236, exam-followup 48/48, memory 8/8 and 0/2,
  materials 23/24 and 2/8; the turn and bank lines were cut off by `tail` — NOT RECORDED this time, unchanged code paths).
- `scripts/secret-scan.sh`: **PASS**, 0 findings.
- `scripts/check-localization.sh`: **PASS**, 850 keys, 850 translations, 0 missing, 0 mismatches.
- `scripts/build-app.sh`: **PASS**, signed `dist/InterviewCopilot.app` (verified OK).
- AC-01…AC-04, AC-06 (unit tests), AC-05 (snapshots), AC-08…AC-10: evidence above. AC-07 and AC-11: review (done) and **H-1 pending**.
- Not covered by automated tests: `ListeningController`/`App.swift` wiring (see above). Review nit 4 (marker may be truncated in very long reviews) left as is.

## Next
D9 (section above), then re-run the full check, then **H-1** (plan.md) together with COPILOT-17 H-1. No push.

## D9 — done (2026-11-24, session after copilot18-d9 was stopped by the owner)
Branch `feat/copilot-18-mic-toggle`, HEAD 3d791e5 (+ this handoff commit), tree clean, no upstream, **no push**.
- Code (b9c2f74): `Sources/CopilotCore/Turns/VoiceClarifyArm.swift` (toggle / one-shot `consume` / 15 s `expire` that waits while the owner
  speaks; `OwnerQuestionDetector.detectForced`), `HotkeyAction.voiceClarify` last (⇧⌘U / ⌃⌥U), `App.swift` wiring (disarm on mute and at
  session start/end, timer), overlay button «Уточнить» / armed «Говорите…» (`ICDark.accent`, 2 pt border) in full and collapsed toolbars,
  `UISnapshots` state `voice-clarify-armed`, 5 strings + en.lproj, `Tests/CopilotCoreTests/VoiceClarifyTests.swift` (+8 tests).
- Docs (3d791e5): intent D9, spec R-09…R-11 / AC-12…AC-14 + risks, plan P-05a and H-1 item (f), ARCHITECTURE.
- Executor decisions (D9): (1) mic off → arming ignored with a log line, and the button is **hidden** (not dimmed): with five buttons the
  default-width overlay overflowed («Завершить» and «Чат» clipped, seen on `--ui-snapshots`); (2) idle label shortened to «Уточнить» for
  the same reason (long form «Уточнить голосом» stays in the collapsed-toolbar label and the hotkey title «Уточнение голосом (одна фраза)»);
  (3) armed colour uses a new overlay token `ICDark.accent` (#6382FF, = `IC.accent` dark) — the overlay is always dark; (4) 15 s timeout,
  not kept across sessions, `detectForced` as suggested above; an interrupted phrase does not spend the armed state.
- Snapshots: `--ui-snapshots` 95/95 PNG; `panel-mic-toggle-on/off.png`, `panel-voice-clarify-armed.png` checked by eye (row fits).

### Full check on tree 3d791e5 (sequential; log `/private/tmp/claude-501/-Users-macbook--claude-spares-spare-hX7LOE/0ff6bd41-c894-4134-966b-08d28e921a68/scratchpad/full-d9.txt`)
- `swift test`: **PASS**, 561 tests in 98 suites (exit 0).
- `scripts/run-evals.sh`: **PASS** (exit 0): filter-text 236/236, exam-followup 48/48, memory 8/8 and 0/2, materials 23/24 and 2/8.
- `scripts/secret-scan.sh`: **PASS**, 0 findings (exit 0).
- `scripts/check-localization.sh`: **PASS**, 855 keys, 856 translations, 0 missing, 0 format mismatches (exit 0).
- `scripts/build-app.sh`: **PASS**, signed `dist/InterviewCopilot.app` (verified OK, exit 0).
- AC-12, AC-13 (unit tests), AC-14 (snapshots), AC-08…AC-10: evidence above. AC-11 (incl. H-1 item f): **H-1 pending**.
- Note: commit 9f9a514 says "full check PASS" but carried the earlier partial text; the full results are recorded by the next commit.

### D9 behaviour notes (as implemented; owner asked about follow-ups and interruptions)
- The interviewer asks a follow-up while armed: it goes the normal interviewer way (new card or follow-up version); the armed state is
  untouched, and the owner's next phrase clarifies the **latest** card (`hasActiveQuestion` = the last history entry exists). 15 s timer still runs.
- The interviewer interrupts the owner: the owner's flushed phrase comes with `interrupted = true`, does not spend the armed state and is
  saved as an ordinary answer; the mode stays armed until the next uninterrupted phrase or the 15 s timeout.
- Not covered by unit tests (app wiring); to watch in H-1 item (f).

### Widened forced mode — done (owner answered 2026-11-24: «Расширить режим»)
Commits: 393d9a6 (code + tests), d5e3b21 (spec R-10/AC-13, plan H-1 f). `OwnerQuestionDetector.forcedMaxWords = 40`;
`detectForced` runs `detect` with that limit, then: content phrase + active question → `clarifyLastQuestion`, no active question →
`newQuestion`; empty / filler / backchannel / > 40 words → `.none`. Automatic `detect` (D1, 15 words) unchanged (private overload with
`wordLimit`). Caveat: in forced mode a phrase that starts like an answer («я думаю…») is now also taken as clarification/new question
(the armed phrase is by definition not an answer). Note: tests and code were written in one pass, so there was no separate red run.
Tests: `VoiceClarifyTests` 11 (new: long repeated question 16–40 words, no-question content phrase → newQuestion, exactly 40 / 41 words,
D1 unchanged).

Full check on d5e3b21, run sequentially (outputs in `/private/tmp/claude-501/chk/`):
| Command | Exit | Result |
|---|---|---|
| `swift test` | 0 | PASS — 564 tests in 98 suites |
| `scripts/run-evals.sh` | 0 | PASS (exam-followup 48/48; memory 8/8, 0/2; materials 23/24, 2/8) |
| `scripts/secret-scan.sh` | 0 | PASS — 0 findings |
| `scripts/check-localization.sh` | 0 | PASS — 855 keys, 0 missing |
| `scripts/build-app.sh` | 0 | PASS — dist/InterviewCopilot.app signed |

## Next
1. ~~Widen forced mode~~ — done above.
2. ~~**H-1**~~ — owner live check done 2026-11-24 on build d5e3b21 installed to /Applications: «все окей» for items a–f (COPILOT-17 and 18 together). No numbers from the log were supplied; owner's verdict only. Installing the build into /Applications was done by the executor (ditto from dist/, codesign verify OK).
3. **P-06**: final handoff with the AC evidence table, ask for acceptance. No push until the owner allows.

## Final: AC evidence (P-06), tree d5e3b21 + docs commits
| AC | Result | Evidence |
|---|---|---|
| AC-01…AC-04, AC-06 | PASS | `swift test` d5e3b21: 564 tests / 98 suites, exit 0 (`OwnerMicToggleTests`, `InterviewMemoryTests`, `ReviewTests`) |
| AC-05, AC-14 | PASS (not re-run on d5e3b21) | `--ui-snapshots` + eye check at P-04/D9; no UI code changed afterwards |
| AC-07 | PASS | independent review (sonnet, 83592c6..c4f9357: mergeable, findings fixed in 8440086) + owner live check H-1 (b), (c), (d) |
| AC-08 | PASS | `scripts/check-localization.sh` 855 keys, 0 missing; `scripts/secret-scan.sh` 0 findings |
| AC-09 | PASS | `scripts/run-evals.sh` exit 0 (exam-followup 48/48, memory 8/8 and 0/2, materials 23/24 and 2/8) |
| AC-10 | PASS | all five commands, sequentially, exit 0 on d5e3b21; `build-app.sh` signed |
| AC-11 | PASS (owner verdict) | H-1 a–f «все окей»; no log numbers supplied |
| AC-12, AC-13 | PASS | `VoiceClarifyTests` 11 tests, incl. widened forced mode (40 words, no-question content phrase → newQuestion, D1 unchanged) |

**Unverified / limits:** the widened forced mode was covered by unit tests and by the owner's live check, but no review subagent
looked at commit 393d9a6 (owner-requested small change); ListeningController wiring is app-target code without unit tests;
latency/log numbers for COPILOT-17 H-1 (e) were not supplied. No push done; branch is not merged into `main`.

**Owner accepted COPILOT-18 on 2026-11-24.** Not pushed, not merged into `main` (needs the owner's decision).
