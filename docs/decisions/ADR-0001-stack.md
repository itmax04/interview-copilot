# ADR-0001: Interview Copilot v1 stack and architecture

Status: **accepted** (2026-10-06); final decisions added 2026-10-07 (P-04, P-06, P-12, P-13) · Date: 2026-10-06 · Owner: itmax04 · Links: [intent](../changes/COPILOT-01/intent.md), [spec](../changes/COPILOT-01/spec.md)

## Context
- A personal macOS app, one user, MacBook Air M1 with 8 GB of memory, macOS 15.7.2.
- Required: system audio of a specific app, a window above all windows that does not steal focus, global hotkeys,
  the Keychain, local uk/ru/en speech recognition.
- A browser and a call run alongside, so the app must be light (AC-05: ≤ 1.5 GB).
- Swift 6.0 (Command Line Tools) was installed, no Xcode; the owner allowed installing Xcode if needed.

## Shell options
| Option | Pros | Cons |
|---|---|---|
| **Swift (SwiftUI + AppKit)** | Native ScreenCaptureKit, NSPanel, Keychain; ~100 MB of own memory | macOS only (which is what is required) |
| Electron | Familiar web stack | 400–600 MB of memory, system audio through workarounds |
| Tauri | Light | Audio capture and the panel still have to be written in Swift or Rust |
| Python + browser | Fast prototype | No native non-activating panel, heavier on memory |

## Decision
1. **Language and UI:** Swift 6, SwiftUI for content, AppKit for `NSStatusItem`, `NSMenu`, `NSPanel`.
   The app runs as an agent (`LSUIElement = true`): no Dock icon.
2. **Build:** SwiftPM (`Package.swift`) without `.xcodeproj`. `scripts/build-app.sh` assembles the `.app`
   (Info.plist, icon, signature). Targets: `InterviewCopilot` (app), `CopilotCore` (logic, tested),
   `copilot-eval` (eval CLI), tests `CopilotCoreTests`.
3. **Signing:** a persistent local code-signing certificate "InterviewCopilot Dev" (created by the owner, H-1), so macOS
   permissions survive rebuilds. With ad-hoc signing the permissions are lost after every build.
   Bundle ID: `com.itmax04.interviewcopilot`.
4. **Audio:** ScreenCaptureKit (`SCStream`, audio only, filtered by the selected app, `excludesCurrentProcessAudio = true`).
   The microphone via AVAudioEngine is used only to detect whether the owner is speaking (VAD): it is not transcribed or stored.
5. **Speech recognition:** whisper.cpp on Metal.
   - Main model: `large-v3-turbo` quantized q5_0 (~0.6 GB on disk).
   - Fallback: `small` q5_1 if AC-01 or AC-05 is not met (decided in P-04 by measurement).
   - Languages: auto-detection among {uk, ru, en} or an explicit choice in the menu.
   - Integration: a prebuilt XCFramework from whisper.cpp releases as a SwiftPM `binaryTarget`.
     If impossible — build from source with Xcode (Q10: do not look for workarounds).
6. **Bank search:** local multilingual embeddings.
   - Candidate 1: `multilingual-e5-small` in GGUF via llama.cpp (the same ggml as whisper).
   - Candidate 2: `bge-m3` if candidate 1 does not reach ≥ 85% (AC-04) and fits in memory.
   - Card embeddings are cached on disk and recomputed when `questions.yaml` changes.
   - The choice is fixed by the eval results in P-06 and recorded in this ADR.
7. **Language models:** an own HTTP client with SSE streaming, no SDKs: Anthropic has no official Swift SDK, and a single
   `LLMProvider` protocol is easier to test with a mock provider.
   - Gemini: `streamGenerateContent?alt=sse`, default model `gemini-3.8-flash`.
   - DeepSeek: OpenAI-compatible `chat/completions`, model `deepseek-flash`.
   - Anthropic: Messages API, model `claude-sonnet-5-5` (strong), `claude-haiku-4-5` (optional).
   - Model IDs are stored in settings and checked against the providers' `models` endpoints in P-07.
8. **Data:** JSON and YAML in `~/Library/Application Support/InterviewCopilot/` (profile/, sessions/, models/, cache/).
   Keys — Keychain (`kSecClassGenericPassword`, service `com.itmax04.interviewcopilot`).
9. **Dependencies (complete allowed list):**
   - whisper.cpp (XCFramework);
   - llama.cpp (XCFramework) — for embeddings;
   - Yams — YAML parsing;
   - global hotkeys — via Carbon `RegisterEventHotKey` (system API, no third-party packages).

## Final decisions from measurements

### Item 5 — Whisper model (P-04, 2026-10-06): **`small` q5_1**, not `large-v3-turbo` q5_0
Measured on a MacBook Air M1 8 GB, whisper.cpp `b5454` (Metal), 6 synthetic uk/ru/en phrases of 3–6 s (`evals/audio`),
`copilot-eval stt` / `stt-stream`:

