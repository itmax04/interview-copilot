# Handoff — STT revision backlog + voice gate (live self-test 2026-11-20)

## Identity
- No COPILOT-NN id yet (side session of the "last long session" audit). Branch `claude/stt-revision-voice-gate-193912`,
  based on `origin/main` 2ae16bd. Problem 1 fix `b0c725d`; problem 2 (option C) `c1eb9ee`, `04ad18e`, `9296fa1`.
  Not pushed, no PR (owner must allow).
- Shared notes: `~/Library/Application Support/Claude/side-session-notes/local_a3c0cf46-c051-4cac-8504-52d97c3f0d87/stt-revision-voice-gate.md`.

## Goal and scope
Fix two issues from the owner's live self-test ("Mac microphone" source, 15:40–17:00):
1. Words mixed in dense speech; `phrase_end_to_revised_ms` grew to 82–107 s. — done in `b0c725d`.
2. With `ownerVoiceOnly: true` the voice gate dropped 798 interviewer phrases (spec behavior, COPILOT-05 Q13).
   Owner chose **option C**: a separate setting, old behavior stays the default.

## Done — problem 1 (b0c725d)
- `StreamingTranscriber.Config.revisionMaxQueueDelay = 8` s: stale revisions skipped (`transcript_revision_skipped`).
- `InterviewMemory.reviseText(_:to:scope:)` — one whole-word replacement; interviewer `.questions`, owner `.answers`.
- Tests `RevisionBacklogTests.*`.

## Done — problem 2, option C
- Setting `AppSettings.rehearsalWithInterviewer` (default false, decoded with default — old settings load). Toggle in
  Settings → Audio → «Ваш голос»: «Репетиция с собеседником: чужой голос — вопросы, мой — ответы» + footnote; English in
  `Resources/en.lproj/Localizable.strings`.
- `VoicePrint.swift`: `VoiceVerdict { similarity, accepted, routeBySpeaker }`; `VoiceGateBox.State.routeBySpeaker`;
  `check(_:ignoringActive:allowRouting:)` (call-time owner channel passes `allowRouting: false`).
- `StreamingTranscriber`: `VoiceCheck` returns `VoiceVerdict?`; with `routeBySpeaker` a verdict is emitted as new
  `TranscriptEvent.speaker(utterance:owner:similarity:)` before `.revising`/`.final` (log `voice_speaker`), and the phrase
  continues as a normal final with revision. Without the flag: unchanged (`.foreignVoice` / `voice_ok`).
- `Filter/SpeakerRouter.swift`: `route(utterance:ownerAnswering:)` → `.question` / `.ownerAnswer`; ⌃⌥A on → always
  answer (manual override); rehearsal + verdict → by speaker; no verdict → ⌃⌥A state. Bounded (20), reset per session.
- `ListeningController`: `updateVoiceGateActive` turns the gate on in rehearsal (mic source, no test call, no AI
  interview route) even with «Только мой голос» off; `handle` records `.speaker`, swallows `.revising` of owner-routed
  phrases, sends owner finals to `recordOwnerAnswer` (log `owner_final … mode=rehearsal|self-test`), others go the
  normal question path (language filter applies).
- Other `TranscriptEvent` switches (`TurnController`, `TestCallTrial`, `AnswerCapture`) ignore `.speaker`.
- Docs: COPILOT-05 intent Q13 + spec R-01, COPILOT-06 spec R-08, AGENTS.md, ARCHITECTURE.md.
- Tests `SpeakerRoutingTests` (11): rejected → speaker+revising+final+revised; accepted → speaker(owner); no verdict →
  no speaker; setting off → `.foreignVoice`/plain final; verdict routing only where allowed; router table (rehearsal,
  no verdict vs ⌃⌥A, override, off, forget/bound); settings default + old JSON + round trip.

## Executor decisions
- Verdict travels as a separate event before `.final` (like `.revising`), not as a new field of `.final` (26 pattern
  sites) and not as UI-layer hacks.
- ⌃⌥A in rehearsal forces every phrase to an answer (including foreign verdicts) — the override exists for gate errors.
- Owner auto-answers log `mode=rehearsal` (⌃⌥A answers keep `mode=self-test`); no script parses the field.
- Footnote names the menu action «Сейчас отвечаю я» instead of "⌃⌥A" (the hotkey is reassignable).

## Verified
- `swift test` — PASS, 427 tests in 77 suites (HEAD 9296fa1); `SpeakerRoutingTests` 12/12 after 0eb485c.
- `scripts/run-evals.sh` — PASS at 0eb485c (turn 0%/0%, bank top1 94.9%, filter-text 214/214, memory 8/8,
  materials 23/24). First run exited 1 with no output while `swift test` was building concurrently; rerun alone passed.
- `scripts/secret-scan.sh` — PASS, 0 findings. `scripts/check-localization.sh` — PASS, 807/807 keys, 0 format mismatches.
- `scripts/build-app.sh` — PASS, `dist/InterviewCopilot.app` signed (started at 4625e5a; 0eb485c changes only router logic).
- Independent review (Sonnet, fresh subagent): no OFF-mode behavior change; 2 low findings fixed in 0eb485c
  (route pinned at `.revising` via `SpeakerRouter.decide`; router reset when rehearsal mode/source changes);
  2 tiny epoch-race notes accepted (self-healing).
- Live app check of rehearsal mode — NOT RUN (needs the owner: mic + second voice + voice sample).
- `ListeningController.handle` (executable target) has no unit tests; its decisions are in `SpeakerRouter`, tested.

## Known limitations
- In rehearsal the speaker is known only at the final: the owner's partial text shows as the interviewer's partial
  line until then, and the owner's `speechStarted` reaches the turn detector. If the owner starts answering within the
  pause T after a question, that question's hint waits until the owner's first phrase is recognized (then
  `phraseDiscarded` rewinds the pause and the turn fires).
- No overlay indicator that rehearsal mode is on (⌃⌥A banner only for the manual mode).
- Minor (old): `SessionController.reviseOwnerUtterance` matches by exact text.

## Next
Owner: live check of rehearsal mode (Settings → Audio → toggle, "Mac microphone", video voice asks, owner answers;
expect `voice_speaker`, `owner_final … mode=rehearsal`, hints only for the other voice). Then permission to push / PR.
