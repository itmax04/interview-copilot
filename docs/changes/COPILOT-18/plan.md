# COPILOT-18: Plan

ID: COPILOT-18-plan · Status: **draft** · Date: 2026-11-24
Links: [intent.md](intent.md) · [spec.md](spec.md) · [handoff.md](handoff.md)

Branch: `feat/copilot-18-mic-toggle` (from `feat/copilot-17-uk-question`, 83592c6). Commit after every step; no push. After every step
update `handoff.md`. Quick check: `swift build && swift test`. A command that does not exist is written NOT RUN.

| Step | What | Requirements | Check |
|---|---|---|---|
| P-01 | Baseline: `swift build && swift test` on the branch start (543 tests expected) | — | handoff |
| P-02 | Core: `ownerVoiceClarification` setting, `MicMutedInterval`, `SessionRecord.micMutedIntervals`, `TimelineEntry.micOff` and review transcript line, `HotkeyAction.toggleMic`, `StreamingTranscriber.setPaused(_, cancelRecognizer:)` + tests | R-01, R-03, R-04, R-06 | `OwnerMicToggleTests`, `InterviewMemoryTests` |
| P-03 | App wiring: D1 gate in `onOwnerSaid`, Settings row; `ListeningController` toggle state and gating; session start/end reset; history marks | R-01…R-03, R-05, R-06 | `swift build`, review |
| P-04 | UI: overlay button (full and collapsed), history row, level wave, strings, `--ui-snapshots` states | R-04, R-05, R-08 | snapshots, `scripts/check-localization.sh` |
| P-05 | Documents (AGENTS.md hotkeys/setting, ARCHITECTURE, CLAUDE.md latest task); independent review of the diff (fresh subagent, standard tier, relay-review brief); fix findings; full check; `scripts/build-app.sh` | R-08, AC-08…AC-10 | full check |
| P-05a | D9 one-shot voice clarification: `VoiceClarifyArm`, `detectForced`, `HotkeyAction.voiceClarify`, overlay button + snapshot, App wiring (disarm on mute and session start/end, 15 s timer), strings, tests; intent/spec/plan/ARCHITECTURE; full check | R-09…R-11, AC-12…AC-14 | full check |
| H-1 | **Owner live check (COPILOT-17 and COPILOT-18 together)** — (a) 18: with the setting off, say a short phrase next to the Mac: no «с вашего голоса» version; with it on the version appears; (b) 18: press ⇧⌘M while Meet is focused: button turns red, speak — nothing appears in the history/review, the level wave is flat, no «Микрофон не даёт звука» after 10+ s; the interviewer's question is still heard and answered; press again: your speech is recorded; Meet still hears you throughout; (c) 18: end the session: the history shows the «Микрофон выключен…» row and the review does not blame the missing answer; (d) 18: new session starts with the mic on; the button is absent in the self-test source and the test call; (e) 17 H-1 list (Ukrainian question text, ticket root title, «Точный вопрос (+2 с)» latency, English term, question-audio saving and wipe); (f) 18 D9: during a question press ⇧⌘U (or «Уточнить»): the button shows «Говорите…»; say a short clarification — a version «с вашего голоса» appears once and the button returns to «Уточнить»; the next phrase does not change the hint; press twice — cancelled; armed and silent for 15 s — turns off by itself; with the mic off the button is absent and ⇧⌘U does nothing | AC-11 | owner's answer; numbers from the log in the handoff |
| P-06 | Apply H-1 findings; final handoff with the AC evidence table; ask for acceptance | AC-11 | owner acceptance |

Order: P-02 → P-03 → P-04 → P-05 → P-05a → H-1. Tiers (relay): P-02…P-04 standard (small logic + UI); P-05 documents light, review standard.
No strong tier: no open design trade-off (D1–D8 decided), no concurrency redesign.
