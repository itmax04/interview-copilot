# COPILOT-01 handoff

Status: **ready for acceptance (H-5)** · Updated: 2026-10-07 · Branch: `feat/copilot-01` · Commit: see `git log -1`
Goal and scope: [intent.md](intent.md), requirements: [spec.md](spec.md), steps: [plan.md](plan.md).

## Done
- SDLC documents created (intent, spec, plan, ADR-0001, evals/README, CLAUDE.md, README, executor-prompt). No code was written.

- 2026-10-06: the owner accepted the v1 set (statuses → accepted, recorded in intent.md).

- 2026-10-06, P-00: environment survey and baseline (below). Conclusion: Xcode is needed → point H-0.

### P-00 baseline
- Git before the step: branch `feat/copilot-01`, clean working tree, HEAD `a0a566f`, same as `origin/feat/copilot-01`.
  Branches: `main`, `feat/copilot-01`. No discrepancies with the handoff.
- `swift --version`: Apple Swift 6.0 (swiftlang-6.0.0.9.10), target arm64-apple-macosx15.0.
- `xcode-select -p`: `/Library/Developer/CommandLineTools`; Xcode is not installed in `/Applications`.
- Environment: macOS 15.7.2 (24G325), Apple M1, 8 GB; 46 GB free on the data volume. Homebrew, gh, cmake, python3 present.
- Minimal package (scratchpad), `swift test` on the CLT:
  - XCTest: FAIL — `error: no such module 'XCTest'`;
  - Swift Testing: FAIL — `error: no such module 'Testing'`. It runs only with manual flags
    `-F …/CommandLineTools/Library/Developer/Frameworks` + rpath, after which it fails with
    `XCTest not available … unable to lookup item 'PlatformPath'`. That is a workaround, not used per Q10.
- XCFrameworks (GitHub Releases, checked with `gh api` 2026-10-06):
  - whisper.cpp: `whisper-b5454-xcframework.zip` (tag `b5454`, 65 816 082 bytes,
    sha256 `e57f8c48933000acabc13bb913fbe82805d483a2deff692cc6738836bd92393b`). The latest stable tag `v1.9.5` has no assets;
    XCFrameworks are published in build tags `bNNNN`.
  - llama.cpp: `llama-b11446-xcframework.zip` (tag `b11446`, 61 978 829 bytes,
    sha256 `da7edb84bd4990680cd6bb475468cc3f78b28cc0062fabebeae40218d228966b`).
  - Both work as a `binaryTarget`; the SwiftPM checksum will be computed with `swift package compute-checksum` at P-04/P-06.
- Decision: Xcode is needed (tests do not run on the CLT) → H-0.

- 2026-10-06, H-0 passed: `xcode-select -p` → `/Applications/Xcode.app/Contents/Developer`, Xcode 26.3 (17C529),
  Swift 6.2.4. Minimal package: `swift test` — XCTest 1/1 and Swift Testing 1/1 PASS.
- 2026-10-06, P-01 (code): `Package.swift` (targets InterviewCopilot, CopilotCore, copilot-eval, CopilotCoreTests; Yams 6.2.2),
  the R-15 menu (model `CopilotCore/Menu/MenuLayout.swift` + `MenuBarController`), an empty settings window with the R-18 tabs,
  a parrot icon (drawn in code: a template for the menu bar, a color one for the .app), `Resources/Info.plist`,
  `scripts/build-app.sh`, `scripts/secret-scan.sh`, a `copilot-eval` stub.

- 2026-10-06, H-1 passed: the signing certificate was created (its Keychain name is "InterviewCopilot", without " Dev";
  `security find-identity -p codesigning` → 1 identity, CSSMERR_TP_NOT_TRUSTED — normal for a self-signed one, trust left untouched).
  `scripts/build-app.sh` builds and signs `dist/InterviewCopilot.app`, the app launches.

- 2026-10-06, P-02 (code): `AppSettings`/`SettingsStore` (JSON in UserDefaults, defaults from the spec, range clamping),
  `KeychainStore` (generic password, service `com.itmax04.interviewcopilot`), `ProviderEndpoints` + `KeyVerifier`
  ("Check" = a request for the model list), `HTTPTransport` with a mock for tests, `AppModel`, settings tabs
  Keys/Models/Audio/Bank/Privacy/Panel/Hotkeys/Budget. Before the Anthropic code the `claude-api` skill was read (curl/examples.md);
  the Gemini and DeepSeek endpoints were checked against ai.google.dev/api/models and api-docs.deepseek.com/api/list-models.

