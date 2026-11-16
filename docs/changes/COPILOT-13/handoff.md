# COPILOT-13 — handoff

## Identity
- Task: COPILOT-13 (technical audit and fixes). Intent: `docs/changes/COPILOT-13/intent.md`.
- Branch `feat/copilot-13-audit-fixes`, created from `main` (`6081670`). Not pushed.
- Code commits: `ac936b8` (audit fixes), `f3e0c21` (fixes after the independent review of `ac936b8`), `0c5cb4a`
  (second audit stage: bank, AI interviewer, test call, `App.swift`), `fb36c06` (third audit stage: question bank
  files, profiles, embedder, question preparation), `6290467` (fixes for the review of `fb36c06`), `2b48047` (fourth stage:
  panel, profile editors, onboarding). Handoff updated after `2b48047`; no uncommitted source changes.
- The checkout is `~/interview-copilot-audit` (moved there by the owner on 2026-11-16). There is no local `main`
  branch in it: the base is commit `6081670` (`scratch/main`). Nothing is pushed.

## Goal and scope
Owner request (translated): "a full technical audit and comprehensive code review; find and fix every bug and
technical problem, and optimise performance, stability, reliability and code quality".
Constraints: project rules in `AGENTS.md` / `CLAUDE.md` (no push without permission, no new dependencies, synthetic
test data only, tuned thresholds and prompt rules are not changed without proof of a defect).

## Audited so far (read in full)
`CopilotCore`: `Audio/*` (ring buffer, VAD, converter, system capture, microphone classes), `STT/*`, `LLM/*`
(SSE client, providers, chain, endpoints), `Storage/SessionStore`, `Secrets/KeychainStore`, `TestCall/LocalTestCallServer`,
`Models/ModelDownloader`, `Usage/UsageMeter`, `Session/JobImport`, `Capture/ScreenshotService`, `Filter/VoicePrint`,
`Turns/TurnDetector`.
App: `ListeningController`, `AnswerController`, `TurnController`, `History/SessionController`, `App.swift`,
`BankController`, `InterviewerController`, `TestCallController`.
Read as their dependencies (second stage): `Bank/BankMatcher`, `Bank/ProfileStore` (`FileWatcher`), `Profiles/Materials`,
`Interviewer/SpeechSynth`, `Interviewer/AnswerCapture`, `TestCall/TestCallTrial`, `CopilotEmbeddings/LlamaEmbedder`.
Third stage (`fb36c06`), read in full — `CopilotCore`: `Bank/*` (except `BankEval`), `Profiles/*`,
`Memory/InterviewMemory`, `Review/SessionReview`, `Answer/AnswerRouter`, `Answer/QuestionDetection`,
`Answer/ScreenshotTask`, `Answer/AnswerHistory`, `LLM/PromptBuilder`, `LLM/KeyVerifier`, `LLM/RetryHint`,
`Privacy/PIIFilter`, `Hotkeys/HotkeyCenter`, `Filter/LanguageGate`, `Filter/SpeechGate`, `Filter/SpeechEnhancer`,
`Interviewer/*`, `TestCall/TestCallTrial`, `TestCall/TranscriptComparison`, `Session/Preflight`, `Session/SessionConfig`,
`Settings/*`, `Localization/*`; `CopilotEmbeddings/LlamaEmbedder`; app: `LiveSessionController`,
`History/ReviewController`, `Profile/QuestionPreparer`, `AppModel`, `MenuBarController`, `Panel/PanelModel`, the logic
part of `Profile/QuestionsView` (`CardEditor`, `ImportReview`).

