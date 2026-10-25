# COPILOT-01: Test plan (for the next executor model and the owner)

Date: 2026-10-07 · Branch: `feat/copilot-01` · Requirements — [spec.md](spec.md), state — [report.md](report.md), log — [handoff.md](handoff.md).
The document is self-contained: a new session can start from it without reading the conversation.

## 1. Context in a minute
- A native macOS app (Swift 6, SwiftPM, no .xcodeproj): menu bar + floating panel. It listens to the other person
  in Meet/Zoom/Telegram (ScreenCaptureKit), transcribes locally (whisper.cpp, model **medium q5_0**), looks for the answer
  in the bank (**bge-m3** embeddings via llama.cpp, threshold 0.74), otherwise generates a hint (Gemini → fallback Gemini Flash-Lite →
  DeepSeek → Claude).
- Targets: `CopilotCore` (logic, tested), `CopilotEmbeddings` (llama.cpp), `InterviewCopilot` (AppKit/SwiftUI), `copilot-eval` (CLI).
- Data: `~/Library/Application Support/InterviewCopilot/` (profile/, models/, sessions/, cache/, usage.json). Keys — Keychain only
  (service `com.itmax04.interviewcopilot`). Settings — UserDefaults `com.itmax04.interviewcopilot`, key `settings.v1` (JSON).
- Project rules — `CLAUDE.md` (forbidden: force-push, reset --hard, merging into main, TCC/Keychain trust, keys in chat/code).

## 2. Environment and preparation
| What | How |
|---|---|
| Mac | Apple Silicon, macOS 15+ (checked: M1 8 GB, 15.7.2), **Xcode 26.3** (`xcode-select -p` → Xcode.app) |
| Certificate | "InterviewCopilot" (or "InterviewCopilot Dev") in the login keychain; `security find-identity -p codesigning` |
| Models | `scripts/fetch-models.sh` (≈ 1.7 GB: whisper medium, small, turbo, bge-m3, embeddinggemma — SHA256 check) |
| Permissions | Screen & System Audio Recording + Microphone for InterviewCopilot (granted **only by the owner**) |
| Gemini key | Entered by the owner in Settings → Keys. Never read or print the key value |

Environment quirks that already caused trouble:
- The repository is on the Desktop in **iCloud Drive**: `build-app.sh` signs the bundle in a temporary folder and copies it to `dist/`
  (otherwise codesign fails with "detritus not allowed"). Do not remove this.
- In zsh `log` is a builtin: use `/usr/bin/log`.
- Metrics are logged at the **notice** level (info lives only in memory).
- **Keychain:** after every rebuild the app asks once for access to the key (self-signed certificate) —
  the owner presses "Always Allow". While the dialog is open, generation waits. Do not rebuild needlessly during the owner's test.
- **The Gemini Free quota** is small: every `--smoke-llm` spends requests. Do not run live requests in a loop.
- The agent process has **no** Screen Recording permission: `screencapture` returns only the wallpaper, synthetic key presses do not work.
  Everything visual and the hotkeys are checked by the owner.
- Quit the app before `scripts/build-app.sh` (`pkill -x InterviewCopilot`): replacing the bundle of a running process
  breaks the signature on the fly.

## 3. Automatic checks (run after any change)
```bash
swift build && swift test
scripts/run-evals.sh            # turn + bank, thresholds from evals/README.md
scripts/secret-scan.sh          # 0 findings is mandatory before a push
scripts/build-app.sh            # dist/InterviewCopilot.app, Authority=InterviewCopilot
```
Expected on 2026-10-07: 143 tests PASS; turn 36 cases 0%/0%; bank 94.9% / 0% false; secret-scan 0.
Additionally:
- `copilot-eval bank evals/bank/holdout.jsonl` — the holdout set (do not tune the threshold to it): 91.7% / 0%.
- `copilot-eval stt-stream <model> <wav…> [--lang xx] [--gain 0.03] [--prompt-bank]` — real-time streaming recognition,
  median "end of phrase → text".
- `copilot-eval exit-check` — exit after releasing the models without a ggml-metal crash.
- Clean clone (AC-14): `git clone -b feat/copilot-01 … && swift build && swift test && scripts/build-app.sh`.

## 4. Live checks by the executor (without the owner)
| Check | Command | Expected |
|---|---|---|
| Gemini key/models/stream | `dist/InterviewCopilot.app/Contents/MacOS/InterviewCopilot --smoke-llm` | `models=… present=true`, `stream OK`, `chain: … done` (≤ 3 requests) |
| Screenshot → model | `… --smoke-screenshot evals/fixtures/two-sum.png` | JPEG 1600×1000, an answer with a code block and O(…) |
| Pipeline audio → text → turn → card | In the app settings the source "All system audio" (JSON `settings.v1`, field `audioSource`), launch the app, play `afplay evals/audio/*.wav` | In `/usr/bin/log show --predicate 'subsystem == "com.itmax04.interviewcopilot"'`: `transcript_final`, `turn_end`, `bank_match matched=true`, `card_shown`. **Restore `audioSource` to `{"auto":{}}`** |
| Memory | `scripts/footprint-monitor.sh 10` | Maximum ≤ 1536 MB (was 1119 MB) |
| Metrics | `scripts/metrics.py --last 30m` | AC-01…AC-03 table |

Note: with "All system audio" any system sound (a video in Safari, etc.) gets into the measurement — phrases get split.

## 5. What remains to check (priority from top to bottom)
1. **AC-10, uk/ru/en accuracy on a call.** Script — `evals/live-script.md`. Run two series: (a) Language = Auto,
   (b) Language chosen explicitly. Better with the other person on a laptop/headset, the phone not in the same room as the Mac.
   The owner assesses "understandable ≥ 4 of 5" per language. English questions 11–15 have not been read live yet.
