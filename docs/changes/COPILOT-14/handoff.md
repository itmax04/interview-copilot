# COPILOT-14 technical audit

## Identity and scope

Branch `feat/copilot-14-technical-audit`, based on `bc64695` (public main and COPILOT-13). Scope and baseline are recorded in `f6bcdba`. First audit implementation: `bad6051`. The audio lifecycle stage started from the clean handoff commit `180e72b`. Its verified implementation is `031d94a`. The browser recovery stage started from `7dd55de` and its verified implementation is `8480f40`. The previous task's handoff identifies the components it reviewed and the areas it left open. This pass examined the app's history and profile flows, model installation, offline evaluation entry points, progress updates, and synthetic UI checks. The follow-up traced rapid End → Start across the live session, browser controller and audio device.

## Findings and changes

| Priority | User-visible failure | Repair and evidence |
| --- | --- | --- |
| High | On first launch, downloading the speech and embedding models together could leave onboarding stuck. The two sessions shared one completion and progress handler. | Each transfer owns its URLSession delegate, result and staging file. A verified file replaces the destination atomically. A loopback test with two different payloads failed on the baseline with a leaked continuation and a missing file. It checks both outputs and progress, plus an HTTP error and a bad checksum when a valid file already exists. |
| High | Deleting a live transcript from history let autosave or End recreate it. A conversation containing only owner speech could disappear on End. | Both history surfaces use SessionController for deletion. Stopping persistence precedes bulk deletion so partial filesystem failure cannot resurrect data. The save predicate includes both speakers. An in-process session ID remains reserved across deletion. Tests cover single/bulk deletion, failure and a subsequent call. |
| Medium | A partial model reply could mark the entire review complete. An interrupted run could appear active after restart, and starting review/chat on a live session could lose the result on autosave. | Checkpoint valid comments, pause incomplete batches, and request the missing answers on retry. Resolve status from stored progress and the actual worker in both history surfaces. Old incomplete reviews can resume. Stop processing when a checkpoint cannot be written. Guard live sessions in the controller and UI. |
| Medium | Long legacy transcripts escaped the prompt budget, an oversized final utterance could be lost, and old turn-only sessions could send an empty transcript. | Apply the character budget to every storage format and keep the latest text. Use historical questions for turn-only records. |
| Medium | A pending file import or an asynchronous drop could write into a different profile. Generated drafts could populate a question outside the requested batch. | Check profile identity when accepting the import or completing the drop. Limit draft updates to requested card IDs. Report save failures and retain import data for retry. |
| Medium | Empty or malformed offline datasets could pass, invalid memory references could terminate the evaluator, and options were sometimes read as filenames. | Validate datasets and reference bounds, parse supported options before positional paths, and reject nonpositive repetition counts. Evaluate Silero once per clip for both the probability and the speech decision. |
| Medium | Apple’s Python 3.9 lacks hashlib.file_digest, breaking documented model setup on machines using that interpreter. | Stream SHA-256 in blocks. Synthetic install, cache hit and bad checksum checks passed for both installers with /usr/bin/python3. |
| Low | The app polled download progress every 300 ms throughout its lifetime. UI snapshot generation could report success after a partial run. | Update the overlay when progress changes. Count all requested renders, require every one to succeed, and remove a duplicate render to the same filename. |

The store also checks that a loaded record ID agrees with its filename. The app-target test dependency lets the suite exercise the real session and review controllers with temporary storage and an in-memory secret store.

## Verification

- Final code tree: `swift test` passed 399 tests in 70 suites, including the application-target lifecycle cases and the simultaneous-download regression. The local parallel-download case passed eight more runs. A separate targeted run of the existing real HTTPS license download hit a network timeout; it passed on the final full run.
- Repository gates passed: `scripts/run-evals.sh`, `scripts/secret-scan.sh` (zero findings for the worktree and index), `scripts/check-localization.sh` (802 keys, no missing translations or format mismatches), `scripts/build-app.sh`, and `codesign --verify --deep --strict dist/InterviewCopilot.app`.