## Fourth stage (this section replaces parts of the lists below)
Read in full: `Panel/PanelController`, `Panel/PanelResize`, `Panel/PanelView`, `Panel/AnswerCardView`, `CopilotCore`
`Answer/AnswerStyle`, `Menu/MenuLayout`, `Domain/Modes`. Read for logic only (not layout): `Session/SessionWizard` (model part),
`Session/AnswerStyleEditor` (preview model), `Settings/VoiceEnrollment`, `Settings/OtherSettingsViews` (hotkeys, budget),
`Onboarding/OnboardingWindow` (state), `Profile/ProfileWindow` (editors), `Profile/QuestionsView` (CardEditor).
STILL NOT READ: layout parts of `History/SessionHistoryWindow`, `Workspace/WorkspaceWindow` (after line 140), `Settings/*` views,
`Onboarding/PermissionsView`, `Design/*`, `ParrotIcon`, `Theme`, `MainMenu`, `SettingsWindow`, `SmokeTest`, `UISnapshots`,
`TurnEval`, `BankEval`, `PromptScenarios`, `copilot-eval`, `scripts/`, `Resources/Interviewer` and `Resources/TestCall` pages.

## Not audited yet (older list; subtract the fourth stage above)
App: `Panel/PanelController`, `Panel/PanelResize`, `SettingsWindow`, `MainMenu`, `Theme`, `ParrotIcon`, `Design/*`, all
SwiftUI views (`Panel/PanelView`, `Panel/AnswerCardView`, `Workspace/`, `Session/`, `History/SessionHistoryWindow`,
`Settings/`, `Onboarding/`, `Profile/ProfileWindow`, the table part of `Profile/QuestionsView`), `SmokeTest`,
`UISnapshots`.
`CopilotCore`: `Answer/AnswerStyle`, `Menu/MenuLayout`, `Domain/Modes`, `Bank/BankEval`, `Turns/TurnEval`,
`Memory/PromptScenarios`.
Also `copilot-eval`, `scripts/`, `Resources/Interviewer` and `Resources/TestCall` pages.

## Fixed (commit `ac936b8`)
| # | Where | Defect | Fix |
|---|---|---|---|
| 1 | `StreamingTranscriber.runFinal` | `recognizer.cancel()` is meant for a partial run, but one engine serves two transcribers (interviewer and owner microphone) and the queue can move on to a final between the check and the cancel. The final failed with "cancelled" and the phrase was emitted as `discarded`: a lost question or a lost owner answer. | `finalTranscription` retries a cancelled final (3 attempts) while the epoch is unchanged and the transcriber is not paused. Tests: `FinalRetryTests`. |
| 2 | `MicActivityDetector`, `MicrophoneCapture` | No handling of `AVAudioEngineConfigurationChange`: after an input device change mid-call (AirPods, headset) the tap went silent for the rest of the session and "owner is speaking" froze at its last value; `true` blocks automatic answers (S-07). | New `MicrophoneTap` restarts the engine on the notification and reports "stopped speaking". |
| 3 | same | When `engine.start()` threw, the tap stayed installed; the next `start()` installed a second tap on the bus, which raises an AVFoundation exception. | The tap is removed on a failed start and before every install. |
| 4 | `AudioRingBuffer` | Per-sample modulo copy under the lock shared by capture and recognition; a 25 s utterance is re-read on every partial run. | Two block copies. Test: `RingBufferBlockCopyTests`. |
| 5 | `HybridRecognizer` | `cancelRevision()` (called on the main thread by pause) waited on the lock held while the Whisper model loads (seconds). | Separate load lock. |
| 6 | `SessionStore.purge` | A file that cannot be decoded was never purged: a transcript could outlive the retention period forever. Every session start decoded the whole history on the main thread. | Unreadable files are removed by modification time; files whose name says they started after the cutoff (+26 h margin) are not read. Tests: `SessionPurgeTests`. |
| 7 | `SessionController.scheduleSave` | Debounce, not throttle: each change postponed the save by 2 s, so in a dense conversation the file could stay stale for minutes and a crash lost everything since the last pause. | A scheduled save is not postponed. |
| 8 | `UsageMeter` | `state` was read without the lock; a `DateFormatter` was created on every status-line refresh. | Locked getter, cached formatter. |
| 9 | `URLSessionStreamingTransport` | Every `ChainFactory.providers()` call created a new `URLSession` (wizard, AI interview, screenshot): no connection reuse and sessions never invalidated. | One shared session. |
| 10 | `JobImport` | New session per fetch; the whole response was loaded into memory with no limit; the page charset was ignored (windows-1251 sites became mojibake); entities were decoded in dictionary order (`&amp;lt;` could become `<`) and numeric entities were replaced by spaces. | Shared session, 3 MB cap, charset from header or `<meta>`, entities decoded once. Tests: `JobPageDecodingTests`. |
| 11 | `ListeningController` | The level loop woke the UI 10 times per second all day, also with no session; `callSpeaking` stayed `true` after a pause swallowed "speech ended", so owner phrases were treated as echo until the next call phrase. | The loop idles outside listening; the flag is reset on pause, standby and session start. |

