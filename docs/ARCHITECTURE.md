# Interview Copilot — architecture reference

For a new developer or agent: what the app does, how data flows, where things live, how to change and verify them.
Start with [`AGENTS.md`](../AGENTS.md) (onboarding), then this document, then `CLAUDE.md` (working rules) and the latest
task folder in `docs/changes/`.

## 1. What it is
A personal macOS app (Swift 6, SwiftUI + AppKit, SwiftPM, no `.xcodeproj`): a parrot in the menu bar, a main window and a
floating overlay. During a call (Google Meet in a browser, Zoom, Telegram) the app:
1. listens to the other person's audio (ScreenCaptureKit, audio of a single app) and, separately, to the owner's microphone;
2. transcribes speech **locally** (Parakeet v3 via FluidAudio; Whisper via whisper.cpp as an alternative and for refinement);
3. filters out noise, foreign-language speech and other voices;
4. detects the end of a question (a turn);
5. shows an answer: a card from the owner's bank or a language-model hint (Groq → Cerebras → Gemini → DeepSeek →
   Claude → custom API), streamed; the first words appear about 1 s after the question ends;
6. remembers the whole interview: questions, the owner's answers, shown hints — and reviews it after the call.

Languages: Ukrainian, Russian, English. One user — the owner. No audio is written to disk.

## 2. Data flow
```
call app audio ─► SystemAudioCapture ─► AudioRingBuffer (30 s) ─► StreamingTranscriber ─┐
owner mic ─► MicActivityDetector (is the owner speaking) ─► TurnDetector                  │
          └► second StreamingTranscriber (owner answers) ─► InterviewMemory.addAnswer     │
                                                                                          ▼
StreamingTranscriber: EnergyVAD splits phrases → [LocalVQE, off] → Silero "is it speech" →
  Parakeet (final ~0.1 s) → HallucinationFilter → CAM++ voiceprint (microphone mode) →
  events .partial / .final / .revised (Whisper turbo refine, ~3 s) / .foreignVoice / .discarded
                                                                                          │
ListeningController.handle: language filter (LanguageGate + term dictionary) → overlay line or a gray line
                                                                                          ▼
TurnController → TurnDetector: pause T (700 ms; 350 ms after "?"), owner speech, echo → Turn
  + speculative request (draft) for a finished phrase before the pause expires
                                                                                          ▼
AppDelegate.turnCompleted → InterviewMemory.addQuestion(turnID) → AnswerController.handle(turn)
  AnswerController: BankController.lookup (one bge-m3 embedding: bank cards + material chunks) →
  AnswerRouter (mode) → card | PromptBuilder (profile, instructions, <materials>, history) → ProviderChain
  (SSE streaming, key rotation, parallel request to another provider after `hedgeAfter`, fallback, last resort) →
  AnswerHistory (question → versions; each request writes only to its own version) → PanelModel → PanelView
  (overlay: toolbar, transcript strip, answer card, chat field)
                                                                                          ▼
hint → InterviewMemory.setHint(turnID); everything → SessionController → SessionStore (JSON, retention) →
ReviewController (post-call comments, summary, "Ask AI")
```
The main actor (`@MainActor`) owns the UI and controllers. Recognition, embeddings, Keychain and networking run in the
background (`Task.detached`, transcriber queues). Cross-thread state uses small `…Box` classes with `NSLock`
(`TranscriberBox`, `VoiceGateBox`, `EnhancerBox`, `AudioRouteBox`).