- Initial clean run: one failure in 393 tests. The sticky-language test asserted a scheduling-dependent upper bound before language pinning. The revised test checks that detection occurs and stops once the language is pinned. Twelve consecutive targeted runs passed.
- Offline evaluations: 36 turn cases, zero early or missed turns. Bank top-1 94.9%, zero false matches out of 12. Text filter 214/214. Memory 8/8 related and zero extra out of 2. Materials retrieval 23/24, with 2/8 unrelated queries returning a fragment.
- Additional synthetic audio: foreign speech filtered 16/16, desired speech lost 1/20 (at the 5% limit), terms retained 8/8, noise utterances 0/20. Speaker gate accepted 18/18 owner samples and rejected 89/96 other samples. LocalVQE increased WER from 3.9% to 6.3% on these fixtures. Its experimental default stays off.
- CLI negative cases, flag ordering and local Python checksum fixtures passed. The signed UI smoke run rendered 92 distinct PNGs, and all nine panel resize checks passed.
- Independent standard review covered the behavioral diff. The focused strong pass checked storage, deletion and asynchronous review because of data-loss risk. Review findings on partial bulk deletion, malformed turn segments and empty filter manifests were fixed and approved on re-review. The legacy review-status follow-up was approved separately. Standard and focused strong reviewers also approved the transfer-local model downloader and failure-preserving installation.

## Executor decisions and remaining work

- Used a separate local checkout at the public main commit. No deployment, push or merge. Verification used synthetic data and preinstalled models. Live calls with a real microphone, capture device changes and real provider prompts were not exercised.
- At that point, the remaining audit areas included the rest of the COPILOT-13 open list, individual settings views, browser playback and connection recovery, hardware-specific paths and profiling with larger profile libraries. Synthetic snapshots confirm rendering, not every interaction. Inspect concurrent installer processes sharing a .part path and benchmark startup/main-thread model or document loading before making latency claims.

## Audio lifecycle stage

- Reproduced on the original event path. With the queued mock-end callback extracted unchanged for testing, `swift test --filter lateMockEndCannotEndTheNextMock` failed because the second mock became inactive. The callback now captures its session ID. The first Start received during teardown is retained and runs once the browser and audio cleanup complete.
- InterviewerController and TestCallController mark close synchronously and share its completion across callers. The existing browser token scopes asynchronous server and browser events. Ending an ordinary session during a test call also closes the temporary capture. The standalone test call now restores standby.
- ListeningController serializes device updates and preserves requested stops across rapid restarts. Transcription resumes when the current source is listening. A second red test showed that a failed restoration could leave the temporary source recording. The error path stops that source, and the next start can recover. ScreenCaptureKit drops retired stream samples and drains callbacks already on the sample queue.
- LocalTestCallServer closes idle connections on shutdown and gives in-flight responses a bounded interval to finish. A loopback test verified both the close acknowledgement and idle peer disconnect.

### Verification at `031d94a`

- `swift test` passed 405 tests in 71 suites. `swift test --skip-build --filter AudioSessionLifecycleTests` passed five additional consecutive runs. Coverage includes old browser success/failure and end callbacks, startup failure delivered after End, active/paused/standby restoration, failed source replacement and successful retry.
- A one-off macOS test (`swift test --filter ToneRecoverySmoke` with a dedicated tone-generator app) exercised the real ListeningController and ScreenCaptureKit. The source filter selected only the fixture process. The test detected 520 Hz in fresh 16 kHz mono samples before switching, after leaving the temporary source, and after immediate standby → start. The final run observed 2,880, 7,040 and 960 fresh samples respectively, all in the listening phase. The first smoke attempt also counted samples during startup. The final probe waits for listening and takes a fresh buffer position before checking the tone. No audio was saved.
- `scripts/run-evals.sh` passed all five default suites. `scripts/secret-scan.sh` reported zero findings. `scripts/check-localization.sh` checked 802 keys with zero missing translations or format mismatches. `scripts/build-app.sh` produced the signed release and `codesign --verify --deep --strict dist/InterviewCopilot.app` succeeded.
- Independent standard and focused strong concurrency reviews approved the final changes after re-review. Findings addressed premature transcription during source restoration and cancellation of pending recognition on a phrase/route reset.
- NOT RUN on physical hardware: live microphone capture, input-device changes and an OS-level stop failure. Microphone routing and stop were checked with a synthetic device. The hardware smoke used system audio only. No push or merge.

## Browser playback and connection recovery

- Reproduced on the pages at `7dd55de` in Chrome with a synthetic 520 Hz WAV on an isolated loopback HTTP fixture. When a disconnect crossed the end of buffered playback, Interviewer stayed in speaking and TestCall abandoned the active trial. A dropped response after the server accepted the end also prevented TestCall from finishing normally. Both pages reported a successful close when the close request failed. Chrome could exhaust a partial WAV without dispatching an audio error. TestCall attempted to begin the next phrase during a disconnect between results.
- Both pages retry the end notification for the active playback after connectivity returns and preserve the outcome if the server already accepted it. Chrome can continue a partial media transfer via an HTTP range request. If the audio remains stalled after the state connection recovers, the user can replay the same question or phrase. Interviewer resets recognition for the current question and reuses its WAV. TestCall cancels the incomplete trial before enabling repeat and advances the queue after a successful state poll. Close waits for acknowledgement and allows another attempt after failure.

