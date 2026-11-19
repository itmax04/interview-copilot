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

- The four measured runs are recorded in the [native audio recovery report](/Users/macbook/Downloads/2026-11-18/copilot-14-handoff-interviewer-testcall/outputs/COPILOT-14-live-audio-recovery.txt). Handoff commit `38dc81d` recorded the measured results and the first Chrome Interviewer attempt.

## macOS Settings audit at `b72f4b9`

The starting checkout was clean on `feat/copilot-14-technical-audit`. On macOS 15.7.2 with Xcode 26.3, exercised the nine Settings tabs through the native Workspace window. A local fixture opened the actual Workspace controller and Settings views with the production AppModel and SettingsStore, a dedicated UserDefaults suite, a temporary app-data root and InMemorySecretStore. It skipped ordinary app startup, global shortcut registration and provider checks. The temporary App.swift changes were reversed after building the fixture.

### Layout and findings

- Inspected the nine Russian light-mode Settings snapshots at 1000 × 680 pt (Audio at 1000 × 1240 pt). Opened all nine tabs in the live Workspace at 1180 × 780 pt in Russian dark mode. Reduced the window by dragging its bottom-right corner to 991 × 615 pt as recorded by AppKit's frame autosave. Both sidebars and the page headings remained visible. The small workspace tagline was ellipsized. The Keys and Audio forms scrolled to the Gemini tier and voice/draft controls respectively, and the budget input remained in view.
- **Mixed language in the answer-style sheet.** On a Mac running in English, select Russian in Settings → General, then open Models & answers → Configure. The sheet exposes `Answer style`, `Question type`, `Close` and `Regenerate` in its accessibility tree alongside Russian style options and Save. The parent Settings page is Russian. Recheck the sheet's SwiftUI locale propagation.
- **Budget and Hotkeys accessibility.** Inspect both tabs with no control focused. Budget exposes a merged static row and no editable field until the visible number is clicked. Hotkeys exposes the action names as one static element and the reset button separately, with no per-row edit button or current binding in the tree. Clicking the visible number or Edit button worked. After an invalid unmodified key, Escape ended capture but left the modifier warning in the tree until a valid combination was entered.
- **Question bank copy.** The subtitle mentioned a search model setting. The form exposed a match threshold and explanatory text. Fixed in `39fc279`.

### Control and persistence results

| Tab | Reproduction and observed result |
| --- | --- |
| General | Click Dark and Russian in the segmented controls. The workspace and its sidebar controls reflected both immediately. Both were selected after process restart. |
| Model keys | Enter `http://example.invalid/v1` and see the HTTPS warning. Replace it with `http://localhost:11434/v1`, enter `audit-model`, click Move to the top of the chain and see that button disable. Scroll to the Gemini free-tier switch and turn it off. With dummy input, save the primary Groq slot and add a second slot. The entry was masked and cleared after save. Deleting the primary promoted slot 2. The synthetic values were absent from settings JSON and the in-memory slots were empty on restart. |
| Models & answers | Move Groq down one position and increment the first-token timeout from 4 to 4.5 s. Set length to Short and save. Reopen, choose Detailed and close. Short remained selected. After promoting Custom from the Keys tab, the first three providers were Custom, Cerebras and Groq, including after restart. |
| Audio & recognition | Change Parakeet to Whisper. The Whisper model picker and final-text switch appeared, and the question-bank prompt switch became enabled. Turn that switch on and increase the end-of-question pause from 700 to 750 ms. Scroll to Voice and disable the automatic similarity threshold. The 0.75 slider appeared. The engine, pause, prompt and threshold mode were restored. |
| Question bank | Increase the match slider once, from 74% to 75%. |
| Privacy | Turn personal-data filtering off and increment the retention stepper from 30 to 31 days. |
| Overlay | Decrement opacity from 92% to 91%, select L, and increment width from 420 to 430 pt. |
| Hotkeys | Click Edit beside Answer now. Press an unmodified letter and observe the warning. Press Escape, reopen the recorder, then press Ctrl+Option+J. The stored override was key code 38 and modifiers 6144. |
| Budget | With Russian selected, type `12,50` and press Return. Reopen the tab and replace it with `17,25`, then click Privacy without pressing Return. Back on Budget, the visible input read `17,25`. The stored amount after restart was the number 17.25. |