| Model | Encoder context | Language | Time per phrase | Quality | Process memory |
|---|---|---|---|---|---|
| large-v3-turbo q5_0 | full (30 s) | auto | 4.2–4.7 s | all 6 phrases correct | ~680 MB |
| large-v3-turbo q5_0 | full | given | 2.1 s | correct | ~680 MB |
| large-v3-turbo q5_0 | trimmed to length | — | 0.7–2.3 s | **unusable**: loops ("it's to, it's to…"), wrong language | ~680 MB |
| small q5_1 | full | auto | 0.9–1.6 s | correct, uk with errors | ~340 MB |
| small q5_1 | trimmed | given | **0.16–0.27 s** | correct (uk even better than with full) | ~340 MB |

- AC-01 (≤ 1 s from end of phrase to text) is unreachable on turbo even with a given language (2.1 s + 0.3 s VAD pause).
- Chosen: small with trimmed context and the language known by the end of the phrase. Real-time streaming run
  (`copilot-eval stt-stream`): median "end of phrase → final text" **524 ms**, max 583 ms, languages 6/6 correct.
  In the built app (capturing all system audio, playing fixtures with `afplay`): median ~590 ms, 6/6 languages correct,
  process `footprint` 453 MB.
- small's language detector confuses Ukrainian with Russian (uk phrase → ru 0.70–0.83). Solution: when choosing between uk
  and ru, the fragment is recognized in both languages and the variant with the higher mean token probability wins
  (a 0.07–0.24 margin for the correct language on fixtures). Language detection runs in a separate whisper state (full context).
- Hallucination protection on silence: fragments quieter than −55 dBFS are not recognized, output length is capped,
  repeated phrases are collapsed.
- turbo remains available as a model file (setting `whisperModel`) but is not used by default.

### Item 5, revision (H-4, 2026-10-07): **`medium` q5_0** instead of `small`
- On a live Meet call (phone → Mac) the audio is heavily compressed: even Chrome Live Caption produced nonsense; small erred
  in many phrases ("Почему решимся не керпотом" instead of "Почему решили сменить работу").
- Measured on fixtures re-encoded as AAC 8 kHz 12 kbit/s (simulated phone audio), language given, trimmed context:
  small — 4/4 with errors ("Просскажите", "бо зласька", "Описіть"), 0.19–0.28 s; **medium — 4/4 correct, 0.44–0.68 s**.
- Streaming run of medium on compressed audio: languages and texts 8/8 correct; "end of phrase → text" 0.84–1.06 s
  (median ~0.9 s). So that the final text does not wait for the language detector (~1.5 s on medium), the conversation
  language is remembered after two confident utterances and the detector is skipped until recognition confidence drops below 0.55.
- Memory: app `footprint` 1121 MB idle (small — 542 MB); the AC-05 threshold is 1536 MB — less headroom, checked on a call.
- small stays in `models.sha256` and can be selected with `whisperModel` when latency and memory matter more.

### Item 6 — embedding model (P-06, 2026-10-06): **bge-m3 Q8_0** (candidate 2), threshold **0.74**
- Candidate 1 `multilingual-e5-small` in GGUF exists only in third-party conversions (not an official repository) — under the
  threat model (downloads only from official sources) it is not used. GGUF files are taken from the `ggml-org` organization
  on Hugging Face (official llama.cpp conversions); checksums are in `models.sha256`.
- `embeddinggemma-2` (ggml-org) does not load in llama.cpp `b11446`: the `gemma-embedding2` architecture is not yet in any
  release XCFramework (`b11446`…`b11451`); building llama.cpp from source just for it was not done.
- The `bank` eval (51 cases: 39 paraphrases, 13 per uk/ru/en, and 12 out of the bank), `copilot-eval bank`:

| Model | Threshold | top-1 | uk / ru / en | False | top-3 | Query |
|---|---|---|---|---|---|---|
| embeddinggemma-300M Q8_0 | 0.74 | 89.7% | 10 / 12 / 13 of 13 | 0% | 100% | 12 ms |
| **bge-m3 Q8_0** | **0.74** | **94.9%** | 13 / 12 / 12 of 13 | **0%** | 100% | 22 ms |

- Holdout set (`evals/bank/holdout.jsonl`, 16 cases, not used for tuning): bge-m3 91.7% / 0% false,
  embeddinggemma-300M 91.7% / 25% false.
- The first run on the original bank (3 phrasings per card) gave bge-m3 84.6% — below AC-04. Three phrasings per card (one per
  language) were added to the example bank; there are no verbatim matches with the eval (checked by a script). The risk of
  fitting to the set is reduced by the holdout set but remains: the owner's bank should keep 2+ phrasings per language.
- Memory: app `footprint` with whisper small and bge-m3 — 542 MB (AC-05 ≤ 1.5 GB).
- whisper.cpp and llama.cpp are separate dynamic frameworks with their own ggml copies; there is no symbol conflict.
  So that ggml headers of two versions never meet in one Swift module, embeddings live in the `CopilotEmbeddings` target.
- Models are released explicitly before exit (`applicationWillTerminate`): otherwise ggml-metal crashes in static
  destructors (`copilot-eval exit-check`).

