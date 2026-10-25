# COPILOT-01: Technical plan v1

ID: COPILOT-01-plan · Status: **accepted** (2026-10-06) · Version: 1 · Date: 2026-10-06 · Owner: itmax04
Precondition: spec.md v1 and ADR-0001 are accepted by the owner. Requirements are not repeated here — only references to R-/AC- numbers from [spec.md](spec.md).
Executor: Claude Code, `claude-opus-5-5`, effort high (Q8).

## Preconditions and state
- Repository: `~/Desktop/1/interview-copilot`, private `itmax04/interview-copilot`.
- Branches: `main` contains only the initial commit; all work happens in `feat/copilot-01`.
- Baseline: when the plan was written there was no code. The executor records the actual SHAs and check results in handoff.md at P-00.
- All commands below are **new**: the steps of this plan create them. Until a command exists, its result is NOT RUN.

## Manual action points (H)
The executor reaches a point, pauses, gives the owner step-by-step instructions and waits for "done". No other questions (Q9).

| H | When | Owner action |
|---|---|---|
| H-0 | P-00, if `swift test` does not work without Xcode, or if the whisper/llama XCFrameworks need Xcode | Install Xcode from the App Store, launch it once, `sudo xcode-select -s /Applications/Xcode.app` |
| H-1 | P-01 | Create the "InterviewCopilot Dev" code-signing certificate in Keychain Access → Certificate Assistant (self-signed, type "Code Signing") |
| H-2 | P-02 | Enter the Gemini key in Settings → Keys (not in chat) and press "Check" |
| H-3 | P-03 | First launch the app without permissions (checks AC-13), then grant "Screen & System Audio Recording" and "Microphone" |
| H-4 | P-12 | A test call: Meet in Chrome on the Mac + a phone, read `evals/live-script.md` (≈10 min); assess AC-10 and AC-11 |
| H-5 | P-13 | Acceptance of the result per report.md |

## Files and order
Each step: implementation → step checks → handoff.md update → commit `P-xx: <short>` → `git push`.

**P-00. Survey and baseline**
- Record in handoff.md: `git status`, `swift --version`, `xcode-select -p`, free space.
- A minimal package in a temporary scratchpad folder: check `swift test` (Swift Testing and XCTest) on the CLT.
- Check whether XCFrameworks are available in the whisper.cpp and llama.cpp releases (URL, version, SHA).
- Record the decision "is Xcode needed" in the handoff. Needed → H-0.

**P-01. App skeleton** — R-15 (static menu), R-18 (empty settings window)
- `Package.swift`: targets `InterviewCopilot`, `CopilotCore`, `copilot-eval`, `CopilotCoreTests`; the Yams dependency.
- `Sources/InterviewCopilot/App.swift`, `MenuBarController.swift`, `SettingsWindow.swift`.
- `Resources/Info.plist`: `LSUIElement`, `NSMicrophoneUsageDescription`, bundle ID from ADR-0001; a parrot template icon.
- `scripts/build-app.sh`: release build, packaging into `dist/InterviewCopilot.app`, signing with "InterviewCopilot Dev" (H-1).
  Without the certificate the script fails with a clear error.
- `scripts/secret-scan.sh` (AC-06): Gemini (`AIza…`), Anthropic (`sk-ant-…`), DeepSeek (`sk-…`) key patterns,
  emails and phones outside `profile.example/`, files from `.gitignore` that got into the index. Run before every push from this step on.
- Checks: `swift build`, `scripts/build-app.sh`, `scripts/secret-scan.sh`, launch — the icon and menu are visible (screenshot).

**P-02. Settings and keys** — R-18, R-23
- `CopilotCore/Settings/SettingsStore.swift` (UserDefaults + JSON), `CopilotCore/Secrets/KeychainStore.swift`.
- `Sources/InterviewCopilot/Settings/*View.swift` — tabs Keys, Models, Audio, Bank, Privacy, Panel, Hotkeys, Budget.
- "Check key" — a request for the provider's model list. Result: OK or an error text, without printing the key.
- Tests: `KeychainStoreTests` (a separate test service and cleanup after the test), `SettingsStoreTests`.
- H-2.

**P-03. Audio capture and permissions** — R-01, R-02, R-04, S-09 (the "permissions" part), AC-13
- `CopilotCore/Audio/SystemAudioCapture.swift` (SCStream, per-app filter, 16 kHz mono Float32).
- `CopilotCore/Audio/MicActivityDetector.swift` (AVAudioEngine + energy VAD).
- `CopilotCore/Audio/AudioSourceResolver.swift` (Auto: zoom.us → Chrome → Telegram).
- `Sources/InterviewCopilot/Onboarding/PermissionsView.swift`.
- Tests: `AudioSourceResolverTests`; capture — manually: the signal level in a debug panel while a video plays in Chrome.
- H-3.