## 3. Modules
| Folder | What | Key types |
|---|---|---|
| `Sources/CopilotCore/Audio` | capture, VAD, buffer, permissions | `SystemAudioCapture`, `MicrophoneCapture`, `EnergyVAD`, `AudioRingBuffer`, `AudioSourceResolver` |
| `…/STT` | recognition | `StreamingTranscriber` (segmentation, finals, refinement), `ParakeetEngine`, `WhisperEngine`, `HybridRecognizer` |
| `…/Filter` | what not to recognize or show | `SileroSpeechGate`, `LanguageGate`, `TermDictionary`/`BuiltinTerms`, `VoicePrint`/`VoiceEmbedder`/`VoiceGateBox`, `SpeechEnhancer`, `HallucinationFilter` |
| `…/Turns` | end of question | `TurnDetector` (pure logic, fully tested), `TurnEval` |
| `…/Profiles` | profiles, file import, materials (COPILOT-08) | `ProfileLibrary` (create, switch, delete, migrate the old `profile/`, materials), `ProfileDocument`, `DocumentText` (PDF — PDFKit, .docx/.rtf — AppKit, .txt/.md), `MaterialChunker`, `MaterialIndex`, `MaterialIndexBuilder` |
| `…/Bank` | profile and answer bank | `Profile`, `ProfileStore.load`, `QuestionBank` (YAML: `BankCard` with an answer status, `QuestionBankWriter`), `QuestionImport` (rules + model), `QuestionPreparation` (phrasings, drafts), `BankMatcher`, `TextEmbedder` |
| `…/Answer` | card / no match / generation; answer history | `AnswerRouter`, `ScreenshotTask`/`ScreenshotTaskTracker` (screenshot task, 30 s, `<active_task>`), `FollowUpDetector` (short follow-ups), `AnswerStyle` (format, length, tone → prompt rule; `AnswerShape` checks the shape), `AnswerHistory` (`AnswerEntry` → `AnswerVersion`: hint / bank / strong / screenshot / refine, statuses, ←/→, "new answer") |
| `…/LLM` | providers and prompt | `PromptBuilder` (all rules for the model), `ProviderChain` + `ProviderHealth` + `ChainFactory`, `Providers` (Gemini, DeepSeek, Anthropic, OpenAI-compatible: Groq, Cerebras, custom API), `SSEClient` (incl. `SSE.redactIdentifiers`), `RetryHint`, `KeyVerifier` |
| `…/Memory` | interview memory | `InterviewMemory`, `SessionExchange`, `MemoryContext`, `ReferenceDetector`, `PromptScenarios` (live prompt checks) |
| `…/Storage` | session history | `SessionRecord` (with the session `config`, the owner's timed utterances and the review), `SessionStore` |
| `…/Review` | review after End (COPILOT-09) | `SessionReview` (status, `ReviewComment`, `ReviewSummary`, `ReviewQA`), `ReviewPrompt` (comments in batches, summary, "Ask AI"), `TimelineEntry` / `SessionRecord.timeline` |
| `…/Session` | session (COPILOT-09) | `SessionConfig`/`SessionType`/`SessionPhase`/`SessionClock`, `Preflight` (pre-start check), `CallDetection`, `JobImport` |
| `…/Localization` | UI language (COPILOT-10) | `L10n` (key = Russian string, English from `en.lproj`, `Scope` for tests), `PageLocalization` (web pages via `en.json`) |
| `…/Settings` | settings, paths, overlay geometry | `AppSettings` (`schemaVersion` migrations), `SettingsStore` (UserDefaults `settings.v1`), `AppPaths`, `PanelResizing` |
| `…/Secrets` | API keys | `KeychainStore` (service `com.itmax04.interviewcopilot`, unlimited slots `groq`, `groq#2`, …), `KeySlots` |
| `…/Interviewer`, `…/TestCall` | AI voice interview, browser test call | `InterviewerPrompt`, `SpeechSynth`, `AnswerCapture`, `LocalTestCallServer`, `TranscriptComparison` |
| `…/Hotkeys`, `…/Menu` | global hotkeys (Carbon), menu content | `HotkeyCenter`, `HotkeyAction`, `MenuLayout` (no AppKit — testable) |
| `…/Usage`, `…/Privacy`, `…/Models`, `…/Capture`, `…/Logging` | spending and budget, PII filter, model download with SHA256, screenshots, logs | `UsageMeter`, `PIIFilter`, `ModelDownloader`, `ScreenshotService`, `Log` |
| `Sources/CopilotEmbeddings` | bge-m3 via llama.cpp (separate because of ggml headers) | `LlamaEmbedder` |
| `Sources/InterviewCopilot` | the app: wires everything | `AppDelegate` (App.swift — all callback wiring), `LiveSessionController` (Start/End, timer, call detection), `Workspace/WorkspaceWindow` (main window: Today, Sessions, Profiles, AI interview, Settings; language and theme switchers in the sidebar), `Design/DesignSystem` (`IC` — dynamic light/dark colors and components, `ICDark` — overlay), `Design/Localization` (`UILanguage`, `localizedRoot`, `L(…)`, `Text(String)` overloads), `SessionWizard`, `AnswerStyleEditor`/`StylePreview`, `ListeningController` (incl. `standby` without a session), `TurnController`, `AnswerController`, `SessionController` (history), `ReviewController` (background review), `PanelController` (collapse, next screen, chat focus, visibility check)/`PanelResize`/`PanelView`/`AnswerCardView`, settings, profile, history |
| `Sources/copilot-eval` | measurement CLI | see §6 |

Rule: logic belongs in `CopilotCore` (tested without UI); the app only wires and displays.

## 4. Data on disk
`~/Library/Application Support/InterviewCopilot/` (override with `INTERVIEWCOPILOT_HOME`):
- `profiles/<id>/` — `profile.yaml` (name), `resume.md`, `stories.md` (facts about the candidate), `job.md`,
  `instructions.md` (profile instructions), `questions.yaml`, `sources/` (uploaded originals), `materials/` (text `*.md`
  + `sources/`), `materials-index.plist` (chunk vectors); permissions 700/600. Active profile — `AppSettings.activeProfileID`;
- `instructions.md` — the owner's general instructions (all profiles and "No profile"). The legacy `profile/` folder is
  migrated into `profiles/` on launch, an unchanged copy of the example is removed; `profile.example/` is for tests and evals only;
- `models/` — Whisper, bge-m3, Parakeet, Silero, CAM++, LocalVQE (lists and SHA256: `models.sha256`,
  `parakeet-models.json`, `filter-models.json`);
- `sessions/*.json` — history (utterances, turns, exchanges with the owner's answers, review), permissions 600, purged by
  retention; "Delete all history" also removes unreadable files;
- `voice/owner.json` — voiceprint (192 numbers), 600; `usage.json` — spending.
Settings — UserDefaults `com.itmax04.interviewcopilot`, key `settings.v1`. API keys — Keychain only.

## 5. Making typical changes
- **Owner instructions** — the `<owner_instructions>` block at the end of `PromptBuilder.system`: outranks style and format
  rules but not the reliability rules; profile, materials and utterances remain data.
- **A rule for the model** — `PromptBuilder.system` / `user`; pin it with a test in `Tests/CopilotCoreTests/` and, if it is
  model behavior, a scenario in `PromptScenarios` plus a live `--smoke-memory` run.
- **An LLM provider** — `ProviderID` + `ProviderEndpoints` + an `LLMProvider` implementation (SSE) + `ChainFactory.providers` +
  an `AppSettings.chain` migration + `KeyVerifier`; stream fixtures in `Tests/CopilotCoreTests/Fixtures/`; set
  `acceptsImages = false` for text-only providers.
- **A setting** — a field in `AppSettings` (+ decoding with a default, `normalized()`), UI in `Settings/`, reaction in
  `AppDelegate.applySettings`.
- **A hotkey** — a new `HotkeyAction` **only at the end** of `allCases` (raw value = index), default in
  `HotkeyBinding.defaults`, handling in `AppDelegate.handle(_ action: HotkeyAction)`; UI labels via `hotkey(_:)`, not a literal.
- **A menu item** — `MenuAction` + `MenuLayout.sections` + `AppDelegate.handle(_ action: MenuAction)` (exhaustive switch) +
  `MenuLayoutTests`.
- **UI text** — a Russian string as one literal: SwiftUI literals translate themselves, code strings use `L("…")`
  (`CopilotCore` — `L10n.t`/`f`); translation in `Resources/en.lproj/Localizable.strings`; check with
  `scripts/check-localization.sh`. A new window: `.localizedRoot()` on the root and `UILanguage.shared.setTitle(_:of:)` for
  the title. Colors — `IC` tokens only.
- **Model chain** — order of attempts and failures in `ProviderChain` (sequential `run` and parallel `runHedged`): keys of a
  provider in turn → next provider → `lastResort` (wait ≤ 25 s for a key reset, patient timeout). Cool-downs in
  `ProviderHealth` (429 — per key, timeout/5xx — whole model). A model with its own timeout — `Step.minFirstTokenTimeout`.
- **Overlay size** — `PanelResizeHandle` strips (AppKit) around the window; geometry in `PanelResizing` (Core, tested).
- **Capture start/stop** — `ListeningController.captureWanted` is the single source of intent; every async capture
  operation re-checks it when it finishes.
- **A new field in history** — optional or `decodeIfPresent`: old files must keep loading.
- **A new dependency or model** — only via an entry in `docs/decisions/ADR-0001-stack.md`; models with SHA256.

## 6. Checks
| What | Command |
|---|---|
| Quick | `swift build && swift test` (361 tests) |
| Full | `swift test && scripts/run-evals.sh && scripts/secret-scan.sh && scripts/check-localization.sh && scripts/build-app.sh` |
| Translations | `scripts/check-localization.sh [--unused]` — keys without a translation, mismatched formats |
| Audio evals | `scripts/run-evals.sh filter voice` (needs Parakeet, Silero, CAM++) |
| CLI | `swift run -c release copilot-eval <stt|stt-parakeet|stt-hybrid|stt-stream|turn|bank|filter-text|filter|voice|voice-enroll|enhance|memory|exit-check>` |
| Live (spend free quota) | `dist/InterviewCopilot.app/Contents/MacOS/InterviewCopilot --smoke-llm`, `--smoke-memory 5`, `--smoke-prepare`, `--smoke-session`, `--smoke-review`, `--smoke-task evals/fixtures/two-sum.png`, `--smoke-screenshot evals/fixtures/two-sum.png`, `--smoke-panel-resize`, `--ui-snapshots <dir>` (window snapshots without audio) |
| Call metrics | `scripts/metrics.py --last 30m` (from the log, numbers only) |

Eval thresholds — `evals/README.md`. Live checks run from the signed `.app`: only it gets the keys from the Keychain without a prompt.

## 7. Log and debugging
`log show --predicate 'subsystem == "com.itmax04.interviewcopilot"' --info --last 30m` (in zsh — `/usr/bin/log`).
Categories: `audio`, `stt`, `turns`, `llm`, `metrics`, `app`. Important events: `transcript_final`, `transcript_revised`,
`filtered reason=lang|vad|voice|echo|hallucination`, `voice_ok similarity=…`, `turn_end`, `draft_start/used/cancelled`,
`bank_match`, `no_match`, `first_token … ms_from_speech_end=…`, `not_a_question`, `last resort: …`,
`owner answering on/off`, `owner_final`, `capture_restart`.
**Utterance texts, answers and keys are never logged** — only events, numbers and model IDs; provider error messages are
redacted (`SSE.redactIdentifiers`).

## 8. Rules (short; full version in CLAUDE.md)
- Keys and personal data never go into code, logs, tests or commits; test data is synthetic.
- One task — `docs/changes/COPILOT-NN/` (intent → spec → [plan] → handoff) and a branch `feat/copilot-NN-…` from the previous
  one; commit after each step; push and merging into `main` by the owner's decision; no force-push or history rewriting.
- The handoff lists what was done, commits, checks PASS/FAIL/NOT RUN, executor decisions and the next step.

## 9. Task history
| Task | What | Branch |
|---|---|---|
| COPILOT-01 | v1: capture, Whisper, bank, Gemini/DeepSeek/Claude, overlay, menu, history | `feat/copilot-01` |
| COPILOT-02 | Parakeet v3 accuracy plan, a draft superseded by COPILOT-03/05; English copy in `docs/changes/COPILOT-02/` | `docs/copilot-02` (documents only) |
| COPILOT-03 | AI voice interview, Parakeet + hybrid with Whisper, "No profile" mode | `feat/copilot-03-ai-interviewer` |
| COPILOT-04 | instant answers: Groq/Cerebras, parallel requests, speculative request, custom API | `feat/copilot-04-instant-answers` |
| COPILOT-05 | filters: Silero, language with terms, voiceprint, LocalVQE, owner speech on calls | `feat/copilot-05-speech-filter` |
| COPILOT-06 | interview memory, "New interview", hint instead of an unrecorded answer, ⌃⌥A | `feat/copilot-06-session-memory` |
| COPILOT-07 | audit and polish: "you mentioned" traps, binding to the turn, "I'm answering now" menu item, history, `--smoke-memory` | `feat/copilot-07-hardening` |
| COPILOT-08 | profiles: Profile window, PDF/Word/RTF/text, owner instructions, materials, questions with answers | `feat/copilot-08-profiles` |
| COPILOT-09 | ParakeetAI parity: sessions (wizard, Start/End, pre-check, job import), live overlay, answer style, review after End, screenshot tasks, redesign from ImageGen references, multiple keys (0.7–0.13) | `feat/copilot-09-parakeet-parity` |
| COPILOT-10 | light and dark window theme, Russian and English UI (instant switch), review in the UI language (0.14) | `feat/copilot-10-theme-language` |
| COPILOT-11 | fixes after the test interview: chain "last resort", hedge to another provider, screenshots only to image-capable providers, Gemini timeout floor, "have you worked with X?" rule, interviewer monologue is not a question, overlay resizing, "Delete all" questions (0.15) | `feat/copilot-11-test-call-fixes` |
| COPILOT-12 | final review: capture start/stop race, history wipe, error redaction, Groq token budget, repository hygiene, English documentation and `AGENTS.md`, `main` fast-forwarded (0.15.1) | `feat/copilot-12-final-review` |

Branches form a chain (each from the previous one). `main` is fast-forwarded to the latest reviewed task by the owner's decision.

## 10. Known limitations and where to grow
- Parakeet's Ukrainian recognition is the main source of text errors; the Whisper refinement sometimes damages a phrase.
- Model answers are probabilistic: rules are checked with `--smoke-memory` but not guaranteed.
- Free Groq tiers (8 000 tokens per minute per key) and a ~6 000-token hint prompt mean about one hint per minute per key;
  a fast series of questions moves the chain to fallback models.
- No acoustic echo cancellation: echo is removed by the voiceprint and a timing rule (COPILOT-05 R-04).
- Ideas: "extend the voice sample", CI for the full check, a shorter prompt (fewer TPM tokens), English source comments.