### Verification at `8480f40`

- `node scripts/check-browser-recovery.mjs dist/InterviewCopilot.app/Contents/Resources` and the same command with `--en` each passed 11 scenarios in Chrome 157.0.8103.79. The unmodified Russian pages passed 3 and failed 8 with the same fixture. Scenarios cover buffered EOF during an outage, a lost response after the server accepts EOF, close and retry, resumable and failed WAV range recovery, and TestCall advancement across a disconnect between phrases. TestCall kept exactly one result per completed trial.
- `swift test` passed 405 tests in 71 suites. `scripts/run-evals.sh` passed all five default suites. `scripts/secret-scan.sh` reported zero findings, `scripts/check-localization.sh` passed, and the English runtime string keys and substitutions passed a direct check for both pages. `scripts/build-app.sh` and `codesign --verify --deep --strict dist/InterviewCopilot.app` passed. Both bundled pages and dictionaries matched their sources byte for byte.
- Independent standard review found an Interviewer race where a playback error was suppressed while a Stop request was pending. The fix handles that error if Stop fails. Focused re-review approved the recovery code and verified the Stop, stall, EOF and queue transitions using the page scripts.
- NOT RUN in this stage: Safari, real provider or microphone traffic, and end-to-end ScreenCaptureKit routing under fault injection. The browser scenarios use the real packaged pages and a synthetic HTTP counterpart. The native app was built and signed locally.

## Native audio recovery in Chrome and Safari

- Verified the browser-recovery code from `095578e` on macOS 15.7.2 with desktop Chrome 157.0.8103.79 and Safari 18.6. A temporary `LiveBrowserAudioSmoke.captureUntilBrowserCloses` test used the shipped page resources, the application controllers and loopback server, ScreenCaptureKit and the installed Whisper small model. TestCall used bundled phrases. Interviewer generated each WAV with macOS speech synthesis from a local fixture provider. The test supplied no spoken microphone answer.
- The fault proxy dropped browser-to-app requests after playback advanced and restored them after buffered EOF. A native sample level written after the cut confirmed capture during the outage. Both pages showed lost connectivity, then accepted the completion exactly once for each of two played fragments. Interviewer reached the answer phase twice. TestCall advanced its queue. Browser close returned HTTP 200 and native listening returned to standby in all four runs.

| Browser | Page | Capture route | Outage during playback | Measured level during outage | WER of two fragments |
| --- | --- | --- | --- | --- | --- |
| Chrome | TestCall | Chrome application | 1.41–4.59 s | -11.7 dBFS | 0%, 0% |
| Chrome | Interviewer | Chrome application | 1.41–7.75 s | -10.9 dBFS | 0%, 0% |
| Safari | TestCall | All system audio | 1.51–4.59 s | -14.0 dBFS | 0%, 0% |
| Safari | Interviewer | All system audio | 1.52–7.75 s | -12.5 dBFS | 0%, 0% |

- Chrome Interviewer initially reached speaking with a valid WAV at the server and no browser playback. A fresh session passed the full scenario. The cause of the initial failure was not established. A preliminary Chrome TestCall session was ended before playback while Parakeet was still loading. The four measured runs used Whisper.
- Safari TestCall exercised its existing system-audio fallback by bypassing the installed Chrome preference in the test. Safari Interviewer used a test-only launcher and the same system-audio route. The production Interviewer launcher still selects Chrome. This stage covered loss of the local control connection across buffered EOF. Partial WAV range recovery remains covered by the earlier browser fixture.
- `swift test --skip-build --filter LiveBrowserAudioSmoke.captureUntilBrowserCloses` passed the four measured runs. Removed the temporary test and launcher hooks. A fresh `swift test` passed 405 tests in 71 suites, and `codesign --verify --deep --strict dist/InterviewCopilot.app` passed on the signed bundle whose pages were used. The measured native runs used the Swift test host with local synthetic inputs.

## Next

The native audio recovery audit is ready for owner acceptance. The next uncovered area is individual settings layouts and interactions. Standard tier.