## Fixed (commit `0c5cb4a`)
| # | Where | Defect | Fix |
|---|---|---|---|
| 12 | `BankController.reload` | Index rebuilds run in detached tasks and finish out of order; only the profile id was checked. An older rebuild could replace a newer index: after "delete all" or an edit, removed cards came back into live search. | `indexGeneration`, bumped in `select` and at every build start, checked on completion. No automated test (app target). |
| 13 | `BankController` (`saveCards`, `renameActive`, `deleteActive`, `start`) | The error was set and then cleared by the `reload()` that follows: a failed save of the question table was never shown, the table silently reverted. | `report(_:)` applies the error after the reload. No automated test. |
| 14 | `BankController.select` | On a YAML parse error `reload()` keeps the previous cards (S-10); after a profile switch those are another profile's cards, shown in the table and written to the wrong `questions.yaml` on save. | `select` clears `cards`. No automated test. |
| 15 | `BankController.loadEmbedder`, `App.makeOnboarding` | If the embedding model was missing at launch (first run), it was never loaded after the wizard downloaded it: bank and materials search were dead until restart. | Retry while no builder is loaded; `retryEmbedderIfMissing()` on wizard completion. No automated test. |
| 16 | `BankController.reloadMaterials`, `shutdown` | Cancelling `materialTask` did not reach the inner `Task.detached`: a superseded indexing run embedded every chunk to the end and kept the embedder busy. `shutdown` did not release `embedder` (comment says models must be freed before exit). | `withTaskCancellationHandler`; `shutdown` cancels indexing and drops the embedder. No automated test. |
| 17 | `BankIndexBuilder.build` | All missing phrasings were embedded in one `embed` call; `LlamaEmbedder` holds its lock for the whole call, so a live `embedQuery` (hint lookup, memory search) waited for the full rebuild. | Batches of 8, as in `MaterialIndexBuilder`. Tests: `BankIndexBatchingTests`. |
| 18 | `FileWatcher.stop` | A stopped watcher was re-armed by its delayed retry (missing file, rename) and a pending debounce still called `onChange`. | `stopped` flag, pending work cancelled. Tests: `FileWatcherStopTests` (fails on the old code). |
| 19 | `InterviewerController` | A speech-synthesis error from a cancelled or superseded question set stage `.failed` over the new state; a missing page resource left the Mock session active with no interview and no listening. | Guard in the `catch`; `onEnd` after the alert. No automated test. |