**P-04. Recognition** — R-03, R-22
- `scripts/fetch-models.sh` + `models.sha256`: whisper `large-v3-turbo-q5_0` and `small-q5_1`.
- `CopilotCore/STT/WhisperEngine.swift`: a C API wrapper; a streaming window; VAD segmentation; partial and final text; language.
- `Package.swift`: a whisper.cpp `binaryTarget` (URL + checksum).
- Measurement: end of phrase → text latency and memory on recordings from `evals/audio/` (synthetic, voiced with `say`:
  uk — voice Lesya, ru — Milena, en — Samantha). If a voice is missing → record in the handoff, replace with an available one.
- The turbo/small decision — by AC-01 and AC-05, recorded in ADR-0001.
- Tests: `WhisperEngineTests` on a short file from `evals/audio/` (check "text is not empty, the language is correct").

**P-05. Turns and the panel (basic)** — R-05, R-16 (header, Interviewer, idle/listening/paused states), S-07, S-08
- `CopilotCore/Turns/TurnDetector.swift` (threshold T, ≥ 3 words, owner speech, forced turn).
- `Sources/InterviewCopilot/Panel/PanelController.swift` (non-activating NSPanel), `PanelView.swift`, `TranscriptView.swift`.
- `CopilotCore/Hotkeys/HotkeyCenter.swift` (Carbon), ⌃⌥P / ⌃⌥H / ⌃⌥↩ — R-17.
- The `turn` eval (evals/README.md) and `copilot-eval turn`.
- Tests: `TurnDetectorTests`.

**P-06. Question bank** — R-06, R-07, S-10, AC-04
- `profile.example/`: `profile.yaml`, `resume.md`, `job.md`, `stories.md` (a fictional candidate),
  `questions.yaml` (≥ 15 cards uk/ru/en, some tagged STAR).
- `CopilotCore/Bank/QuestionBank.swift` (Yams, validation, file watching), `EmbeddingEngine.swift` (llama.cpp),
  `BankMatcher.swift`, an embedding cache.
- The `bank` eval: `evals/bank/cases.jsonl`. Model candidates — ADR-0001 item 6; record the choice and threshold in ADR-0001 and evals/README.
- Tests: `QuestionBankTests` (validation, parse errors), `BankMatcherTests` (a deterministic stub embedder).

**P-07. Providers and router** — R-09…R-13, AC-07, AC-08
- Before the Anthropic code, read the `claude-api` skill (curl/examples.md, streaming, refusal/fallbacks);
  for Gemini and DeepSeek — their official streaming documentation. Check model IDs against the model list.
- `CopilotCore/LLM/LLMProvider.swift` (protocol), `SSEClient.swift`, `GeminiProvider.swift`, `DeepSeekProvider.swift`,
  `AnthropicProvider.swift`, `MockProvider.swift`.
- `CopilotCore/LLM/ProviderChain.swift` (fallback triggers, 4-second first-token timeout, cancellation).
- `CopilotCore/LLM/PromptBuilder.swift` (R-11), `CopilotCore/Privacy/PIIFilter.swift` (R-12).
- `CopilotCore/Answer/AnswerRouter.swift` (modes R-08).
- Tests: `ProviderChainTests`, `AnswerRouterTests`, `PromptBuilderTests`, `PIIFilterTests`, `SSEClientTests`
  (stream fixtures in `Tests/Fixtures/`).
- A live smoke test only with Gemini (key from H-2); DeepSeek and Anthropic without keys — NOT RUN with a note.

**P-08. Answer card and modes in the UI** — R-08, R-16 (answer / no-match / thinking / error), R-15 (Mode, Models, Language), S-01…S-05, S-11
- `Sources/InterviewCopilot/Panel/AnswerCardView.swift` (Markdown, STAR chips, Copy, ↑ Claude), panel states.
- Connect the menu submenus to SettingsStore.

**P-09. Screenshot** — R-14, S-06
- `CopilotCore/Capture/ScreenshotService.swift` (SCScreenshotManager, panel exclusion, downscaling), ⌃⌥S, ⌃⌥C.
- Live check on Gemini (no Anthropic key) with the task image `evals/fixtures/two-sum.png`
  (create it: a screenshot of a synthetic problem statement opened in Chrome).

