# Handoff — STT revision backlog + voice gate (live self-test 2026-11-20)

## Identity
- No COPILOT-NN id yet (side session of the "last long session" audit). Branch `claude/stt-revision-voice-gate-193912`,
  based on `origin/main` 2ae16bd. Code fix commit `b0c725d`. Not pushed, no PR (owner must allow).
- Shared notes: `~/Library/Application Support/Claude/side-session-notes/local_a3c0cf46-c051-4cac-8504-52d97c3f0d87/stt-revision-voice-gate.md`.

## Goal and scope
Fix two issues from the owner's live self-test ("Mac microphone" source, 15:40–17:00):
1. Words mixed in dense speech; `phrase_end_to_revised_ms` grew to 82–107 s.
2. With `ownerVoiceOnly: true`, threshold 0.6, the voice gate dropped 798 interviewer phrases; only 14 `turn_end`.
Owner expectation (from the brief): "interviewer voice → questions and hints, owner voice → answers".
Brief rule: if problem 2 is "setting vs bug" ambiguous — ask the owner, do not decide.

## Done
- `Sources/CopilotCore/STT/StreamingTranscriber.swift`: `Config.revisionMaxQueueDelay = 8` s; a revision that waited
  longer after phrase end is skipped (fast text kept, `revised` still emitted, log `transcript_revision_skipped`).
- `Sources/CopilotCore/Memory/InterviewMemory.swift`: `reviseText(_:to:scope:)` — one replacement, last whole-word
  occurrence; scope `.questions` / `.answers` / `.all`. Before: all substring occurrences in last 3 questions.
- `Sources/InterviewCopilot/App.swift`: interviewer revisions use `.questions`, owner revisions `.answers`.
- Tests: `RevisionBacklogTests.staleRevisionsAreSkipped`, `revisionDoesNotReplaceInsideOtherWords`,
  `revisionReplacesOnlyOneOccurrence`, `ownerAnswerRevisionDoesNotTouchQuestions`.

## Verified (against b0c725d's tree)
- Red before fix: 4 new tests failed (e.g. `"Когда вы начали…" → "КогТак. вы начали…"`; 8/8 revisions run, 2.45 s).
- `swift test` — PASS, 416 tests in 76 suites.
- `scripts/secret-scan.sh` — PASS, 0 findings.
- `scripts/run-evals.sh`, `scripts/check-localization.sh`, `scripts/build-app.sh` — NOT RUN (no UI strings added).
- Review: self-review of the diff only, not independent.
- Live app check of the fix — NOT RUN.

## Open
- Problem 2 is spec behavior, not a bug: COPILOT-05 intent Q13 / spec R-01 ("in Mac microphone mode only the owner's
  voice counts as questions"), answers via ⌃⌥A (COPILOT-06 R-08). Gate classified correctly (rejected median 0.40,
  accepted 0.66). Question sent to the parent session with options: (A) no code change, turn off "Only my voice" for
  rehearsals with a second voice; (B) route by speaker (other voice → question, owner → answer, no ⌃⌥A) — changes Q13;
  (C) (B) as a separate setting, (A) default. **Waiting for the owner's answer.**
- Refuted for this session: ring buffer overwrite (audio copied at phrase close), id mismatch in
  `SessionController.reviseUtterance`, engine race (Parakeet `inferenceLock`; owner channel paused in mic mode).
- Minor: `SessionController.reviseOwnerUtterance` matches by exact text — may swap revisions of two identical drafts.
- `first_token` growth to 4–7 s: plausibly CPU/GPU contention from the Whisper backlog; unproven.

## Next
Get the owner's choice for problem 2. If (B)/(C): update COPILOT-05 Q13/R-01 wording, implement routing in
`ListeningController.handle` (mic source + voiceprint: `foreignVoice` → question path, accepted → owner answer path),
add tests, run the full check list from CLAUDE.md, then ask the owner before push/PR. If (A): no code; record decision.
