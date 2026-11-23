# COPILOT-16: Handoff — capture only the call, lock the session language

## Identity
- Branch `feat/copilot-16-source-language`, created from `feat/copilot-15-accurate-turns` at 36a3402 (COPILOT-15 is not
  merged into `main`; it is the previous task's branch, as CLAUDE.md requires).
- Intent commit: 06f29fd. Spec and plan: see below. Not pushed, no PR.

## Goal and scope
See [intent.md](intent.md). Owner decision 2026-11-21: «Источник и язык» — options 1 + 2 of the brainstorm (capture only
the call app with a warning for "All system audio" and for other audible apps; a fixed session language with a gray line
for other languages and a one-action switch) plus a live silent-microphone warning. Interviewer voice anchoring and the
"not an interviewer" hotkey are later tasks.

## Done
- Stage 0 (brainstorm and analysis, Opus): the session of 2026-11-21 19:05–19:09 was analyzed from its session file and
  the app log; findings in intent.md "Problem". `docs/changes/COPILOT-16/intent.md` written.

## Work merged before the spec (2026-11-22…23, outside the plan)
Six commits landed on this branch without spec/plan: 89522df (Wave 1: output sanity guard, generation isolation,
interruption owner flush, short follow-ups), cd4879c (Waves 2–3: ActiveTopic RAG, Exam mode, transcript sanity check,
follow-up return UX), 13e669e (TurnDetector barge-in window < 600 ms), 826c987 (Exam live-run fixes), a45f63b (1-click
Quick Start; Auto falls back to All system audio; Teams/Discord/Safari in Auto), 9922aee (owner voice question repeat,
lecture STT vocabulary from materials, strict answer language for the LLM, macOS mic mute banner).
Relation to this task: a45f63b reverses the intent's "call-only by default" — **owner decision 2026-11-23: keep All system
audio for Quick Start / Auto fallback and add a warning** (spec R-06). 9922aee's mute banner covers one silent-mic cause.
Observed: Quick Start writes `.allSystem` into the saved source setting (not changed by this task).

## Spec and plan (2026-11-23)
`spec.md` (R-01…R-09, AC-01…AC-08) and `plan.md` (P-01…P-08, H-1) cover only the remaining scope: language gate on the
call channel, "auto" language lock, live silent-mic notice, All-system-audio warning.

## Verified
- `scripts/secret-scan.sh` — PASS, 0 findings (at 06f29fd).
- `swift build && swift test` — NOT RUN at 06f29fd (docs only); **PASS at 9922aee** (2026-11-23): 502 tests in 87 suites.
- At 9922aee: `scripts/run-evals.sh` PASS (turn 0%/0%, mean 791 ms; bank top1 94.9%; filter-text 214/214; memory 8/8;
  materials 23/24); `scripts/secret-scan.sh` PASS, 0 findings; `scripts/check-localization.sh` PASS, 821/821;
  `scripts/build-app.sh` NOT RUN.

## P-02 — eval cases first (2026-11-23)
- `evals/filter/text-cases.jsonl`: 4 `english-call` → drop; +14 `pseudo-en-call` (7 synthetic phrases × uk/ru, `.call`, drop);
  +8 `terms-call` (keep). Total 214 → 236 cases. No real transcript text.
- `scripts/run-evals.sh filter-text` before P-03: **FAIL as expected**, 218/236 correct (18 wrong: english-call 0/4,
  pseudo-en-call 0/14; terms-call 8/8). Next: P-03.

## P-03 — LanguageGate on `.call` (2026-11-23)
- `LanguageGate.check`: whole English phrase (≥ 3 words, not a term phrase ≤ 4 meaningful words) is dropped on every channel
  when `en` is not allowed (`allowed.contains("en")` is the only keep condition); term-phrase and short-phrase rules unchanged.
  `channel` is kept in the signature (call sites in `ListeningController` untouched; they compile and still pass `gateChannel`).
- Doc comment updated (Q8 superseded); COPILOT-05 `spec.md` R-05 and `intent.md` Q8 carry a superseded note.
- `LanguageGateTests`: `englishPhraseRulesDoNotDependOnChannel` (uk/ru drop, en/auto keep, all channels),
  `pseudoEnglishOnCallIsDropped`, `termAndShortPhrasesPassOnCall` (AC-02).
- Checks: `swift build` PASS; `swift test` PASS 504 tests in 87 suites; `scripts/run-evals.sh`: filter-text 236/236 PASS (AC-01),
  turn 0%/0% mean 791 ms, bank top1 94.9%, memory 8/8, materials 23/24 — all unchanged PASS. secret-scan / localization /
  build-app NOT RUN in this step (no strings or secrets touched).

## Code pointers found during the analysis
- `Sources/CopilotCore/Filter/LanguageGate.swift` — `.auto` → {slavic, en}; whole English phrases are kept on `.call`
  always and on `.allSystem`/`.mic` only when `allowed` contains "en".
- `Sources/CopilotCore/Audio/AudioSourceResolver.swift` — `.allSystem`, `.auto` (Zoom → Chrome → Telegram).
- `Sources/CopilotCore/Session/Preflight.swift` — mic peak check ("Тихо — …") and call signal check; no warning for
  "All system audio" or for other audible apps.
- `Sources/InterviewCopilot/ListeningController.swift` — `updateVoiceGateActive` (gate only on the mic channel),
  `updateOwnerChannel`, the `level_db … mic_db … owner_speaking` log line (~line 1046).
- `Sources/CopilotCore/Session/SessionConfig.swift` — the session `language` (the analyzed session had "auto").

## Owner answers (2026-11-21, recorded in intent.md v2)
The stray speech was **German spoken near the owner**, picked up by the interviewer-side mic (iPhone + wired AirPods) and
delivered through Telegram — i.e. it came on the call channel, not from another Mac app. Interviewers never switch to
English, only IT words. Calls: mostly Meet, sometimes Telegram/Discord/Zoom. Number of interviewers varies.
Priority for the spec therefore: (1) language gate drops whole foreign/English phrases on the `.call` channel too when the
session is uk/ru, and "auto" settles on the interview language; (2) silent-mic detection + cause during a Telegram call;
(3) call-only capture by default, "All system audio" warning, Discord in the auto list.

## Open
- Meet runs in **Google Chrome** (owner, 2026-11-21). Capturing Chrome takes every Chrome tab: consider a preflight note
  about other audible Chrome tabs if it can be detected; otherwise document it.
- Cause of the silent microphone (`mic_db=-120.0` all session, owner answered into the Mac during a Telegram call) is
  unknown; suspected the call app holding the input or a different input device. Needs a device check with the owner.
- Pseudo-English from German: the text detector says `en`; check on synthetic samples (`evals/`) that the stricter rule
  catches such phrases without dropping uk/ru questions with IT terms (filter-text eval must stay 214/214 or be extended).
- CLAUDE.md still says the latest task is COPILOT-13 (stale; update when this task's docs land).

## P-04 — SessionLanguageLock (2026-11-23)
- `Sources/CopilotCore/Filter/SessionLanguageLock.swift` (pure): in "auto" locks to slavic/en after 3 consecutive kept
  interviewer phrases (≥ 3 words) of one group (a mixed ≥ 3-word phrase breaks the streak; short ones are ignored);
  `effectiveSetting(base)` feeds `LanguageGate`; 2 consecutive `en` drops in a uk/ru (set or locked) session raise the
  notice once; `allowEnglish()` opens English for the session (also for explicit uk/ru, no relock); `reset()` per session.
- `ListeningController`: `languageLock` reset in `startSession`; `filterReason` uses the effective setting, logs
  `language_locked group=… after=3`, raises `englishNoticeVisible`; `allowEnglish()` logs `language_unlocked reason=owner`.
  Settings are not changed (session state only). Mic-channel gate in `handleOwner` is untouched (owner's own speech).
- Panel: banner «Собеседник говорит по-английски?» + button «Разрешить английский» (`PanelModel.englishNoticeVisible`,
  `onAllowEnglish`, synced in `App.updateLevels`); the notice hides on the next kept phrase or after the action. English
  strings added to `Resources/en.lproj/Localizable.strings`. Executor decision: notice is a banner row in the existing
  banners block (same style as the mute banner), no new animation, so Reduce Motion is not affected.
- `SessionLanguageLockTests` (9 tests, AC-03).
- Checks: `swift build` PASS; `swift test` PASS 513 tests in 88 suites; run-evals: filter-text 236/236, others unchanged PASS;
  check-localization PASS (823 keys, 0 missing); secret-scan PASS (0 findings); build-app NOT RUN; UI not checked visually.

## P-05 — MicSilenceDetector (2026-11-23)
- `Sources/CopilotCore/Audio/MicSilenceDetector.swift` (pure): peak ≤ −119 dB for ≥ 10 s with the channel active and the mute
  flag off → `isSilent`; `update` returns true once per episode (log moment); any louder sample, mute, or inactive channel resets.
  `DefaultInputMute.deviceName()` (CoreAudio `kAudioObjectPropertyName`) gives the input device name.
- `ListeningController.micExpected` (listening, not a test call, source mic or owner channel on). `App.updateLevels` feeds the
  detector (10 Hz) and logs `mic_silent seconds=… device=… muted=false` (device is `.private`). `PanelModel.micSilent`,
  `micSilentDevice`; PanelView shows an `AlertBox` with the device name and the hint (another app may hold the mic; check
  System Settings → Sound) and hides it while the mute banner is shown (mute has priority).
- `MicSilenceDetectorTests` (6 tests, AC-04). English strings added.
- Checks: `swift build` PASS; `swift test` PASS 519 tests in 89 suites; filter-text 236/236, evals otherwise unchanged PASS;
  check-localization PASS (825 keys); secret-scan PASS; build-app NOT RUN; UI snapshot NOT RUN (not checked visually).

## P-06 — "All system audio" notice (2026-11-23)
- `AudioSourceResolver.runningCallApp` / `allSystemNotice(for:running:)` (pure): notice only for `.allSystem`; `callApp` is the
  first running app by `autoPriority` (Discord is already in the list).
- `ListeningController`: `allSystemNotice` (refreshed on source change and app launch/terminate), `dismissAllSystemNotice()`,
  `switchToCallOnly()` — a per-session `sessionSourceOverride` (settings untouched; reset in `startSession`), log
  `source_call_only app=…`. Executor decision: override instead of changing `settings.audioSource`, per R-06 "for the session".
- Panel: warning row «Слушаю весь звук Mac — …» with «Только звонок» (only when a call app runs) and a dismiss button.
  Wizard: footnote under the source picker for All system audio / Auto, and a Chrome note («захватываются все вкладки»)
  when Chrome is chosen. English strings added.
- `AllSystemNoticeTests` (4 tests, AC-05 logic part).
- Checks: `swift build` PASS; `swift test` PASS 523 tests in 90 suites; filter-text 236/236, evals unchanged PASS;
  check-localization PASS (831 keys); secret-scan PASS; build-app NOT RUN; UI snapshot (`UISnapshots`) NOT RUN — not checked visually.

## Next
P-07: documents, independent review (fresh subagent, standard), full check and `scripts/build-app.sh`. Then H-1 (owner live call).
