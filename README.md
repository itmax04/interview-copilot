# Interview Copilot

A personal macOS app (menu bar + floating overlay) that listens to the other person in Google Meet, Zoom or Telegram,
transcribes speech locally (Ukrainian, Russian, English), finds the question in the owner's prepared answer bank and
shows the answer. If the question is not in the bank (or in "No profile" mode), it generates a hint through the chain
Groq → Cerebras → Gemini → DeepSeek → Claude → custom API; the first words appear about one second after the question.
It filters out noise, foreign-language chatter and other voices, remembers the whole interview, sends a screenshot of
a coding task to a strong model on a hotkey, and reviews the call afterwards. There is one user — the owner; the app is
not distributed.

Status: **0.15.1** (COPILOT-12: final review, fixes, English documentation) — see
[docs/changes/COPILOT-12/handoff.md](docs/changes/COPILOT-12/handoff.md).

**New developer or AI agent? Start with [AGENTS.md](AGENTS.md)**, then [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Requirements
- Apple Silicon Mac, macOS 15+ (tested on an M1 with 8 GB, macOS 15.7).
- Xcode 26+ (tests do not run with the Command Line Tools alone): `sudo xcode-select -s /Applications/Xcode.app`.
- A code-signing certificate named "InterviewCopilot" or "InterviewCopilot Dev" in the Keychain (self-signed, "Code Signing").
- ≥ 3 GB of free disk space for models.
- A Groq or Gemini API key (free tiers). Cerebras, DeepSeek, Anthropic and a custom OpenAI-compatible API are optional.
- Memory during a call: about 1.1–1.2 GB.

## Quick start
```bash
scripts/fetch-parakeet.py      # local Parakeet v3, pinned version and SHA256
scripts/fetch-models.sh        # Whisper and embedding models, SHA256 check (or use the first-run wizard)
scripts/fetch-filter-models.py # Silero, CAM++ (voiceprint), LocalVQE — speech filters
scripts/build-app.sh           # build and sign dist/InterviewCopilot.app
open dist/InterviewCopilot.app # parrot in the menu bar; overlay — ⌃⌥H
```
First launch: the wizard walks through permissions → a free Groq key → models. "Screen & System Audio Recording" and
"Microphone" are granted manually in System Settings. After a rebuild macOS asks once for Keychain access to the key —
choose "Always Allow".

## Using the app
- **No session — no listening.** "New session…" (⌃⌥N, menu, main window or overlay): call type (Interview / Regular call /
  AI interview), profile, job posting (text or link), audio source, language, model, session instructions, auto-answer,
  transcript saving, planned duration → a pre-start check of the microphone, call audio, recognition and keys →
  "Start session". "End" is in the overlay and the menu. When a call starts, the overlay offers to start a session.
- **Audio source**: Auto (Zoom → Chrome → Telegram), a specific app, all system audio, or **Mac microphone (self-check)** —
  you speak into the Mac microphone yourself, without a call, to practise and test.
- **Test call…**: a local browser tab with 15 RU/UK/EN phrases, text comparison, highlighted errors, latency and a JSON
  report. Real browser audio capture is used; answer generation and history are off. Run only the free test with
  `open -n dist/InterviewCopilot.app --args --test-call` (quit the running instance first).
- **AI interview**: the model asks questions by voice in the browser, you answer into the microphone, hints work as on a
  real call, and a review follows.
- **Mode**: Question bank only / Bank + hint / Generate every answer.
- **Settings → Audio & recognition**: Parakeet v3 (main local engine) or Whisper (large-v3-turbo, "Accurate final text");
  switching needs no restart. **Call language**: Auto (UK/RU/EN) or a fixed language.
- **Profiles** (main window → Profiles, or launch with `--args --profile`): one profile per job search with résumé,
  facts about you, job posting (PDF, Word, RTF, TXT, Markdown or pasted text), profile and general instructions,
  **Materials** (notes and documentation; 3–4 matching chunks go into each request) and **Questions** (sample questions
  and your answers: import a file in any form with ⌘I, edit in a table, "Prepare" adds uk/ru/en phrasings and draft
  answers, "Delete all…" clears the list). During the interview the model adapts your answer to the actual wording.
- **Answer style**: format (gist + bullets / bullets only / plain text), length (up to 40 / 80 / 150 words) and tone, with
  a live preview on your profile. Default in Settings → Models & answers; per call in the session wizard. Your
  instructions take priority.
- **Overlay**: microphone and call levels, "Can't hear the call for N s", status "Checking / Question detected / Not a
  question", the answer card with history ← 3 / 7 →, answer versions and "Shorter / More detail / Example"; chat for a
  typed question, a refinement or an instruction for the whole session. The ⋯ menu has auto-answer, language, zoom,
  next screen, "Hide during screen sharing" and an honest "Check visibility". **Resize** by dragging any edge or corner
  (grip in the bottom-right corner); width 280–1000 pt is remembered.
- **Screenshot task** (⇧⌘↩ during a session, ⌃⌥S): a strong model solves the task; screenshots within 30 s join the same
  task (up to 3). While the task is active, short voice follow-ups ("And the complexity?") are answered about it.
- **Review after "End"** (can be turned off in the wizard): a comment on each of your answers (what worked, what was
  missing, how to say it better), a summary (agreements for a regular call) and "Ask AI" about the call. Session history
  is in the main window → Sessions.
- **Your voice** (Settings → Audio & recognition): a 25-second voice sample; in microphone mode other voices and TV are grayed out.
- **Multiple keys per provider** (Settings → Model keys → "Another key — from another account", unlimited): all keys of a
  provider are tried in turn; a rate-limited key waits for its reset (`retry-after`, "try again in…", daily limits —
  hours); only when all keys are limited does the next provider answer. If everything fails, the "last resort" waits up
  to 25 s for the nearest key reset and gives slow models more time instead of showing "Models unavailable".
- **Theme and language** (Settings → General, onboarding, bottom of the main window sidebar): System / Light / Dark and
  System / Русский / English, applied instantly. The call overlay is always dark. Review and "Ask AI" use the UI
  language; live hints use the interviewer's language.
- **Hotkeys** (Settings → Hotkeys): ⌃⌥↩ answer now (also for a gray line), ⌃⌥S screenshot, ⌃⌥H overlay, ⌃⌥P pause,
  ⌃⌥C strong model, ⌃⌥A "I'm answering now" (self-check), ⌃⌥N session, ⌃⌥Space chat, ⌃⌥⌫ clear transcript,
  ⌃⌥← / ⌃⌥→ previous / next answer. **During a session only** (ParakeetAI scheme): ⌘↩ answer, ⇧⌘↩ screenshot,
  ⇧⌘Space chat, ⇧⌘⌫ clear, ⌘← / ⌘→ history.

## Verification
- Quick: `swift build && swift test`.
- Full: `swift test && scripts/run-evals.sh && scripts/secret-scan.sh && scripts/check-localization.sh && scripts/build-app.sh`.
- UI translations: `scripts/check-localization.sh` — every UI string has an English translation with matching formats.
- Evals: `scripts/run-evals.sh [bank|turn|filter-text|memory|materials|filter|voice]` — thresholds and baselines in [evals/README.md](evals/README.md).
- Call metrics: `scripts/metrics.py --last 30m`; memory: `scripts/footprint-monitor.sh 10`.
- Live checks from the signed app (spend free quota): `--smoke-llm`, `--smoke-memory [N]`, `--smoke-screenshot evals/fixtures/two-sum.png`,
  `--smoke-task`, `--smoke-session`, `--smoke-review`, `--smoke-prepare`; UI without audio: `--ui-snapshots <dir>`.
- CLI: `swift run -c release copilot-eval <stt|stt-parakeet|stt-hybrid|stt-stream|turn|bank|filter-text|filter|voice|voice-enroll|enhance|memory|exit-check>`.

## Repository layout
- `Sources/CopilotCore/` — logic: `Audio/`, `STT/`, `Filter/`, `Turns/`, `Bank/`, `Profiles/`, `LLM/`, `Memory/`, `Answer/`,
  `Review/`, `Session/`, `Interviewer/`, `TestCall/`, `Localization/`, `Privacy/`, `Capture/`, `Storage/`, `Usage/`,
  `Hotkeys/`, `Menu/`, `Models/`, `Settings/`, `Secrets/`, `Logging/`.
- `Sources/CopilotEmbeddings/` — embeddings via llama.cpp (separate from whisper because of ggml headers).
- `Sources/InterviewCopilot/` — the app: menu bar, overlay, main window, settings, wizard, history.
- `Sources/copilot-eval/` — CLI for evals and measurements.
- `Tests/CopilotCoreTests/` — tests and recorded provider streams.
- `scripts/` — build, models, evals, secret scan, localization check, metrics, fixtures.
- `profile.example/` — a fictional candidate profile (synthetic; Russian/Ukrainian content used by tests and evals).
- `evals/` — bank/turn/filter/memory/materials datasets, audio and screenshot fixtures, the live-call script.
- `docs/` — [ARCHITECTURE.md](docs/ARCHITECTURE.md), design, ADRs, tasks `changes/COPILOT-01…12` (intent, spec, plan, handoff).

## Limitations and security
- API keys live only in the macOS Keychain — never in code, logs, chat or Git (`scripts/secret-scan.sh`).
- Personal profiles and session history live in `~/Library/Application Support/InterviewCopilot/` and never enter Git.
- No audio is written to disk (≤ 30 s ring buffer in memory); only session text is saved, with configurable retention.
- Logs contain events and latencies only, never utterance or answer text.
- Transcription accuracy depends on audio quality: compressed Meet audio from a phone is recognized worse.
- Private repository: `itmax04/interview-copilot`. Licensed under the [MIT License](LICENSE).