- 2026-10-06, H-2 passed: the owner saved the Gemini key and pressed "Check" → "OK · models: 62" (owner's screenshot).
  `security find-generic-password -s com.itmax04.interviewcopilot -a gemini` (without `-w`) — the entry exists; the value was not read.
- 2026-10-06, P-03 (code): `AudioSourceResolver` (Auto: Zoom → Chrome → Telegram, app helpers by bundle ID prefix),
  `SystemAudioCapture` (SCStream audio only, 16 kHz mono, `excludesCurrentProcessAudio`, source switching via
  `updateContentFilter`), `PCMConverter`, `AudioRingBuffer` (≤ 30 s), `EnergyVAD`, `MicActivityDetector` (AVAudioEngine),
  `Permissions`, `Log` (os_log), `ListeningController`, a permissions window with a level indicator, a "Listening" submenu listing
  running apps, pause from the menu.

- 2026-10-06, H-3 passed: the owner granted "Screen & System Audio Recording" and "Microphone". Owner screenshots:
  the permissions window with two green checkmarks, "Listening: Chrome"; the menu with a green dot "Listening — Chrome"
  (crop — `evidence/menu-2026-10-06-owner.png`, for AC-11). A YouTube video in Chrome: the log shows `capture stats … rate=16000 ch=1`
  (~16 000 samples/s) and `level_db` −31…−14 dB during playback, −120 dB in silence.
  AC-13 (the view without permission): the log shows `no screen capture permission`, the process did not crash, the permissions window opened by itself;
  no visual confirmation from the owner before granting permissions — recheck at H-5.
- Known issue (P-03 → P-05): without headphones the microphone hears the speakers, and `owner_speaking=true` while the other person speaks.
  This would block auto-answer (R-05, S-07). Plan: enable AVAudioEngine voice processing (`setVoiceProcessingEnabled`,
  echo cancellation) and/or treat the owner as speaking only when the microphone is louder than the system-audio echo. Done at P-05.

- 2026-10-06, P-04: whisper.cpp `b5454` as a `binaryTarget` (URL + checksum), `scripts/fetch-models.sh` + `models.sha256`
  (turbo q5_0 and small q5_1, SHA256 from Hugging Face LFS), `scripts/make-audio-fixtures.sh` → `evals/audio/*.wav`
  (Lesya, Milena, Samantha — all voices present), `WhisperEngine`, `StreamingTranscriber` (VAD segmentation, partial
  and final text, language), `AppPaths`, `copilot-eval stt` / `stt-stream`, wiring into the app.
  The turbo/small decision — small (measurement table in ADR-0001 "Final decisions").

- 2026-10-06, P-05: `TurnDetector` (R-05: T, ≥ 3 words, the owner is not speaking; waiting for a continuation after a comma/function
  word; ⌃⌥↩ waits for the final text; speaker echo is ignored), the `turn` eval (`evals/turn/cases.jsonl`, 34 cases,
  `TurnEval`, `copilot-eval turn`, `scripts/run-evals.sh`), `HotkeyCenter` (Carbon, ⌃⌥↩/S/H/P/C, remapping in the
  Hotkeys tab, a warning for a taken shortcut), the panel (non-activating `NSPanel`, `.hudWindow`, 16 radius, width/
  opacity/font from settings, position remembered; header, Interviewer, states idle/listening/paused/thinking/
  error/no-permission/downloading, footer), `TurnController`, the `turn_end` metric in the log.
  uk/ru language: the comparison repeats as the utterance grows, the longest decides (live measurement: wrong at 2 s).
- The P-03 known issue (echo) is closed by logic: the start of "owner speech" during the other person's speech and 150 ms after it is echo (R-05, S-07).

- 2026-10-06, P-06: `profile.example/` (a fictional candidate: profile.yaml, resume.md, job.md, stories.md, questions.yaml —
  20 cards, 6 phrasings per card, 7 with STAR), `QuestionBankParser` (Yams, validation, error lines), `ProfileStore`
  (copying the example on first launch, R-21), `FileWatcher`, `BankIndex`/`BankIndexBuilder` (embedding cache on disk),
  the `CopilotEmbeddings` target (`LlamaEmbedder`, llama.cpp `b11446` XCFramework), the `bank` eval (+ a holdout set),
  `BankController` in the app (menu: card count, parse error, opening the bank and the profile folder), search per turn
  with the `bank_match` metric. Model and threshold choice — ADR-0001 "Final decisions", item 6.

- 2026-10-06, P-07: before the Anthropic code the `claude-api` skill was read (curl/examples.md, model-migration.md § Sonnet 5.5,
  § refusal, § fallbacks "default"); Gemini — ai.google.dev (generate-content, thinking), DeepSeek — api-docs (chat completion).
  Code: `LLMProvider`, `SSEClient`/`SSEParser`, `GeminiProvider`, `DeepSeekProvider`, `AnthropicProvider`, `MockProvider`,
  `ProviderChain` (R-09 triggers, first-token timeout, cancellation, text restart), `ChainFactory` (budget, strong model),
  `PromptBuilder` (R-11), `PIIFilter` (R-12), `AnswerRouter` (R-08), a live check `--smoke-llm`, model ID check at launch.
  Stream fixtures — `Tests/CopilotCoreTests/Fixtures/`.

- 2026-10-07, P-08…P-10 (one commit: the steps intertwined because of a shared Keychain problem, see below):
  - P-08: `AnswerController` (bank → mode → streamed generation, "—" does not change the panel, cancellation on a new turn,
    "Models unavailable: …" + top 3, the strong model manually ⌃⌥C / "↑ Claude"), `AnswerCardView` (source, Markdown,
    S/T/A/R chips, Copy), `NoMatchView`, the Mode / Models (strong model) / Language submenus wired to settings,
    the `card_shown` and `first_token` metrics measured from the end of speech and from the end of the turn.
  - P-09: `ScreenshotService` (the display under the cursor, with the cursor, without the assistant's windows, ≤ 1600 px, JPEG in memory),
    ⌃⌥S and a menu item, the strong model or Gemini without an Anthropic key, the fixture `evals/fixtures/two-sum.png`
    (`scripts/make-screenshot-fixture.swift`), `--smoke-screenshot`.
  - P-10: `SessionStore` (a JSON file per session, delete one/all, retention), `SessionController`, the "Session history…" window,
    `UsageMeter` + `Resources/pricing.json` (day/month, DeepSeek peak hours, Gemini Free = $0, monthly limit → paid
    providers switched off), the menu status line "Today: $… · Gemini: N req / limit".
  - Settings migration: threshold 0.85 → 0.74, the Gemini fallback model → `gemini-flash-lite-latest`.

- 2026-10-07, P-11: the first-run wizard (`OnboardingWindow`: permissions → Gemini key → models with progress and
  SHA256 check, `ModelDownloader`, `models.sha256` in the bundle; progress also in the panel — the downloading state), `scripts/metrics.py`
  (medians and p90 of AC-01…AC-03 from `log show`), `scripts/footprint-monitor.sh` (AC-05), metrics logged at the notice level,
  `evals/live-script.md` (15 questions + AC-09 checks during the call).

- 2026-10-07, H-4 attempt 1 (uk/ru only, by the owner's decision): `scripts/metrics.py --start "2026-10-07 10:00:00"`:
  AC-01 median 511 ms (n=20) PASS; AC-03 median 4850 ms (n=10) FAIL; AC-02 — 0 cards. Causes from the logs:
  (1) the other person's audio from Meet was very quiet — speech −47…−53 dBFS over a −85…−90 background (YouTube the day before −14 dB); the VAD with a
  −50 dBFS threshold cut speech into 0.6–1 s fragments, whisper produced nonsense on them, no bank matches (0.45–0.59);
  (2) `gemini-3.8-flash` did not answer within 4 s on every turn → fallback to Flash-Lite → first words after 4.8 s.
  Fixes: the other person's VAD at −62 dBFS (the main threshold — noise + 10 dB), a 350 ms hold; quiet audio is raised
  to a 0.5 peak (at most ×40) before whisper, silence threshold −68 dBFS; `ProviderHealth` — a model that did not answer in time
  or returned 429/5xx goes to the end of the queue for 5 minutes. Check: a stream at −30 dB — 4/4 phrases and languages correct, median 602 ms.

- 2026-10-07, H-4 attempt 2: normal volume (−13 dB), but low accuracy; Chrome Live Caption on the same audio also
  erred — Meet audio from a phone is heavily compressed. Switched to whisper medium + "conversation language" (ADR-0001, item 5 revision).
  Hints: first words 0.9–1.1 s after the end of the turn (ProviderHealth worked).

- 2026-10-07, H-4 attempt 3 (medium, ru): `scripts/metrics.py --start "2026-10-07 11:00:00"` — AC-01 median 684 ms (n=24)
  PASS; AC-02 84 ms (n=4) PASS; AC-03 978 ms (n=11) PASS; `footprint` 1166 MB (peak 1172). The about-me card was found
  from an inaccurate text. Owner: "already better, but not accurate". The owner's choice: option 1 — keep medium + improvements.
- 2026-10-07, P-12 accuracy improvements (measured on fixtures re-encoded as AAC 8 kHz 12 kbit/s and with noise at SNR 8 dB):
  - prompting recognition from the bank (initial prompt) — a mixed result (some phrases more accurate, others get translated
    into another language or repeated) → the Audio option "Prompt recognition with phrasings from the bank", off by default;
  - previous lines in the prompt — whisper started repeating them → removed;
  - a separate small model for language detection — memory ~1.4 GB without embeddings (> AC-05) → rejected;
  - choosing the language by comparing ru/uk/en probabilities and a "confident detector" on the first 1.2 s — more language errors → reverted;
  - result: detector + uk/ru comparison + conversation language after two confident lines. A single-language session: ru 4/4,
    median 846 ms; uk 4/4, median 1140 ms. If the language is known — choose it in the Language menu (more accurate and faster).

- 2026-10-07, P-13: an independent review (`/code-review high` on the branch against the spec and CLAUDE.md) — 10 findings (1 P0, 6 P1, 3 P2),
  all fixed with regression tests (commit `cc1c06e`; the list — report.md "Independent review"). P0: `.gitignore`
  with `models/` hid `Sources/CopilotCore/Models/` — a clean clone did not build (AC-14 FAIL on `d046738`), fixed.
  AC-05: `scripts/footprint-monitor.sh 10` — maximum 1119 MB. AC-14: a clean clone of `cc1c06e` — build/test/package/sign/scan PASS.
  Documents: report.md (AC-01…AC-14), test-plan.md (for the next executor and acceptance), README, ADR-0001 (final decisions).

- 2026-10-07, at the owner's request (after P-13): the audio source "Microphone (practice, no call)" — the owner asks
  questions by voice into the Mac microphone, without Meet; the app transcribes and answers. `MicrophoneCapture` (AVAudioEngine → 16 kHz,
  memory only); in this mode owner-speech detection (R-02) is off and the Screen Recording permission is not required.
  Checked: fixture audio through the speakers → microphone → `transcript_final`, `card_shown` (about-me, conflict, 74–102 ms after the turn),
  `first_token` 0.83 s. 144 tests PASS.

## Next step
H-5: owner acceptance per report.md and test-plan.md §7. Open: the AC-10 decision (accuracy on compressed audio),
NOT RUN — DeepSeek/Anthropic live, English questions on a call, AC-13 visually, AC-09 key presses while Chrome is active.

## Checks
| Step | Command | Commit | Result |
|---|---|---|---|
| P-00 | `swift test` (minimal package, CLT) | — | FAIL: no XCTest/Testing modules without Xcode → H-0 |
| P-00 | `swift build` / `scripts/secret-scan.sh` | — | NOT RUN (no code or script yet) |
| H-0 | `swift test` (minimal package, Xcode 26.3) | — | PASS: XCTest 1/1, Swift Testing 1/1 |
| P-01 | `swift build` | P-01 | PASS |
| P-01 | `swift test` | P-01 | PASS: 4 tests (MenuLayoutTests) |
| P-01 | `scripts/secret-scan.sh` (tree + index + history) | P-01 | PASS: "0 findings"; self-test on fake keys/email/phone — 5 of 5 found |
| P-01 | `scripts/build-app.sh` | P-01 | FAIL as expected: no certificate → a clear error; rerun after H-1 |
| H-1 | `scripts/build-app.sh` | P-01 fix | PASS: `dist/InterviewCopilot.app`, `codesign -dvv` → `Identifier=com.itmax04.interviewcopilot`, `Authority=InterviewCopilot`; `codesign --verify` → valid on disk, satisfies DR |
| H-1 | `open dist/InterviewCopilot.app` | P-01 fix | PASS: the process runs (pgrep); icon visibility — owner confirmation |
| P-02 | `swift build` | P-02 | PASS |
| P-02 | `swift test` | P-02 | PASS: 22 tests in 4 suites (MenuLayout, SettingsStore, KeychainStore — the real Keychain, a test service, KeyVerifier — mock) |
| P-02 | `scripts/build-app.sh` | P-02 | PASS, `Authority=InterviewCopilot` |
| P-02 | `scripts/secret-scan.sh` | P-02 | PASS: "0 findings" |
| P-03 | `swift test` | P-03 | PASS: 36 tests in 7 suites (+AudioSourceResolver, AudioRingBuffer, EnergyVAD) |
| P-03 | `scripts/build-app.sh` | P-03 | PASS |
| P-03 | Launch without permission | P-03 | PASS (log): `no screen capture permission`, the process is alive, the permissions window opened; visually — not confirmed by the owner (AC-13 → H-5) |
| H-3 | Chrome audio capture (YouTube) | P-03 | PASS: `level_db` −31…−14 dB during playback, ~16 000 samples/s, 16 kHz mono |
| H-3 | Microphone (VAD) | P-03 | PASS partially: the owner's speech is detected; without headphones false triggers from the speakers → P-05 |
| P-04 | `scripts/fetch-models.sh` | P-04 | PASS: both files downloaded, "SHA256 matches" |
| P-04 | `copilot-eval stt` (turbo/small measurements) | P-04 | see ADR-0001: small 0.16–0.27 s per phrase, turbo 2.1–4.7 s |
| P-04 | `copilot-eval stt-stream` small, 6 phrases | P-04 | PASS: median end of phrase → text 524 ms, max 583 ms, languages 6/6 |
| P-04 | The app, all system audio + `afplay` of fixtures | P-04 | PASS: `transcript_final` 503–759 ms (median ~590), languages 6/6; `footprint` 453 MB |
| P-04 | `swift test` | P-04 | PASS: 49 tests in 9 suites (+StreamingTranscriber with a fake recognizer, WhisperEngine on the real model) |
| P-05 | `scripts/run-evals.sh turn` | P-05 | PASS: 34 cases, premature 0%, missed 0%, latency = T (700 ms) |
| P-05 | `swift test` | P-05 | PASS: 61 tests in 10 suites (+TurnDetector) |
| P-05 | `copilot-eval stt-stream` (7 phrases, clean audio) | P-05 | PASS: languages 7/7, median 518 ms, max 630 ms |
| P-05 | The app: "All system audio" + `afplay` | P-05 | `turn_end` 700–750 ms after the end of speech; final 375–707 ms. The measurement was polluted by background audio of another app (WebKit) — split phrases and 1 language error; in normal operation capture is per app |
| P-05 | Hotkeys, focus (AC-09) | P-05 | Registration without errors (log). Key presses with Chrome active — NOT RUN: the executor process has no rights for synthetic key presses; owner check at H-4 |
| P-06 | `scripts/fetch-models.sh` (embeddings) | P-06 | PASS: embeddinggemma-2, embeddinggemma-300M, bge-m3 — SHA256 matches |
| P-06 | `scripts/run-evals.sh` (bank + turn) | P-06 | PASS: bank bge-m3 top-1 94.9%, false 0%, top-3 100%; turn 0% / 0% |
| P-06 | `copilot-eval bank evals/bank/holdout.jsonl` | P-06 | PASS: top-1 91.7%, false 0% |
| P-06 | `swift test` | P-06 | PASS: 74 tests in 12 suites (+QuestionBank, BankMatcher with a stub embedder, ProfileStore, FileWatcher) |
| P-07 | `swift test` | P-07 | PASS: 112 tests in 16 suites (+SSEClient/providers on fixtures, ProviderChain, AnswerRouter, PromptBuilder, PIIFilter) |
| P-07 | `InterviewCopilot --smoke-llm` (Gemini, live key) | P-07 | Model list: 62, `gemini-3.8-flash` present. Stream: the request format is accepted; `gemini-3.8-flash` — 503 "high demand" / 429 / first token 13–17 s; `gemini-flash-latest` — 2.1 s and 13 s; `gemini-flash-lite-latest` — 0.7 s; the chain 3.8 → flash-latest fell back on 503 |
| P-07 | DeepSeek, Anthropic (live calls) | P-07 | NOT RUN — no keys; covered by fixture tests and mock providers (AC-07) |
| P-08 | The app, mode "Question bank only", 5 phrases through the speakers | P-08 | PASS: 5/5 cards found; `card_shown` 0.09–0.13 s after the end of the turn (0.81–0.85 s after the end of speech; the first — 4.4 s while a Keychain prompt was pending, fixed) |
| P-08 | The app, "Bank + hint", an out-of-bank question | P-08 | PASS: "Not in the bank" by the bank (0.615), Gemini 3.8 → 429 → Flash-Lite, first token 1.73 s after the end of the turn (2.45 s after the end of speech) |
| P-09 | `--smoke-screenshot evals/fixtures/two-sum.png` | P-09 | PASS: JPEG 1600×1000 (144 KB), 3.8 → 429 → Flash-Lite, first token 1.9 s, an answer with a code block and O(...) |
| P-09 | ⌃⌥S in the app (a live screenshot) | P-09 | NOT RUN by the executor (no synthetic key presses) — owner check at H-4 |
| P-10 | `swift test` | P-10 | PASS: 127 tests in 19 suites (+SessionStore: save, delete, retention — AC-12; UsageMeter: prices, DeepSeek peak, limit; Screenshot) |
| P-10 | The app: sessions and spending | P-10 | PASS: `sessions/2026-10-07T00-08-11.json` with a turn and latency, `usage.json` — a Gemini request, a 429 mark |
| P-11 | `swift test` | P-11 | PASS: 130 tests in 20 suites (+ModelDownloader: list, SHA256, a live download of a small file) |
| P-11 | `scripts/run-evals.sh` | P-11 | PASS: turn 36 cases 0%/0%; bank 94.9% / 0% |
| P-11 | Focus when showing the panel (AC-09, partially) | P-11 | PASS: `lsappinfo front` before and after launching with the panel shown — "Claude", focus not taken. Hotkeys with Chrome — at H-4 |
| P-11 | Memory (AC-05, preliminary) | P-11 | `footprint` 453–542 MB idle with all models; the 10-minute measurement — at H-4 |
| H-4 (1) | `scripts/metrics.py` (Meet call, uk/ru) | P-11 | AC-01 PASS 511 ms; AC-02 NOT RUN (0 cards); AC-03 FAIL 4850 ms — fixed, rerun |
| P-12 | `swift test` | P-12 | PASS: 134 tests (+quiet speech −30 dB, normalization, ProviderHealth) |
| P-12 | `copilot-eval stt-stream … --gain 0.03` | P-12 | PASS: 4/4 uk/ru phrases at −30 dB, median 602 ms |
| H-4 (2) | Call: first words of a hint | d2f0b45 | 1.06 and 0.91 s after the end of the turn (was 4.8 s) |
| P-12 | whisper small vs medium on compressed audio (AAC 8 kHz 12 kbit/s) | P-12 | small 4/4 with errors; medium 4/4 correct, 0.44–0.68 s per phrase |
| P-12 | `copilot-eval stt-stream` medium, compressed audio | P-12 | 8/8 correct; 0.84–1.06 s (median ~0.9 s) with a free GPU |
| P-12 | App `footprint` with medium + bge-m3 (idle) | P-12 | 1121 MB |
| H-4 (3) | `scripts/metrics.py` (Meet call, ru, medium) | e4f923c | AC-01 684 ms PASS; AC-02 84 ms PASS; AC-03 978 ms PASS; memory 1166 MB |
| P-12 | `copilot-eval stt-stream` medium, compressed audio, ru / uk session | P-12 | ru 4/4, median 846 ms; uk 4/4, median 1140 ms |
| P-12 | `swift test` | P-12 | PASS: 137 tests in 21 suites |
| P-13 | `/code-review high` | cc1c06e | 10 findings — all fixed |
| P-13 | `swift test` | cc1c06e | PASS: 143 tests in 21 suites |
| P-13 | `scripts/run-evals.sh` | cc1c06e | turn 36 — 0%/0%; bank 94.9% / 0% |
| P-13 | `scripts/footprint-monitor.sh 10` (AC-05) | cc1c06e | 1119 MB maximum over 10 minutes — PASS |
| P-13 | Clean clone (AC-14) | d046738 | FAIL: ModelDownloader.swift is not in Git |
| P-13 | Clean clone (AC-14) | cc1c06e | PASS: build, 143 tests, build-app (Authority=InterviewCopilot), secret-scan 0 |
| P-06 | The app: profile, bank, S-10 | P-06 | PASS: the profile was copied, index of 20 cards; an error in questions.yaml → `parse error line=275`, the previous bank keeps working; a new card → 21, only the new phrasing recomputed (137 ms); `footprint` 542 MB |
| P-01 | Launch, the icon and menu are visible (screenshot) | P-01 | Launching the debug binary: the process starts without errors. Screenshot NOT RUN: the executor process has no Screen Recording permission (`screencapture` gives only the wallpaper), TCC left untouched. The menu screenshot — at H-3/P-11 |

## Executor decisions
_(the executor adds: date, step, decision, reason, reference to R-/AC-)_

- 2026-10-06, P-00: tests are written with XCTest and/or Swift Testing after Xcode is installed; CLT workaround flags are not used (Q10, AC-14).
- 2026-10-06, P-01: the menu structure lives in `CopilotCore` (`MenuLayout`) and is covered by tests — the testable part of AC-11; AppKit only draws. Item icons are SF Symbols close to the picture (HIG).
- 2026-10-06, P-01: the parrot icon is drawn in code (`ParrotIcon`), the .icns is built with `iconutil` in build-app.sh — no binary assets in Git (R-15).
- 2026-10-06, P-01: when paused, the first menu line shows "Paused — <app>" and the item "Resume listening" (R-15 only mentions the dot color; this is clearer, HIG).
- 2026-10-06, P-01: `secret-scan.sh` does not check emails/phones in `profile.example/` and `evals/` (synthetic, AC-06); the addresses `example.*`, `users.noreply.github.com`, `anthropic.com` are allowed.
- 2026-10-06, H-1: `build-app.sh` accepts the certificate "InterviewCopilot Dev" (ADR-0001 item 3) or "InterviewCopilot" (the actual name after H-1); override with `CODESIGN_IDENTITY`. Recreating the certificate was not requested: the name does not affect TCC behavior.
- 2026-10-06, H-1: the repository lives on the Desktop in iCloud Drive; File Provider adds `com.apple.FinderInfo`, and `codesign` fails. The bundle is built and signed in a temporary folder outside iCloud, then copied with `ditto --noextattr` into `dist/`; the final check is `codesign --verify` without `--strict` (AC-14).
- 2026-10-06, P-02: settings window texts are in Russian (the spec names buttons "Проверить", "Удалить", "ключ недействителен"), tab and menu names in English, as in R-15/R-18 and the picture.
- 2026-10-06, P-02: Gemini authenticates with the `x-goog-api-key` header, not the `?key=` parameter from the documentation example — R-23 requires keys only in headers.
- 2026-10-06, P-02: "Check" on a 429 shows "rate limit", not "invalid key"; 400/401/403 — "invalid key" (R-09). The provider's error text is cleaned of the key value.
- 2026-10-06, P-02: Keychain — the classic (file-based) keychain, not the data-protection keychain: the latter needs a keychain-access-groups entitlement and a provisioning profile that local signing does not have.
- 2026-10-06, H-2: an agent app has no main menu, so ⌘V did not paste the key into the field. An invisible main menu with Edit items was added (`MainMenu.swift`).
- 2026-10-06, P-02: the Hotkeys tab only shows the shortcuts for now; registration, conflict checks and remapping — P-05 (R-17).
- 2026-10-06, P-03: Auto considers both Telegram clients (`ru.keepcoder.Telegram`, `org.telegram.desktop`); an app's audio is taken together with its helpers (`com.google.Chrome.helper…`), otherwise Chrome tabs are not heard (R-01).
- 2026-10-06, P-03: the VAD noise level is the minimum energy over 3 s, not exponential smoothing: otherwise a constant background was treated as speech from the first second (test `steadyNoiseIsNotSpeech`) (R-02).
- 2026-10-06, P-03: listening starts by itself at launch if the permission is granted and a source is found; without permission the permissions window opens immediately, the system prompt — only via the "Request" button (AC-13, S-09).
- 2026-10-06, P-03: without permission the "Listening" item has no submenu — a click opens the permissions window (R-15, AC-13).
- 2026-10-06, P-03: in zsh `log` is a builtin; for app logs use `/usr/bin/log show --predicate 'subsystem == "com.itmax04.interviewcopilot"' --info`.
- 2026-10-06, P-04: the default whisper model is small q5_1 (AC-01, AC-05), not turbo; details and numbers — ADR-0001 (R-03).
- 2026-10-06, P-04: the uk/ru language is chosen by comparing recognition confidence in both languages — small's detector errs on Ukrainian (S-11, AC-10).
- 2026-10-06, P-04: silence (< −55 dBFS) is not fed to the model, the output length is capped, repeats are collapsed — whisper produced "you", "Повтори!" and looping text on silence (R-03).
- 2026-10-06, P-04: the first model run in a new bundle takes ~18 s (Metal shader compilation), then ~0.5 s. The first-run wizard (P-11) should warm up the model after the download.
- 2026-10-06, P-04: a pipeline self-check without the owner — the source "All system audio" is written into the app settings (`defaults write com.itmax04.interviewcopilot settings.v1`), fixtures are played with `afplay`; after the check the setting is restored (Auto).
- 2026-10-06, P-05: after a phrase cut at a comma or a function word, wait T + 1.3 s — otherwise "Расскажите о проекте, который…" goes out as a question (R-05, the `turn` eval).
- 2026-10-06, P-05: ⌃⌥↩ during speech or before the final text arrives — the turn fires as soon as the text arrives (R-05: "using the last utterance").
- 2026-10-06, P-05: AVAudioEngine voice processing (echo cancellation) is not enabled — it ducks the audio of other apps, including the call; instead — an echo rule in `TurnDetector` (R-02, S-07).
- 2026-10-06, P-05: the panel is shown at launch (`orderFrontRegardless`, without activating the app); the menu item changes to "Hide panel" when the panel is visible (R-15, R-16).
- 2026-10-06, P-05: the uk/ru language — the comparison on the longest audio of the utterance decides; with a difference < 0.02 — the previous utterance's language; refinement is interrupted at the end of the phrase (AC-01, AC-10).
- 2026-10-06, P-06: the embedding model is bge-m3 (candidate 2), threshold 0.74 by eval; multilingual-e5-small exists only in unofficial conversions, embeddinggemma-2 is not supported by the release llama.cpp (ADR-0001, AC-04, R-07).
- 2026-10-06, P-06: phrasings were added to the example bank (6 per card) to pass AC-04; a holdout set was added to check overfitting (AC-04).
- 2026-10-06, P-06: the example profile is copied by reading/writing, not `copyItem`: cloning a file from the .app in iCloud Drive hung the main thread (R-21).
- 2026-10-06, P-06: "Edit resume & stories…" and "Open profile folder" open the profile folder in Finder, "Question bank…" opens questions.yaml in the default editor (R-15).
- 2026-10-06, P-07: Anthropic — `thinking: between_tools` + `effort: low` for hints and the "strong model manually" (minimal latency; `disabled` on Sonnet 5.5 returns 400), adaptive thinking + `effort: medium` for screenshots; `fallbacks: "default"` with the header `server-side-fallback-2026-07-01`; temperature is not sent (R-13, the `claude-api` skill).
- 2026-10-06, P-07: an invalid key (400/401/403) — move to the next provider without retrying this one, including without the same provider's fallback model (R-09, AC-07).
- 2026-10-06, P-07: a Gemini fallback model was added (`gemini-flash-latest`, editable in Models) right after the main one: the main `gemini-3.8-flash` on a free key answered 503 "high demand". The chain stays Gemini → DeepSeek → Claude (R-09).
- 2026-10-06, P-07: if Gemini does not accept `thinkingLevel` (a 400 about thinking), the request is retried without it — different Flash models have different level sets (R-09).
- 2026-10-06, P-07: partial text on a failure mid-answer is discarded (`restart`), the next provider answers from scratch (R-09, R-10).
- 2026-10-06, P-07: provider errors are cleaned of the key value if the key is longer than 8 characters (short test values are left alone) (R-23).
- 2026-10-07, P-08: keys are read only in the background; the decision "card or generation" uses key presence without reading the value: while a system Keychain prompt is pending, any call to it waits, and the bank card appeared after 4.4 s (AC-02).
- 2026-10-07, P-08: after every rebuild with "Allow" (not "Always Allow") macOS asks for key access again; after the owner's "Always Allow" rebuilds pass without a prompt (R-23).
- 2026-10-07, P-08: the free quota of `gemini-3.8-flash` and `gemini-flash-latest` for the day was used up by latency measurements (≈ 40 requests) — "You exceeded your current quota". The fallback model was switched to `gemini-flash-lite-latest` (a separate quota, first token 0.7–1.9 s). The quota resets daily — H-4 is better after the reset. The executor's live requests are kept to a minimum.
- 2026-10-07, P-08: microphone threshold −36 dBFS (speaker echo at the microphone ≈ −40…−44 dBFS); "owner speech" that starts ≤ 500 ms before the other person's speech is echo (R-02, S-07, `turn` eval +2 cases).
- 2026-10-07, P-09: the screenshot fixture is drawn off screen rather than captured in Chrome: the executor process has no Screen Recording permission (R-14).
- 2026-10-07, P-10: session texts are saved as is (R-19 requires utterances and the answer); files use `completeFileProtection`, the folder is outside Git.
- 2026-10-07, P-11: with a self-signed certificate "Always Allow" in the Keychain applies only to a specific build: after every code change macOS asks again. The final build asks once. Certificate trust was not changed (CLAUDE.md); an option for the owner — mark the certificate as trusted for code signing (in the report).
- 2026-10-07, P-11: the first-run wizard is shown until completed or if models are missing; the owner will see it once, all green (S-09).
- 2026-10-07, P-11: metrics are logged at the notice level — info lives only in memory, and the measurement of a past call was lost (R-24).
- 2026-10-07, P-12: "conversation language" (the detector is skipped after two confident lines) is on: interviews are usually in one language; with mixed ru/uk/en speech the recommendation is to choose the language in the menu. Bank prompting — an off-by-default option (mixed effect in measurements). A separate model for the language detector was rejected (memory ~1.4 GB without embeddings) (R-03, AC-01, AC-05, AC-10).
- 2026-10-07, P-13: `.gitignore` — data-directory patterns anchored with `/` (`/models/`, `/profile/`, `/sessions/`, `/logs/`): on case-insensitive macOS `models/` hid `Sources/CopilotCore/Models/` (AC-14).
- 2026-10-07, owner request: the new "Microphone" source extends R-01 (self-check mode); R-02 ("the microphone is not transcribed") applies to call sources, in the "Microphone" mode the microphone is the other person. Requires owner confirmation at acceptance as a spec change.
- 2026-10-06, P-00: whisper.cpp and llama.cpp come from build tags `bNNNN` (where the XCFrameworks are), the version is pinned by URL + checksum (ADR-0001 items 5, 9).

## Open questions
No blockers. Non-blocking questions — intent.md, section "Open questions".

## Permissions
- Allowed:
  - code, tests and scripts in the repository;
  - commits and `git push` to `feat/copilot-01`;
  - downloading models and dependencies from ADR-0001;
  - live requests to Gemini with the owner's key.
- Not allowed:
  - force-push, `reset --hard`, deleting branches, merging into `main`;
  - changing TCC and Keychain trust;
  - paid services and dependencies outside ADR-0001;
  - publishing.

## Risks and rollback
Rollback point: the initial commit of `main`. Rolling back a step — `git revert` of its commit.

## Continuation 2026-10-08 — local STT accuracy

Owner authorization: execute the plan, free local recognition first; the top priority is accuracy.
Executor decisions: FluidAudio 0.17.7 and Parakeet v3, the dependency recorded in ADR-0001;
full Whisper for finals, fast partial results; a snapshot of the audio/language of each closed phrase;
VAD positions inside a block and keeping all transitions. Engine/model selection in Audio.
First-stage checks: PASS 149 tests, including buffer overwrite, several phrases in a block,
keeping the language and continuous stereo48k → mono16k conversion. Repeat after integration.
A live call and a direct comparison with parakeet-ai.com: NOT RUN, needed at H-4.

### Result of the local stage 2026-10-08

v0.1.1 (build 2) is ready, Parakeet v3 is the main engine, Whisper turbo/full the alternative.
PASS: 151 tests, bank/turn evals, SHA256 checks (23 Parakeet files and two Whisper),
54 files through the adapter, an EN/RU/UK stream (final 461–519 ms), secret scan 0 findings,
build and strict local signature check. Results and limitations were added to report.md.
The signing script was fixed: a variable before a typographic quote requires `${IDENTITY}`.
FLEURS audio and working results were not added to Git. Generation APIs were not called.
Next step: H-4 — a live test by the owner, five phrases per language, separately negations/names/numbers/terms;
check the audio source, language switches and memory. Do not mark AC-10 PASS without it.


### Local test call 2026-10-08 — v0.1.2 (build 3)

Owner request: the other person reads phrases, the app compares the recognition with the original.
Implemented: the "Test call…" item, a local browser page, 15 synthetic phrases
RU/UK/EN (normal, negation, quiet, compressed, technical), word comparison/difference highlighting,
latency, repeat/stop, per-language results, a JSON report. The server listens only on 127.0.0.1, a random
token, Host/Origin checks, a resource whitelist, Range support for WAV.
Executor decisions: a separate Chrome so that audio goes through real capture; without Chrome, Safari
uses all system audio. In the test the language is Auto, the personal bank dictionary is not applied,
the microphone and answer generation are off, the phrase history is not appended. The source is not saved
to settings; the previous text/language/source/pause are restored. Missing audio and an unfinished
queue after 20 s show a problem. Closing the tab ends the test; a 90 s fallback timer
without requests. --test-call skips the cloud checks and the bank; the old instance must be closed.
Audio fixtures are synthetic only, in the allowed evals/audio/test-call/; models are not in Git.
No new external dependencies (Network/AppKit are built in).
PASS: 157 tests; turn 36; bank top1 94.9%, top3 100%, false 0/12; secret scan 0;
build/strict signature; 15 phrases through Chrome audio → SystemAudioCapture → Parakeet;
checking the JSON export from the browser; HTTP/Range/Host/Origin/token/traversal checks;
the final build: model readiness, rejection of overlapping tests and a stale end, server reset/close
and unchanged saved settings.
Measurement of 15 synthetic phrases: 316 words, 20 errors (6.33% raw WER), median latency 501 ms.
RU 7/96 (7.29%), UK 9/97 (9.28%), EN 4/123 (3.25%). Most errors are terms and number spelling.
The full run was done before adding highlighting/per-language results and the close-on-launch guard;
the final version passed tests/build and control checks again, rendered the page and
recognized the first phrase through the browser. Highlighting was checked separately on omissions/substitutions/insertions.
NOT RUN: the whole set in Safari, unclear human speech/noise, language mixing inside a phrase,
a direct comparison with parakeet-ai.com. Next step: recordings of a real voice with a reference,
compare Parakeet and Whisper on identical audio. Quiet-speech normalization already exists;
automatic engine selection for unclear speech is not implemented yet.
Commit: adding the local test call to feat/copilot-01 (hash in the Git history).
