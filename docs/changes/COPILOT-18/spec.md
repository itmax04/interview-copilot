# COPILOT-18: Spec

ID: COPILOT-18-spec · Status: **draft** · Version: 2 (D9: R-09…R-11, AC-12…AC-14) · Date: 2026-11-24
Links: [intent.md](intent.md), [plan.md](plan.md), [handoff.md](handoff.md)

## Starting point
Branch `feat/copilot-18-mic-toggle`, cut from `feat/copilot-17-uk-question` at 83592c6. On a call (source «app» or «all system»)
the Mac microphone runs next to the call capture: `MicActivityDetector` reports "owner speaking" (an input of `TurnController`), and
the samples feed a second `StreamingTranscriber` (`ownerTranscriber`) while `ownerActive` is set (`updateOwnerChannel`). Its final
phrases go through `handleOwner` → `OwnerAnswerAssembler` → `onOwnerSaid` → memory, history and (before this task) the detector.
In the «Микрофон Mac» source (self-test, rehearsal) and in the test call / AI interview the microphone is the only input.

## Requirements
| ID | Requirement |
|---|---|
| R-01 | **Setting `ownerVoiceClarification`** (`AppSettings`, Bool, default **false**, decoded with the safe fallback so old files load). `OwnerQuestionDetector` is consulted in `onOwnerSaid` only when the setting is on (and the existing conditions hold). Off: the phrase is added to memory and history as an owner answer, no hint is started or changed. Settings row (Voice section) with a short explanation |
| R-02 | **Mic switch state** in `ListeningController`: `ownerMicOff`, `toggleOwnerMic()`, available only on a call session (`testSource == nil`, source is not «Микрофон Mac»), not in the test call and not in the AI interview. Elsewhere the button is hidden and the hotkey is ignored with a log line. `resetOwnerMic()` runs at session start and end (every session starts on, D4); the state is never saved |
| R-03 | **Off = ignored** (D3). `updateOwnerChannel` deactivates the owner channel (samples dropped, owner transcriber paused **without cancelling the shared engine**, so a running interviewer decode is not lost); pending owner phrases are discarded (`resetOwnerAnswer`); a phrase finishing after the press is dropped in `handleOwner`; "owner speaking" is reported false while off, so the interviewer's turn ends by pause only. Nothing reaches `onOwnerSaid`, so no history, memory, review or hint text. `foreignVoice` routing from the owner channel stops too. Meet and macOS mute are not touched |
| R-04 | **Hotkey and button** (D5): `HotkeyAction.toggleMic` appended at the end of `allCases` (indices of earlier actions unchanged); session default **⇧⌘M** (the session ⌘-scheme, Q10), outside a session **⌃⌥M**; shown in Settings → hotkeys like the others. Overlay button «Микрофон» (on) / «Микрофон выкл.» (off) between «Скриншот» and «Чат», full and collapsed toolbar; `IC`/`ICDark` tokens; no animation added (Reduce Motion unaffected) |
| R-05 | **Indicator only** (D6): red state `ICDark.red` + changed icon and label (colour is not the only signal); the mic level wave is flat while off; no banner, reminder or auto-unmute; `micExpected` is false while off, so `MicSilenceDetector` does not fire. `micHardwareMuted` is unchanged and independent |
| R-06 | **Muted intervals** (D7): `SessionRecord.micMutedIntervals: [MicMutedInterval]` (start, optional end; times only, no text; old files decode to empty). Opened/closed on toggle, closed at session end. History transcript shows a «Микрофон выключен в Copilot · 12:05–13:40 — ваши слова не записывались» row; the review transcript carries a line that the owner's microphone was switched off and that missing answers are not silence |
| R-07 | **Test call / rehearsal / self-test**: unchanged; the toggle is unavailable there (R-02). No new risk to `voiceGate` (it only guards the owner channel, which is inactive while off) or echo handling (`callSpeaking`, `echoWindowMs` read the call channel only) |
| R-09 | **One-shot voice clarification (D9)**: `VoiceClarifyArm` (CopilotCore) — `toggle` arms or cancels; `consume(interrupted:)` spends the armed state on the next owner phrase that reaches `onOwnerSaid` (an interrupted phrase does not spend it); `expire` disarms after **15 s** without a phrase, but not while the owner is speaking (waits for the phrase end). Available only where the mic switch is (R-02); ignored with a log line while the owner mic is off; disarmed when the mic is switched off and at session start and end (never saved) |
| R-10 | **Decision for the armed phrase**: bypasses `ownerVoiceClarification` (D1 setting unchanged) and uses `OwnerQuestionDetector.detectForced`: the ordinary `detect` decision if it gives one; otherwise, with an active question, a short phrase (≤ `maxWords`, not only fillers/backchannel) is `.clarifyLastQuestion`; otherwise `.none` → ordinary owner answer (memory/history) |
| R-11 | **Control** (D9): `HotkeyAction.voiceClarify` appended last (session **⇧⌘U**, otherwise **⌃⌥U**). Overlay button «Уточнить» (armed: «Говорите…», icon `waveform`, `ICDark.accent` with a 2 pt border — colour is not the only signal), between «Микрофон» and «Чат», full and collapsed toolbar; hidden while the owner mic is off. No animation (Reduce Motion unaffected). Log lines carry only armed/cancelled/timed out, never text |
| R-08 | UI strings are Russian single literals with English lines in `Resources/en.lproj/Localizable.strings`; synthetic test data only; no text, audio or secrets in logs (the new log lines carry only "on"/"off") |

