# COPILOT-14 technical audit

## Identity and scope

Branch `feat/copilot-14-technical-audit`, based on `bc64695` (public main and COPILOT-13). Scope and baseline are recorded in `f6bcdba`. First audit implementation: `bad6051`. The audio lifecycle stage started from the clean handoff commit `180e72b`. Its verified implementation is `031d94a`. The previous task's handoff identifies the components it reviewed and the areas it left open. This pass examined the app's history and profile flows, model installation, offline evaluation entry points, progress updates, and synthetic UI checks. The follow-up traced rapid End → Start across the live session, browser controller and audio device.

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
- Remaining audit coverage includes the rest of the COPILOT-13 open list, the layout and interaction of individual settings views, browser-page playback/connection recovery, hardware-specific paths and profiling with larger profile libraries. Synthetic snapshots confirm rendering, not every interaction. Inspect concurrent installer processes sharing a .part path and benchmark startup/main-thread model or document loading before making latency claims.

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

## Next

Exercise browser playback and connection recovery for the bundled Interviewer and TestCall pages using synthetic audio. Check what the page shows after a disconnect during playback and whether it resumes or closes cleanly. Update this handoff with reproduced failures and their verification. Standard tier.