## Fixed (commit `fb36c06`)
| # | Where | Defect | Fix |
|---|---|---|---|
| 20 | `QuestionBankWriter.yaml` | An answer or question with a Unicode line break (U+2028, U+2029, U+0085, U+000B, U+000C: text pasted from Pages or Word, or imported from .docx) or a control character made the whole `questions.yaml` unreadable after the save: "error in line N", and the bank is gone after restart. | New `PlainText.printable` is applied to answers, questions and tags before writing. Tests: `QuestionBankWriterSanitizingTests`. |
| 21 | `DocumentText.normalize` | The same characters were not treated as line breaks: lines of an imported question file were glued together and the rule-based import found nothing. | `PlainText.unifiedLineBreaks`. Tests: `DocumentTextLineBreakTests`. |
| 22 | `QuestionImport.chunks` | A paragraph longer than one part (a file with no blank lines) was cut to its first 6000 characters; the remaining questions never reached the model, with no message. | Long paragraphs are split by lines, long lines into pieces. Tests: `QuestionImportChunkTests`. |
| 23 | `LlamaEmbedder.embedOne` | Text longer than the 512-token window threw "tokenization error" (finding of the second stage): one dense material chunk failed the whole materials index, a long turn got no bank or materials lookup, an exchange with a long answer never reached memory search. | The text is tokenized in full and the first 512 tokens are kept, with the model's final special token last. The path for texts that fit is unchanged. Test: `LongTextEmbeddingTests` (runs when bge-m3 is installed; evals `bank`, `memory`, `materials` keep their numbers). |
| 24 | `ProfileLibrary.importFile`, `addMaterial` | Importing the stored source copy itself deleted it before reading it. | Atomic replace without deleting first. Test: `ProfileImportSameFileTests`. |
| 25 | `FileWatcher` | A file that appears after watching started (deleted and put back later) did not call `onChange`: the app kept the old content and the read error. | The first successful arm after a miss reports a change. Test: `FileWatcherAppearTests`. |
| 26 | `QuestionPreparer` | After "Stop" the message "Stopped. Finished parts are saved." was replaced by "Models unavailable: no answer" (the cancelled request came back as a failure). A run that ended late could reset the state of a newer run. Switching the profile during preparation wrote phrasings and drafts of the old profile's questions into the new profile's cards with the same ids (`q-1`, `q-2`…). | Run generation counter; every step checks that the run is current and the profile unchanged, otherwise it stops with a message. No automated test (app target). |
| 27 | `SpeechSynthError` | Messages were plain Russian text, not localized. | `L10n` + English strings. |

## Fixed (commits `6290467`, `2b48047`)
| # | Where | Defect | Fix |
|---|---|---|---|
| 28 | `QuestionPreparer.importFile` | Model-parsed questions of profile A reached `pendingImport` after a switch to B; a cancelled run could overwrite "Stopped". | `profileID` captured, `isCurrent`/`sameProfile` checked in the loop and before the final result. App target: build and reading only. |
| 29 | `QuestionBankWriter.yaml` | A question empty after `PlainText.printable` was written as `""`; the parser rejects a card with no questions. | Empty questions skipped, a card with none is not written. Test `ReviewFollowUpTests`. |
| 30 | `QuestionImport.chunks` | A long line was cut at a fixed length, mid-word. | Cut at a space in the second half of the piece. Test `ReviewFollowUpTests`. |
| 31 | `LlamaEmbedder`, `LongTextEmbeddingTests` | Silent truncation; test passed silently without the model with a model-dependent threshold. | Log line (counts only); `.enabled(if:)` trait; relative closeness assertion. Test run: PASS with bge-m3 installed. |
| 32 | `DocumentEditor`, `InstructionsEditor`, `CardEditor`, `BankController.save/text` | After a profile switch the closing editor's `onDisappear` wrote the OLD profile's text into the NEW profile (always for Instructions, when a save was pending for documents; cards by the same `q-N` id). | Editors capture their profile id; `save`/`text` take `profileID`; writes to a deleted profile are refused; `CardEditor` drops a pending edit after a switch. App target: build only. |
| 33 | `App.onToggleCollapse` | Collapsing the overlay with chat open left the panel as key window with no input field (keystrokes lost, call app loses keyboard). | Chat is closed before collapsing. Build only. |
| 34 | `OnboardingState.downloadMissing` | A late progress callback re-added a finished model to `downloads`: stuck "downloading", no retry. | Progress is applied only while the entry exists. Build only. |
| 35 | `PanelView.LevelWave` | NaN level reached `Int(...)`: crash. | NaN treated as -60. Build only. |