### Item 7 — language models (P-07…P-12)
- Raw HTTP + SSE without SDKs, as decided. Anthropic follows the `claude-api` skill: `thinking: between_tools` +
  `effort: low` for hints and the manual call (R-13), adaptive thinking for screenshots, `fallbacks: "default"`
  (`server-side-fallback-2026-07-01`), `cache_control` on the system part.
- Gemini: the `x-goog-api-key` header, `thinkingLevel: low` (retried without it if the model does not know the level).
  The fallback model of the same provider is `gemini-flash-lite-latest` (the main `gemini-3.8-flash` on a free key answered
  503/429/slower than 4 s). `ProviderHealth`: a model with a timeout/429/5xx goes to the end of the queue for 5 minutes.
- Any HTTP error moves to the next provider; 400/401/403 are not retried at that provider.

### Dependency summary
Only allowed ones: whisper.cpp XCFramework (`b5454`), llama.cpp XCFramework (`b11446`), Yams 6.2.2, Carbon.
Models: whisper medium q5_0 (default), small q5_1, large-v3-turbo q5_0 (not used by default), bge-m3 Q8_0 (default),
embeddinggemma-300M / -2 Q8_0 (candidates, not used) — from ggerganov/whisper.cpp and ggml-org, SHA256 in `models.sha256`.
No new dependencies outside the list.

## Consequences
- (+) Minimal memory, native behavior, access to every required system API.
- (+) Logic (`CopilotCore`) is separated from the UI and covered by `swift test` and evals.
- (−) Manual owner steps are needed: a signing certificate and macOS permissions, possibly Xcode.
- (−) Two native ggml libraries (whisper + llama) increase the app size. On a symbol conflict, llama.cpp may be replaced
  by the second candidate from item 6 or by Core ML embeddings — with an ADR entry.

## Review triggers
Revisit if:
- AC-05 (memory) or AC-01 (latency) are not met even on the fallback model;
- AC-04 < 85% on all embedding candidates;
- the owner decides to release the app to other users (notarization and auto-update would be needed).

### Amendment 2026-10-08: priority of local STT accuracy

At the owner's request, free local RU/UK/EN recognition on an M1 8 GB comes first.
Added FluidAudio 0.17.7 (MIT), exact version, Swift 6.2; default traits are disabled:
only Parakeet v3 is used, without Nemo text normalization and without cloud APIs.
Core ML models are downloaded by the installer and verified against the published Hugging Face LFS SHA256.
At runtime `ModelHub.offlineMode = true`. Reference FLEURS recordings are used only outside Git.
On the first 30 test recordings (10 per language, 575 words): medium reduced 9.39% WER,
turbo full 4.70%, Parakeet v3 4.52%. The sample is small; parity with parakeet-ai.com is not confirmed.
Both engines are available in Audio settings, one is loaded at a time. Parakeet is the new main option,
Whisper turbo with full context is the alternative, medium is the reserve when the new models are missing.
Final phrases are kept in the queue memory until processed, separately from the 30-second ring buffer;
user audio is never written to disk. This refines R-04 for audio retention.
AC-01 for the accurate mode requires a separate live measurement; the owner ranked accuracy above latency.

### Amendment 2026-10-23: Silero VAD model (COPILOT-05 R-02, R-08)
A new model without new packages: `FluidInference/silero-vad-coreml` (MIT), revision `b419383c55c1`, file
`silero-vad-unified-256ms-v6.2.1.mlmodelc` (~1 MB), SHA256 in `filter-models.json`, installed by `scripts/fetch-filter-models.py`.
Loaded directly (`VadManager(config:vadModel:)`), no downloads at runtime. It checks a closed utterance before recognition
(segmentation stays with the energy detector — the end of a phrase is not delayed); ~5 ms per utterance.
The language filter uses Apple NaturalLanguage (a system framework) + the share of Cyrillic/Latin letters.

### Amendment 2026-10-23: CAM++ model (COPILOT-05 R-03, R-08)
`FluidInference/campplus-coreml`, revision `321b18e270a4`, ~16 MB: a 192-number voice embedding (CPU/GPU, ~0.2 s per utterance).
A conversion of the FunASR / ModelScope model `iic/speech_campplus_sv_zh-cn_16k-common` (trained on Chinese speech; license —
upstream FunASR). Checked on synthetic uk/ru/en/de/fr voices: the owner's voice in another language is recognized equally well (0.88–0.95).
The alternative — WeSpeaker from FluidAudio diarization (VoxCeleb) — is postponed: fixed 10-second windows with diarization masks.
SHA256 — `filter-models.json`. The owner's voiceprint lives only in `…/InterviewCopilot/voice/owner.json`; sample audio is not stored.

### Amendment 2026-10-23: LocalVQE (COPILOT-05 R-04)
`FluidInference/localvqe-coreml` (Apache-2.0), revision `4205430781c2`, v1.3 with 4.8 M parameters, 256 ms and 16 ms variants
(~19 MB each), SHA256 — `filter-models.json`. Measured with `copilot-eval enhance`: with noise suppression Parakeet errs more often
(3.9% → 6.3% of words) — **off by default**, the setting is "experimental". The 16 ms variant is kept for streaming echo
cancellation on call audio (stage 4), which needs a reference signal; that decision depends on a separate measurement.