## Acceptance criteria
| ID | Criterion | How to check |
|---|---|---|
| AC-01 | `ownerVoiceClarification` defaults to false, old settings files load, round-trip keeps true | `OwnerMicToggleTests` |
| AC-02 | `MicMutedInterval.apply/close/contains`: open on mute, close on unmute, repeats ignored, open interval closed at session end | `OwnerMicToggleTests` |
| AC-03 | The owner transcriber pause used by the toggle does not call `recognizer.cancel()` of the shared engine; the default pause still does | `OwnerMicToggleTests` |
| AC-04 | `toggleMic` is last in `allCases`, defaults ⌃⌥M / session ⇧⌘M, earlier indices unchanged | `OwnerMicToggleTests`, `InterviewMemoryTests` |
| AC-05 | Overlay shows the button in on and off states between «Скриншот» and «Чат» | `--ui-snapshots` (`panel-mic-toggle-on/off.png`) |
| AC-06 | Timeline contains the `micOff` marker with the correct range; review transcript says the microphone was off; sessions without intervals unchanged; old files load | `OwnerMicToggleTests`, `ReviewTests` |
| AC-07 | Behaviour R-02/R-03/R-05 (state, gating, turn signal, silence notice) — code review of the diff against the spec, and the owner's live check | review, H-1 |
| AC-08 | Localization and secrets | `scripts/check-localization.sh`, `scripts/secret-scan.sh` |
| AC-09 | Existing evals unchanged | `scripts/run-evals.sh` |
| AC-10 | Full check | `swift test && scripts/run-evals.sh && scripts/secret-scan.sh && scripts/check-localization.sh && scripts/build-app.sh` |
| AC-11 | **Live check (H-1, with COPILOT-17 H-1):** see plan | owner |
| AC-12 | `VoiceClarifyArm`: arm/cancel, one-shot consume, interrupted phrase keeps it armed, 15 s timeout only when the owner is silent | `VoiceClarifyTests` |
| AC-13 | `detectForced`: plain short phrase with an active question → `clarifyLastQuestion`; detector decision kept when it speaks; no active question, fillers, empty or long phrase → `.none`; D1 default still false; `voiceClarify` last, ⌃⌥U / ⇧⌘U | `VoiceClarifyTests`, `OwnerMicToggleTests`, `InterviewMemoryTests` |
| AC-14 | Overlay shows «Уточнить» (mic on), «Говорите…» armed, no button while the mic is off; the row fits the default overlay width | `--ui-snapshots` (`panel-mic-toggle-on/off.png`, `panel-voice-clarify-armed.png`) |

## Risks
| Risk | Mitigation |
|---|---|
| The toggle logic in `ListeningController` is app-target code without unit tests | Pure parts are in CopilotCore with tests; the rest is small and reviewed; H-1 exercises it live |
| Pausing the owner transcriber cancelled the shared engine and could drop an interviewer phrase | `setPaused(_, cancelRecognizer: false)` (AC-03) |
| ⇧⌘M is also a Chrome shortcut («Profile» menu) while a session runs | Owner's choice (D5); the session scheme registers it only during a session; a failed registration falls back to ⌃⌥M like the other ⌘ keys; rebinding in Settings |
| A phrase spoken just before the press and still being decoded is dropped | Intended by D3 ("fully ignored"); the spoken-before-press part is not kept either |
| The armed phrase is a backchannel or noise and spends the one shot | Fillers/backchannel give `.none` (ordinary answer); the owner presses again |
| Armed and forgotten | 15 s self-disarm; disarmed on mute and session end |
| Mic off by mistake for a whole answer | Red state; the history/review marks (D7) say the answer was not recorded |