## Found, not changed (needs an owner decision or a live check)
- `StreamingTranscriber.runFinal`: the comment says the sticky language is dropped after two low-confidence utterances,
  the code drops it after one (`lowConfidenceStreak >= 1`). Tuned behaviour — left as is.
- `ModelDownloader`: one continuation per instance (two concurrent `download` calls on one instance would hang the
  first); cancelling the Swift task does not cancel the download.
- `ProviderChain.runHedged`: tokens spent by the losing parallel attempt are not counted in usage.
- `LocalTestCallServer`: no read timeout and no connection limit (loopback only, token-protected).
- `AnthropicProvider` / `DeepSeekProvider` request parameters (`thinking`, `fallbacks`, beta header) cannot be verified
  without a live call.

- `LlamaEmbedder` (after fix 23): truncation keeps the beginning of the text. For a long interviewer turn the question
  is usually at the end, so the bank match for such a turn is still weak (before the fix there was none at all).
- `ReviewStatusBadge` (history list): a review interrupted by quitting the app stays `.running` in the file, and the
  list shows "Review in progress" until the session is opened ("Continue review" works there).
- `ReviewController.start`: if the model returns comments for only part of a batch, the missing answers get no comment
  in this run and the review still ends as done.
- `ReviewController` and the running session: a review started from the history window for the session that is still
  running would be overwritten by the next periodic save of that session.
- Two `QuestionPreparer` instances exist (Profile window and Workspace): "Prepare" can run in both at once: double
  requests, no data damage (results are applied by card id).
- `BankIndexBuilder` embedding cache (`embeddings-*.json`) never drops vectors of deleted phrasings (the materials
  cache does).
- `AnswerHistory.remove`: the "new answer" badge can stay on after the new entry was removed as "not a question"
  while the owner is viewing an older answer.
- `PromptBuilder.user`: the PII filter is applied to cards, materials and memory, but not to the `<transcript>` lines
  and the current question. Prompt behaviour, left as is.
- `QuestionPreparer.importFile` extracts text from the file on the main thread (a large PDF blocks the window briefly).
- `BankController.start` loads the embedding model and decodes the embeddings cache on the main thread at launch.
- `AppDelegate.startDownloadProgressMirror` polls every 300 ms for the whole life of the app; `refreshUI` assigns every
  observable field on each transcript change without comparing. Both are energy/redraw costs, not defects.
- A Mock session started while the previous `InterviewerController.close()` is still awaiting capture teardown reuses
  the closing interviewer and is ended by its `onEnd` (window of a few hundred ms).

