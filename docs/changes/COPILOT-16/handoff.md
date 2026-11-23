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

## Next
P-03 (LanguageGate on `.call`). Owner review of spec/plan is welcome but not a checkpoint; the next owner checkpoint is H-1 (live call).