**P-10. History, spending, budget** — R-18 (Budget), R-19, R-20, the R-15 status line
- `CopilotCore/Storage/SessionStore.swift`, `CopilotCore/Usage/UsageMeter.swift`, `Resources/pricing.json`.
- `Sources/InterviewCopilot/History/SessionHistoryWindow.swift`.
- Tests: `SessionStoreTests` (save, delete, retention — AC-12), `UsageMeterTests` (prices, DeepSeek peak hours, limit).

**P-11. First launch, polish, resources** — all of S-09, R-16 (accessibility, Reduce Motion), R-24, R-25, AC-09, AC-11
- Wizard: permissions → key → models.
- Compare the menu with `docs/design/menu-v2.webp`: a screenshot next to the picture → `docs/changes/COPILOT-01/evidence/`.
- Memory measurement (`footprint`), profiling if exceeded.
- `scripts/metrics.py`; `scripts/run-evals.sh` combines `copilot-eval bank` and `copilot-eval turn`
  (created earlier, at P-05/P-06, if needed).

**P-12. Test call** — AC-01…AC-03, AC-05, AC-10
- Prepare `evals/live-script.md` (15 questions: 5 uk, 5 ru, 5 en; some paraphrase the bank, some are outside it).
- H-4. After the call: `scripts/metrics.py` on the logs → a table of medians in report.md.

**P-13. Independent review and report**
- A fresh-context review: a new Claude Code session (Opus 5.5, high) or `/code-review high` on the `feat/copilot-01` branch
  against spec.md and CLAUDE.md. Fix P0/P1 findings, list the rest.
- `docs/changes/COPILOT-01/report.md`: tracing AC → evidence → PASS/FAIL/NOT RUN, unverified items, known limitations.
- Update the README (actual commands), ADR-0001 (final decisions). H-5.

## Dependencies
Only from ADR-0001 item 9. Anything else — an ADR-0001 entry + a note in the handoff ("requires owner confirmation at acceptance").

## Checks
| Command (new) | Steps | Expected evidence |
|---|---|---|
| `swift build` | all | Build without errors |
| `swift test` | P-02+ | All tests green; the test count in the handoff |
| `scripts/build-app.sh` | P-01+ | `dist/InterviewCopilot.app`; `codesign -dv` shows "InterviewCopilot Dev" |
| `scripts/fetch-models.sh` | P-04+ | Model files, SHA256 match |
| `scripts/run-evals.sh bank` | P-06+ | Accuracy ≥ 85%, false matches ≤ 10% (AC-04) |
| `scripts/run-evals.sh turn` | P-05+ | Metrics from evals/README |
| `scripts/secret-scan.sh` | P-01+, before every push | "0 findings" (AC-06) |
| `scripts/metrics.py <log>` | P-12 | Medians for AC-01…AC-03 |
| `footprint -p $(pgrep InterviewCopilot)` | P-11, P-12 | Peak ≤ 1.5 GB (AC-05) |

A test must not be weakened to get a green result. If a test needs a network key that is missing, mark it NOT RUN instead of deleting the test.

## Risks and rollback
| Risk | Sign | Action |
|---|---|---|
| Not enough memory or whisper turbo is slow | AC-01/AC-05 not met | The small model; then a smaller window; if that does not help — stop and escalate to the owner |
| Embeddings < 85% | bank eval | The second candidate (ADR-0001); then a hybrid with lexical search (BM25) — with an ADR entry |
| whisper.cpp and llama.cpp symbol conflict | Link errors | Embeddings via Core ML or another candidate; an ADR entry |
| Gemini Free limits | 429 in tests | Pause and retry; on a call the chain kicks in; note it in the report |
| macOS permissions reset | Repeated TCC prompts | Check the signature (H-1); do not touch TCC yourself |

Rollback: each step is a separate commit in `feat/copilot-01`; if a step fails — `git revert` of your commit.
`main` does not change. Destructive git commands are forbidden (CLAUDE.md).

## Stop conditions (escalation to the owner)
- A dependency, service or paid key outside ADR-0001 and the intent is needed.
- A spec requirement cannot be met without changing the scope (for example, AC-05 is unreachable on any model).
- A secret or personal data is found in the Git history.
- Three attempts in a row on the same problem without progress: save the state in the handoff, describe the hypotheses.
- Any action from the "Forbidden" list in CLAUDE.md.

## Done when
AC-01…AC-14 have evidence in report.md (PASS, or NOT RUN with a reason accepted by the owner),
the P-13 review has no open P0/P1, the `feat/copilot-01` branch is pushed, handoff.md is current, the owner confirmed H-5.