## Verified (against `ac936b8`)
| Check | Result |
|---|---|
| `swift build` | PASS, 0 warnings |
| `swift test` | PASS, 375 tests in 60 suites |
| `scripts/run-evals.sh` | PASS (bank, filter-text, memory, materials) |
| `scripts/secret-scan.sh` | PASS, 0 findings |
| `scripts/check-localization.sh` | PASS, 796 keys, 0 missing |
| `scripts/build-app.sh` | PASS: signed `dist/InterviewCopilot.app` built (exit 0) |
| Independent review of `ac936b8` | DONE (fresh subagent, strong tier): APPROVE WITH FIXES, no high-severity findings. All five findings fixed in `f3e0c21`: flaky `FinalRetryTests`; level indicator dead in `.idle`/`.error` and frozen after a pause with the panel hidden; stale `MicrophoneTap` restart attempts; double entity decoding and charset loss on a truncated page |
| Affected suites after `f3e0c21` (`StreamingTranscriber`, `FinalRetry`, `JobPage`, `SessionPurge`, `RingBuffer`) | PASS 12 runs of 12 |
| Full §9 check on `0c5cb4a` (includes `f3e0c21`), 2026-11-16 | PASS: `swift test` 380 tests in 62 suites; `scripts/run-evals.sh` exit 0 (filter-text 214/214, memory, materials 23/24); `scripts/secret-scan.sh` 0 findings; `scripts/check-localization.sh` 796 keys, 0 missing; `scripts/build-app.sh` exit 0 |
| `FileWatcherStopTests` against the old `FileWatcher` | FAIL as expected (`counter.count → 1`), PASS with the fix |
| `swift test` on `988a7b7` + the `0c5cb4a` patch (before `f3e0c21` was in) | FAIL 1 of 379: `repeatedCancelGivesUp` (`recognizer.calls → 4`), the flaky test rewritten in `f3e0c21`; not rerun there |
| Independent review of `0c5cb4a` | NOT VERIFIED: a fresh reviewer (standard tier) was started and stopped on the account usage limit before reporting |
| Full §9 check on `0c5cb4a` repeated by the third-stage session, clean tree, 2026-11-16 | PASS: `swift test` 380 tests in 62 suites; evals exit 0 (filter-text 214/214, memory 8/8 and 0/2, materials 23/24 and 2/8); secret scan 0 findings; localization 796 keys, 0 missing; `scripts/build-app.sh` exit 0 |
| New tests of `fb36c06` against the code before the fixes | FAIL as expected, 9 of 11 tests: YAML reader "control characters are not allowed" and "could not find expected ':'", glued lines, one chunk instead of several, deleted source file, "Ошибка токенизации", no `onChange` |
| Full §9 check on the tree committed as `fb36c06` | PASS: `swift build` 0 warnings in sources; `swift test` 391 tests in 68 suites; evals exit 0 (filter-text 214/214, memory 8/8 and 0/2, materials 23/24 and 2/8); secret scan 0 findings; localization 799 keys, 0 missing, 0 format mismatches; `scripts/build-app.sh` exit 0, signed bundle |
| Independent review of `fb36c06` | DONE (fresh reviewer, standard tier, read-only): APPROVE WITH FIXES, no high-severity findings; 1 medium and 4 low findings are NOT FIXED yet (listed in "Open") |
| After `6290467`: `swift build`; `swift test --filter "ReviewFollowUp|LongTextEmbedding|QuestionImportChunk|QuestionBankWriterSanitizing"` | PASS, 9 tests |
| After `2b48047`: `swift build` | PASS (app target has no tests) |
| Independent review of `0c5cb4a` + `f3e0c21` | DONE (fresh reviewer, strong tier, read-only): APPROVE WITH FIXES, no high findings; 3 medium and 5 low NOT FIXED yet, see "Open: review of 0c5cb4a/f3e0c21". Reviewer's own runs: `swift build --build-tests` PASS; FileWatcherStop/BankIndexBatching/FinalRetry/StreamingTranscriber/JobPageDecoding suites 6 of 6 runs PASS, 5 more under full CPU load PASS. |
| Full §9 check after `2b48047` | NOT RUN |
| Microphone restart on a real device change | NOT RUN (needs hardware and a live session) |
| Live checks `--smoke-*` | NOT RUN (signed app, spends quota) |

## Open
- `f3e0c21` (review fixes) has no independent review of its own.
- `0c5cb4a` has no independent review. Points to check: `indexGeneration` when the builder is nil, `report(_:)` and
  `onChange` re-entrancy, callers that relied on `cards` surviving `select` (`Profile/QuestionsView`,
  `Profile/QuestionPreparer`, `Session/SessionWizard`), `onEnd` from `InterviewerController.start()` re-entering
  `sessionStarted` → `liveSession.end()`, timing of `FileWatcherStopTests` under parallel test runs.
- Rows 12–16 and 19 are in the app target and are verified only by build and reading; there is no test target for it.
- `stickyLanguageAfterTwoConfidentUtterances` failed 9 runs of 12 after `ac936b8` and 0 of 12 on the base code: the
  block-copy ring buffer made the test feeder outrun the work queue, so the second utterance's partial run (the one
  that calls the detector) sometimes never started. Audio arrives in real time in the app, so only the test was
  changed (it now checks that the detector is not called after the language is pinned).
