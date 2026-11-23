# COPILOT-17: Handoff — Ukrainian question stays Ukrainian, new question starts a new ticket

## Identity
- Branch `feat/copilot-17-uk-question`, created from `feat/copilot-16-source-language` at 50e65b6 (COPILOT-16 is not merged
  into `main`; it is the previous task's branch, as CLAUDE.md requires). Not pushed, no PR.
- Documents commit: see the git log (`COPILOT-17: intent, spec, plan, handoff`). **No code changed yet.**

## Goal and scope
See [intent.md](intent.md). Owner decisions of 2026-11-23: fixes 1+2+3 (Parakeet `language:` hint, exam new-ticket openers,
Whisper corrects the ticket root), variant B (`hintWaitsForWhisper`) for uk only behind «Точный вопрос (+2 с)» (default on
for exam sessions), opt-in local saving of question audio. No cloud STT (ADR-0001 amendment of 2026-10-08), no bake-off here.

## Source
Diagnosis of the live session of 2026-11-23 18:32:43–18:33:54: side-session note
`~/Library/Application Support/Claude/side-session-notes/local_b3470773-375b-4b4a-abba-ed615b1e6a58/copilot17-uk-question-diagnosis.md`
(outside the repo; verified causes with file:line; not re-diagnosed). Transcript text is deliberately not copied anywhere.

## Done
- Read AGENTS.md, CLAUDE.md, docs/ARCHITECTURE.md, the diagnosis; COPILOT-16 used as the document format.
- `intent.md`, `spec.md` (R-01…R-11, AC-01…AC-15), `plan.md` (P-01…P-11, H-1) written.

## Verified
- Nothing run: documents only. `swift build`, `swift test`, evals, secret-scan, localization, `build-app.sh` — **NOT RUN**.
- Code references in the spec were checked by reading the source at 50e65b6: `ParakeetEngine.swift` (no `language:` in the
  `manager.transcribe` call), `ScreenshotTask.swift:195-228` (`newTicketMarkers`, `isExamFollowUp`),
  `StreamingTranscriber.swift` (`hintWaitsForWhisper` :54, `onHistoryText` :84/:134), `ActiveTopic.swift`,
  `SessionStore.deleteAll`, `AppPaths`.

## Executor decisions (documents stage)
- E-1: the effective-wait rule is a three-state setting (`auto`/`on`/`off`): the owner's "on by default for exam" needs a
  value that depends on the session type, so a plain Bool would not express it.
- E-2: the audio saving covers the interviewer's call channel only (not the owner's microphone): the bake-off needs question
  audio, and this keeps the owner's own speech out of the files.
- E-3: sidecars hold numbers only; the transcript stays in the session JSON, which already exists and is already purged and
  wiped by the history controls.
- E-4: the Parakeet hint can be switched off with one flag if the English-term regression (R-02) shows up; the spec does not
  claim the hint separates uk from ru (it cannot: both Cyrillic).

## Open / NOT VERIFIED
- Whether the script filter damages English IT terms in uk/ru sentences on real call audio (AC-02, H-1).
- The final opener list for R-03 (to be tuned on the eval in P-03).
- The cause of the misheard key word on live audio (needs the saved audio of R-09; the bake-off is a separate task).
- Baseline latency numbers (P-01).

## Next
Owner reviews the documents. Then P-01 (baseline) and P-02 (eval first). Tier: standard (Sonnet 5.5 medium), in a new session.
