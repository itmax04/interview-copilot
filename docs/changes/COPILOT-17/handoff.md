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

## P-01 — baseline at e2583df (2026-11-23)
- `swift build` PASS; `swift test` PASS, 525 tests in 92 suites.
- `scripts/run-evals.sh turn bank filter-text memory materials`: turn 0%/0%, mean 791 ms; bank top1 94.9%, top3 100%;
  filter-text 236/236; memory 8/8; materials 23/24 — all PASS.
- `scripts/secret-scan.sh` 0 findings; `scripts/check-localization.sh` 831/831.
- `scripts/build-app.sh`, Parakeet decode baseline (AC-03) and first-token baseline (AC-06/08): NOT RUN (the latter needs a
  recent session log and the models; taken before P-04/P-07).

## P-02 — exam-followup eval first (2026-11-23)
- `evals/exam-followup/cases.jsonl`: 48 synthetic cases (24 `opener-new` uk/ru/en, 24 `followup`, incl. three mid-sentence
  «що таке / что такое / what is» that must stay follow-ups); `copilot-eval exam-followup`; added to the default list of
  `scripts/run-evals.sh`; `evals/README.md` updated.
- Before P-03: **FAIL as expected**, 24/48 (opener-new 0/24, followup 24/24).

## P-03 — exam new-ticket openers (2026-11-23)
- `FollowUpDetector.newTicketOpeners` (uk/ru/en, 18 openers) + `startsNewTicket`: start-anchored, needs ≥ 2 words after the
  opener and no anaphoric word in the rest («назвіть їх», «describe it», «а що таке це…» stay follow-ups). Checked after the
  topic-shift and `newTicketMarkers`, before `isFollowUp`.
- `copilot-eval exam-followup`: **PASS 48/48**; `swift test` PASS, 526 tests (new `examOpeners…` test; existing exam tests unchanged).
- Executor decision E-5: the «≥ 2 words and no anaphora» guard is an addition to the spec's R-03 so that short anaphoric
  clarifications with an opener word are not cut off from the ticket.

## P-04 — Parakeet language hint (2026-11-23)
- `ParakeetEngine.languageHint(for:)` (uk/ru/en → FluidAudio `Language`, auto/unknown → nil) and `language: hint` in the
  `manager.transcribe` call; `ParakeetEngine.useLanguageHint` (default true) is the one-flag switch of R-02.
- `ParakeetLanguageHintTests` (mapping); the seam is the pure mapping function, the `manager.transcribe` call itself is
  covered only by the real-model check of P-05. `swift test` PASS, 528 tests.
- Not yet measured: effect on real audio, English terms, decode time (P-05).

## P-05 — real-model check of the hint (2026-11-23)
- Setup: 10 synthetic Ukrainian sentences (`say -v Lesya`, 16 kHz wav, kept outside the repo): 4 without terms, 6 with IT
  terms (Docker, Kubernetes, REST, PostgreSQL, Git rebase/merge, garbage collector, CI/CD, GitLab, TCP/UDP);
  `copilot-eval stt-parakeet … --lang uk --full-context --repeat 3` with and without the new flag `--no-lang-hint`.
- AC-03 latency: median decode **80 ms with the hint vs 78 ms without** (30 runs each) → +2 ms, within the ≤ 20 ms budget. PASS.
- AC-02(a): no sentence came out as English text with the hint. NOT a proof for the live case: the synthetic voice never
  produced English output without the hint either, so the live turn-1 English failure is **not reproduced** here.
- AC-02(b)/(c): without the hint the Lesya voice already pronounces the terms Ukrainian-style and Parakeet writes them in
  Cyrillic (e.g. «доокер», «Рестапі…»); with the hint the output is identical in 9 of 10 sentences, in the 10th only one
  Latin letter inside a misrecognized word became Cyrillic. So the synthetic set **cannot show** whether real English terms
  spoken with an English accent are lost: that stays **NOT VERIFIED** and is the main thing to look at in H-1 (e).
  All outputs are Cyrillic, so `LanguageGate` keeps them (no Latin to drop).
- R-02 decision: keep the hint on; `ParakeetEngine.useLanguageHint` stays the one-flag fallback if H-1 shows lost terms.
- `copilot-eval` got `--no-lang-hint` (comparison only).

## P-06 — Whisper corrects the ticket root (2026-11-23)
- `TicketRootUpdate.apply` (CopilotCore, pure) + `AnswerHistory.refineRoot` + `ActiveTopic.rootRefined`; wired in
  `AnswerController.refineTicketRoot`, called from the `onHistoryText` handler in `App.swift`. The memory text and the session
  report were already revised by that handler (COPILOT-15), so only the ticket/panel part is new.
- Guards: turn is the root entry's turn, `rootQuestion` and the entry text still equal the old text, ticket not changed
  (otherwise the root entry/turn no longer match), text non-empty, differs, not `HallucinationFilter`, not refined before.
  Log `ticket_root_updated turn= chars_old= chars_new=` (numbers only). No await, no hint regeneration (AC-06 by construction;
  the metrics replay is NOT RUN).
- Executor decision E-6: the history handler now also passes the audio seconds (`StreamingTranscriber.setHistoryHandler`,
  `ListeningController.onHistoryText`) so the hallucination check gets the real duration.
- Tests: `ActiveTopicUpdateTests` (6: root updated incl. follow-up `rootTitle`; non-root; changed ticket; text mismatch;
  empty/identical/hallucination; twice). The `AnswerCardView` title is `entry.rootTitle`, covered by the model assertion
  (no UI snapshot target exists in this package).
- `swift build` PASS; `swift test` PASS, 534 tests in 94 suites.

## P-07 — «Точный вопрос (+2 с)» setting (2026-11-23)
- `PreciseQuestionMode` (auto/on/off) + `waits(mode:session:language:)` in `Domain/Modes.swift`; `AppSettings.preciseQuestion`
  (default `.auto`, old files decode to it). Wait only when the language is `uk`; `auto` = exam sessions.
- Wiring: `App.sessionStarted` sets `listening.setHintWaitsForWhisper(...)`, `sessionEnded` resets it; applied to
  `StreamingTranscriber.setHintWaitsForWhisper(_:budget:)` (new; redecoder is built lazily from it, so it is fixed per session).
  Reuses the COPILOT-15 R-14 fallback B (`QuestionRedecoder.Config.waitsForWhisper`, budget 6 s); no new recognition path.
- Log `hint_wait_whisper turn= waited_ms= used=whisper|parakeet` (numbers only). Speculative drafts use the no-wait path
  (`release:false` redecode still goes through the same redecoder — see unverified below).
- Settings → Recognition: picker «Точный вопрос (+2 с)» (Авто (экзамен) / Включено / Выключено) + explanation; English lines added;
  `scripts/check-localization.sh` PASS.
- Tests: `PreciseQuestionSettingTests` (3×3×4 table, old-file decode + round trip); stalled-recognizer test in
  `OwnerAnswerRedecodeTests` (revise stalls 3 s, budget 0.4 s → nil in < 1.5 s, hint falls back to the Parakeet text).
  `swift build` PASS; `swift test` PASS, 537 tests in 95 suites.
- Unverified: the +2.2 s median (AC-08) needs live logs (H-1). R-07 «wait does not apply to speculative drafts and bank
  cards»: `turns.draftRedecode` shares the transcriber's redecoder, so a draft in a wait-on session would also wait —
  to be checked in the P-10 review / H-1 (possible fix: a per-call `waits:false` argument for drafts).

## Next
P-08: `QuestionAudioStore` (opt-in question-audio saving), then P-09, P-10, H-1.