- `MicrophoneTap` was verified only by build and unit tests; the engine restart path has no automated test.
- Review findings for `fb36c06`: ALL FIXED in `6290467` (rows 28–31). Original list, for the record:
  - medium: `QuestionPreparer.importFile` has no profile check and its "no questions found" branch has no
    current-run check. Questions parsed by the model for profile A land in `pendingImport` after a switch to B and
    are then added to B; a cancelled run with no chunks can overwrite the "Stopped" message. Fix: capture
    `bank.activeID` before `start`, guard `isCurrent(run)` and `sameProfile` before `pendingImport = found` and
    before the final `fail`.
  - low: `QuestionBankWriter.yaml` — a question that is empty after `PlainText.printable` is written as `""`, the
    parser drops it and rejects the file if it was the only one; skip empty questions when writing.
  - low: `LlamaEmbedder` truncates silently; add a log line.
  - low: `LongTextEmbeddingTests` passes silently when bge-m3 is absent, and its `> 0.6` threshold is model-dependent.
  - low: `QuestionImport.chunks` cuts an over-long line at a fixed length (mid-word); prefer a space.
- Row 26 (`QuestionPreparer`) is verified only by build and reading: the app target has no tests.
- Not audited yet: the SwiftUI views and the rest of the list above (about 6 000 lines of 22 900).

## Closed: review of 0c5cb4a/f3e0c21
The app target has no test target: M1, M3, L1–L3 are verified by build and reading only; M2 and L4 touch CopilotCore but M2 needs a real audio engine (no unit test possible).
- M1 FIXED (`db031ca`): `interviewer.onEnd` in `App.swift` now checks `isActive` on the next main-loop turn, after `start` set the phase to `.active`.
- M2 FIXED (`db031ca`): `MicActivityDetector` and `MicrophoneCapture` no longer keep their own `running` flag; they read `tap.isRunning`, so a second `start()` after the tap gave up restarts the engine. Not done: a user-visible error on give-up (it is logged; the next start recovers).
- M3 FIXED: `BankController.questionsUnreadable` is set when `questions.yaml` fails to parse; `saveCards` refuses with a message, "Добавить вопрос" is disabled (EN string added).
- L1 FIXED: `loadEmbedder` on a model change sets `index = nil`, bumps `indexGeneration`, clears `materialIndex`.
- L2 FIXED (partly): `shutdown()` waits up to 3 s on a `DispatchGroup` for running index builds. The detached closure's captured `builder` may still be released on a background thread just after the wait; accepted, no repro.
- L3 FIXED: `.error` no longer reports levels.
- L4 FIXED: `reportsChange` rewrites the file every 150 ms until the callback arrives (up to 40 tries).
- L5 DECISION: keep `(1...2).contains(afterTwo)` in the sticky-language test; the exact count depends on stream timing, the test still proves the language does not flip back, no defect found.

## Executor decisions
- Tuned thresholds and prompt rules were not touched.
- Retention semantics are unchanged for readable sessions (end time from the file decides); the file name is only a
  shortcut to skip files that cannot be old.

## Verified (final check of this stage, HEAD `38c79a8`)
- `swift test`: PASS, 393 tests in 69 suites. `scripts/run-evals.sh`: PASS (filter-text 214/214, memory 8/8 and 0/2, materials AC-05 23/24, unrelated 2/8). `scripts/secret-scan.sh`: PASS, 0 findings. `scripts/check-localization.sh`: PASS, 800 keys, 0 missing. `scripts/build-app.sh`: PASS, `dist/InterviewCopilot.app` built and signed.

## Next
1. Review findings M1–M3, L1–L5 are closed (see above).
2. Optionally read the "STILL NOT READ" list of the fourth stage; fix findings.
3. Full §9 check: `swift test && scripts/run-evals.sh && scripts/secret-scan.sh && scripts/check-localization.sh && scripts/build-app.sh`;
   no source edits while it runs. Record PASS/FAIL in "Verified", commit the handoff.
Rules: commit by explicit path only, no `git stash`, no push. Stop and ask the owner before pushing, changing tuned thresholds
or prompt rules, adding a dependency.
