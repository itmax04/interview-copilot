# COPILOT-16: Handoff — capture only the call, lock the session language

## Identity
- Branch `feat/copilot-16-source-language`, created from `feat/copilot-15-accurate-turns` at 36a3402 (COPILOT-15 is not
  merged into `main`; it is the previous task's branch, as CLAUDE.md requires).
- Intent commit: 06f29fd. Not pushed, no PR.

## Goal and scope
See [intent.md](intent.md). Owner decision 2026-11-21: «Источник и язык» — options 1 + 2 of the brainstorm (capture only
the call app with a warning for "All system audio" and for other audible apps; a fixed session language with a gray line
for other languages and a one-action switch) plus a live silent-microphone warning. Interviewer voice anchoring and the
"not an interviewer" hotkey are later tasks.

## Done
- Stage 0 (brainstorm and analysis, Opus): the session of 2026-11-21 19:05–19:09 was analyzed from its session file and
  the app log; findings in intent.md "Problem". `docs/changes/COPILOT-16/intent.md` written.

## Verified
- `scripts/secret-scan.sh` — PASS, 0 findings (at 06f29fd).
- `swift build && swift test` — NOT RUN (docs only).

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
- Meet browser (Chrome / Safari / Arc) — unknown; ask at an H-checkpoint.
- Cause of the silent microphone (`mic_db=-120.0` all session, owner answered into the Mac during a Telegram call) is
  unknown; suspected the call app holding the input or a different input device. Needs a device check with the owner.
- Pseudo-English from German: the text detector says `en`; check on synthetic samples (`evals/`) that the stricter rule
  catches such phrases without dropping uk/ru questions with IT terms (filter-text eval must stay 214/214 or be extended).
- CLAUDE.md still says the latest task is COPILOT-13 (stale; update when this task's docs land).

## Next
Write `spec.md` (requirements R-…, acceptance criteria AC-… with measurable checks, synthetic test data only) and
`plan.md` (steps with commands, H-checkpoints: the owner's answers to O1–O4 and a live check on a real call), then
implement step by step with a commit and a handoff update after each step. Checks: quick `swift build && swift test`;
full set from CLAUDE.md before reporting done. Independent review (fresh subagent, standard) of the code changes before
asking the owner to accept. Stop and ask the owner at the H-checkpoints only.