2. **AC-09, hotkeys while Chrome is active:** ⌃⌥H (the panel disappears/appears, the cursor stays in the address bar),
   ⌃⌥↩ (answer immediately), ⌃⌥S (solution from a screenshot), ⌃⌥P (pause: status Paused, nothing goes to the model), ⌃⌥C
   (without an Anthropic key the "↑ Claude" button is disabled with the hint "No Anthropic key").
3. **AC-13, without permission:** the owner turns off InterviewCopilot in Privacy → Screen & System Audio Recording and
   launches the app: a red dot in the menu, the panel "No permission… Open System Settings", the permissions window/wizard,
   no crash. Then turn it back on (restart).
4. **AC-07 manually:** temporarily enter a deliberately invalid Gemini key in Settings → Keys → "Check" shows
   "Invalid key"; on an out-of-bank turn — "Models unavailable: …" and the top 3 (no fallback keys). Restore the correct key.
5. **DeepSeek and Anthropic live** — only once the owner adds keys: `--smoke-llm`, then ⌃⌥C; check the actual model label
   and `usage.json` (cost, monthly limit).
6. **AC-05 under load:** 10 minutes of a call with speech + `scripts/footprint-monitor.sh 10`.
7. **S-09, the first-run wizard on a "clean" profile:** rename `~/Library/Application Support/InterviewCopilot/models`
   (only with the owner's consent — 1.7 GB to download again) and check the download with progress and SHA256; or check on another account.
8. **S-10:** editing `profile/questions.yaml` with an error → the menu shows "Question bank: error on line N", the previous bank keeps working;
   fix it → the card count updates (already checked via logs, needs a visual look).
9. **"Microphone (practice, no call)" mode:** Listening → Microphone; ask bank and non-bank questions into the Mac microphone;
   expect a transcript and an answer; switching back to Auto restores Chrome capture and owner-speech detection.
10. **R-19 history window:** "Session history…" — list, view, delete one and all.

## 6. Known weak spots (where to look on errors)
| Symptom | Where | What is known |
|---|---|---|
| Inaccurate text | `STT/WhisperEngine.swift`, `STT/StreamingTranscriber.swift` | Compressed Meet audio. The Settings → Audio option "Prompt recognition with phrasings from the bank" (initial prompt) has a mixed effect and is off. The context of previous lines in the prompt broke the output — removed |
| Wrong language uk ↔ ru | `resolveLanguage` in `StreamingTranscriber` | Whisper's detector is unreliable on the first ~1.2 s; uk/ru are compared by mean token probability; the "conversation language" after 2 confident lines skips the detector (~1.5 s on medium, not interruptible) |
| Phrase final > 1 s | same | The final waits for the non-interruptible language detector if the phrase ended during it. An explicit language in the menu removes the delay |
| No hint arrives | `LLM/ProviderChain.swift` | `ProviderHealth`: a model with a timeout/429/5xx goes to the end of the queue for 5 minutes. Gemini Free quota |
| Auto-answer does not fire | `Turns/TurnDetector.swift` | The owner is "speaking" (microphone, threshold −36 dBFS); speaker echo is filtered (150 ms after and 500 ms before the other person's speech). Log: `mic_db`, `owner_speaking` |
| Quiet other person | `StreamingTranscriber.Config.vad` | VAD −62 dBFS + noise+10 dB; gain up to a 0.5 peak (≤ ×40) |
| Keychain dialog | — | Self-signed certificate; "Always Allow" after every rebuild |

## 7. Owner acceptance (H-5), ≈ 15 minutes
1. Launch `dist/InterviewCopilot.app` (if the Keychain asks — "Always Allow"; the wizard — everything green → "Done").
2. The parrot menu looks like `docs/design/menu-v2.webp` (⌃⌥ instead of ⌘, "Practice mode … soon", the line "Today: $… · Gemini: N req"). — AC-11
3. Meet in Chrome, the other person asks 3 bank questions and 2 outside the bank: the card "Bank · … · NN%" or "Gemini · generated". — AC-08
4. While Chrome is active: ⌃⌥H twice, ⌃⌥↩, ⌃⌥S, ⌃⌥P twice. — AC-09, S-06, S-08
5. "Session history…": the session is there and can be deleted. — AC-12
6. A decision on AC-10 (accuracy) and NOT RUN (DeepSeek/Anthropic, English live, AC-13 visually).

## 8. If development continues
- New requirements — a new intent (`docs/changes/COPILOT-02/`); this set is closed by the report.
- Candidates: more accurate recognition (cloud STT with the owner's consent or large-v3-turbo with relaxed AC-01/AC-05),
  a training mode ("soon" in the menu), multiple profiles, hiding the panel from screen sharing (Q3 — currently "no").
- Do not weaken tests and eval thresholds; new dependencies — only with an ADR-0001 entry and the note "requires owner confirmation".

## Local STT v0.1.1 — H-4

1. Close the old copy, open the new one. Mode → Question bank only for a test without generation.
2. Audio → Parakeet v3, Microphone, Auto. Wait for the "model ready" status.
3. Five phrases each in UK/RU/EN: a regular question, a negation, a number/version, names/terms, a long question.
4. Repeat with a real call source and assess the final text (the partial may change).
5. On the same phrases choose Whisper large-v3-turbo, "Accurate final text", a known language.
6. Record omissions/substitutions, changes of meaning, latency and memory. Compare with the service only on identical audio;
   quality cannot be assumed equal from the model name.
7. Monologues > 25 s and language mixing inside a phrase are separate unverified cases until a live measurement.
   Do not write user audio to disk and do not commit it.