### Reproduce and verify

- Build from `b72f4b9` in a clean checkout using the [temporary fixture patch](/Users/macbook/Downloads/2026-11-18/copilot-14-docs-changes-copilot-14-2/outputs/COPILOT-14-settings-fixture.patch). First run `scripts/build-app.sh` to produce the resource bundle. Set `patch` to the fixture patch path. Apply with `git apply "$patch"`, run `swift build --product InterviewCopilot`, then reverse with `git apply -R "$patch"`. Set `app="$(mktemp -d)/Interview Copilot Settings Audit.app"`. Run `ditto --noextattr --noqtn dist/InterviewCopilot.app "$app"` and `cp .build/debug/InterviewCopilot "$app/Contents/MacOS/InterviewCopilot"`. Set the copied identifier with `/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.itmax04.interviewcopilot.settingsaudit" "$app/Contents/Info.plist"` and sign the copy with `codesign --force --sign - "$app"`.
- Set `auditRoot=$(mktemp -d)` and `suite="com.itmax04.interviewcopilot.settingsaudit.$(uuidgen)"`. Launch the copied bundle with `open -n -a "$app" --env IC_SETTINGS_AUDIT_SUITE="$suite" --env INTERVIEWCOPILOT_HOME="$auditRoot" --args --settings`. Repeat the table from a fresh suite. Restart the fixture with the same arguments and suite. Read the saved fields using `defaults export "$suite" - | python3 -c 'import json,plistlib,sys; print(json.loads(plistlib.loads(sys.stdin.buffer.read())["settings.v1"]))'`. The measured run checked 21 assertions after restart, including the final values above and absence of both dummy key values.
- PASS: `swift test` on the restored source, 405 tests in 71 suites. The focused run `swift test --filter 'SettingsStoreTests|StorageAndUsageTests|KeychainStoreTests'` passed 27 tests in 4 suites, including Keychain round-trips in dedicated test services. `scripts/check-localization.sh` passed (802 keys, zero missing or mismatched format specifiers). `dist/InterviewCopilot.app/Contents/MacOS/InterviewCopilot --ui-snapshots "$snapshotDir"` rendered 92/92 PNGs. `codesign --verify --deep --strict` passed for the existing release bundle and the fixture copy.
- NOT RUN: standalone Settings window interactions, real microphone or voice enrollment, provider key verification or live style preview, Carbon registration/conflicts, automatic history purge and paid-provider enforcement through the full app lifecycle. The fixture exercised form bindings and saved values. Runtime effects need their own tests.

## Settings localization and accessibility follow-up

The checkout was clean at `0048985` on `feat/copilot-14-technical-audit`. The implementation is `a069ec1`.

- `Sources/InterviewCopilot/Session/AnswerStyleEditor.swift` translates the sheet's labels, help text and preview status using the app language. The preview language selector controls the language of the sample question and answer. The original fixture reproduced English title, question type, Close and Regenerate labels with Russian selected.
- `Sources/InterviewCopilot/Settings/OtherSettingsViews.swift` gives the native numeric budget input a localized field label. The 11 native shortcut buttons expose their action and current binding in the macOS accessibility tree. Temporary modifier validation clears on cancellation. Registration errors are tracked separately. Reset also ends active capture.

### Verification

- Rebuilt with the temporary fixture patch and packaging commands above, then reversed the patch. The fixture used a fresh UserDefaults suite, an isolated data root and an in-memory secret store. Added `-AppleLanguages '(en)'` to the fixture launch and repeated the Settings checks in Russian and English. Restarted with the same suite and `--audit-standalone` to exercise the separate Settings window.
- The sheet exposed labels in the selected app language in both passes. Saving Short, selecting Detailed and pressing Escape left Short selected after reopening the sheet. Both languages exposed a named editable budget field before focus and all 11 action-specific shortcut buttons with their bindings.
- In the fixture, Tab selected the budget input in the standalone window. Entering `12,50` and pressing Return saved the first edit. Entering `17,25` and switching tabs saved the second. The field used a decimal comma in both languages on this Mac. An unmodified key displayed a warning in the shortcut recorder. Escape removed it, cancelling via the button kept the binding, and Reset during capture ended it and restored the default. Ctrl+Option+J was accepted on reassignment.
- A fixture restart restored the selected language, Short style, the numeric budget 17.25 and Answer now bound to Ctrl+Option+J. The four corresponding checks on the isolated `settings.v1` export passed.
- PASS: `swift test` (405 tests in 71 suites), `scripts/run-evals.sh` (five suites), `scripts/secret-scan.sh` (zero findings), `scripts/check-localization.sh` (802 translations, zero missing keys or format mismatches), `scripts/build-app.sh`, `codesign --verify --deep --strict dist/InterviewCopilot.app` and `git diff --check`. The signed app rendered 92/92 PNGs with `INTERVIEWCOPILOT_HOME="$auditRoot" dist/InterviewCopilot.app/Contents/MacOS/InterviewCopilot --ui-snapshots "$snapshotDir"`. Inspected the Budget, Hotkeys and style editor renders.
- Independent standard review and focused re-review of the native button styling and Reset placement passed with no actionable findings.
- The fixture exercised activation through the macOS accessibility tree. Global Carbon registration and conflicts, live generation in the style editor, and the Session Wizard sheet interaction remain unverified.

### Keyboard and VoiceOver recheck at `3c55898`

- Reused the signed Settings fixture on macOS 15.7.2 with a fresh UserDefaults suite, isolated data root and in-memory secret store. Ran the keyboard check in the English Workspace Settings window. The fixture passed `codesign --verify --deep --strict "$app"`. The app source matched `a069ec1`.
- Started VoiceOver and confirmed with AppKit that VoiceOver and macOS keyboard navigation were active. Tab reached all 11 Change buttons in row order, from Answer now to Next answer. Space started recording on the first and last buttons, and Escape restored the previous value and focus on each. Shift+Tab from Next answer moved focus back to Previous answer. The fixture data contained no saved override after cancellation.
- VoiceOver speech and VoiceOver-specific activation were unverified in this automated run. The UI driver could send Tab and Space to the fixture, but VO-Space did not activate the focused button and VO-Shift-C did not place the last spoken phrase on the clipboard. The macOS accessibility tree showed the button label and current binding at keyboard focus. Turned VoiceOver off and confirmed that AppKit reported both VoiceOver and keyboard navigation back in their original off state.

### Physical keyboard VoiceOver recheck at `68baf29`

- Created a detached worktree at `68baf29`, applied the existing Settings fixture patch there and ran `swift build --product InterviewCopilot` successfully. Copied the existing release bundle, replaced its executable with that debug fixture, changed its bundle identifier and ad-hoc signed it. `codesign --verify --deep --strict` passed. Launched it with a dedicated UserDefaults suite and isolated data root; the fixture uses an in-memory secret store.
- PASS (owner-reported, 2026-11-19). In the isolated Settings fixture, VoiceOver announced the action and current shortcut for the focused Change button in Hotkeys. Pressing VO+Space on the physical keyboard started recording a new shortcut. The report gave an overall result without specifying the tested row or exact spoken wording.

### Question bank subtitle follow-up

- Reproduced the stale search-model reference in the isolated English Workspace Settings fixture at `68baf29`. Implementation `39fc279` updated the subtitle in `Sources/InterviewCopilot/SettingsWindow.swift` and its English translation in `Resources/en.lproj/Localizable.strings`. Workspace and standalone Settings use the same `SettingsView`.
- PASS: rebuilt and signed the isolated fixture, then verified both subtitles visually and in the Workspace accessibility tree. Incrementing the slider changed 74% to 75%, and switching from English to Russian kept the selected tab and the 75% value. Standalone UI interaction was not run in this follow-up.
- PASS: `swift test` (405 tests in 71 suites), `scripts/run-evals.sh` (five suites), `scripts/secret-scan.sh` (zero findings), `scripts/check-localization.sh` (802 keys, zero missing keys or format mismatches), `scripts/build-app.sh`, `codesign --verify --deep --strict dist/InterviewCopilot.app` and `git diff --check`. One independent standard review approved the shared view and both strings with no findings.

## Next

Owner acceptance is the next checkpoint. The earlier audit's unverified runtime checks remain open.
