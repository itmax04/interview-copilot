# COPILOT-03: Handoff — AI interview

Branch: `feat/copilot-03-ai-interviewer` (from `feat/copilot-01`, `3b690fc`) · App version 0.1.5 (build 6) · Date: 2026-10-22
Links: [intent.md](intent.md), [spec.md](spec.md)

## Done
- `CopilotCore/Interviewer/`: `InterviewerPrompt` (R-31), `SpeechSynth` + `WAVEncoder` (R-30), `AnswerCapture`
  and `InterviewTurnRecord` (R-32, R-33). `TestCallClip` got a public initializer.
- `InterviewCopilot/InterviewerController.swift` — the page server (on `LocalTestCallServer`), the interview flow,
  a question as a `TestCallTrial` with the model's text as the reference.
- `ListeningController`: `AudioRoute`/`AudioRouteBox` (one source in recognition), `beginInterviewCapture`,
  `setInterviewRoute`, `endInterviewCapture`, `onOwnerTranscript`.
- Fixed along the way (found while testing on 2026-10-22): if Chrome had just been launched, ScreenCaptureKit did not see it
  yet — capture failed with "not running" and was not retried. Now up to 8 retries every 0.5 s, and on failure
  `source = .none`, so that a later app launch turns capture back on.
- Menu: "AI interview…" (`MenuAction.aiInterview`); the launch flag `--ai-interview` opens the page immediately.
- `Resources/Interviewer/index.html`, copied in `scripts/build-app.sh`.

## Executor decisions
- One recognizer instead of two: sources are switched by a route. Two `StreamingTranscriber`s on one
  `ParakeetEngine` would cancel each other's passes (`cancel()` is shared by the engine).
- The voice is a WAV in a Chrome tab, not the browser's `speechSynthesis`: macOS system synthesis plays audio from its own
  process, and the Chrome capture filter would not hear it.
- The question goes into the normal turn and hint pipeline — that is the "as on a call" check. The owner's answer does not.
- The first-token timeout for a question is 20 s: under Gemini overload 4 s was not enough (503 and a fallback model timeout).

## Checks
| Check | Result |
|---|---|
| `swift build` | PASS |
| `swift test` | PASS — 165 tests in 24 suites (new: 8 in "AI interviewer — COPILOT-03", menu) |
| `scripts/build-app.sh` | PASS, `Authority=InterviewCopilot` |
| Live API run: start → Gemini question (ru) → WAV 10.3 s 22 kHz → stop | PASS (the first question took 27 s due to Gemini overload) |
| Playback in the tab, recognizing the question through capture, answering into the microphone | NOT RUN — needs the owner's click in Chrome (autoplay policy) |

## R-35: Ukrainian final via Whisper (2026-10-23)
Owner complaint: Parakeet "merges" Ukrainian speech into Russian. `HybridRecognizer` (Parakeet + Whisper turbo `uk`),
the hook `SpeechRecognizer.transcribeFinal`, the setting `ukrainianWhisperFinal` (Settings → Audio), the mode `copilot-eval stt-hybrid`.
Measurement (final text from files, M1 8 GB; FLEURS — 10 human uk recordings from benchmark-human, outside Git; call — 5 synthetic uk):

| Configuration | FLEURS uk | Call uk | Russian letters in Ukrainian text | Phrase final |
|---|---:|---:|---:|---:|
| Parakeet | 4.71% | 8.25% | 0 | ~150 ms |
| Hybrid, Auto | 7.65% | 4.12% | 0 | ~2.4 s |
| Hybrid, "Українська" | 7.65% | 4.12% | 0 | ~2.4 s |
| Whisper turbo `uk` | 7.65% | 4.12% | 0 | ~2.3 s |
| Russian FLEURS: Parakeet / hybrid Auto | 4.12% / 4.12% | — | — | the hybrid does not trigger |

On clean FLEURS speech no model drifts; Whisper's difference is mostly normalization ("км" → "кілометрів",
joined spelling of names). On the call Whisper is better on terms. The drift the owner sees does not reproduce on these
data — it has to be checked on the owner's voice (AC-35). If the drift is complete and the text has no і/ї/є/ґ,
the hybrid does not trigger in Auto: for a Ukrainian interview choose Language → "Українська".

## R-36…R-39 (2026-10-23): fast models, instant hints, noise, capture
Owner request: do items 1–4 (capture, 0 hints, Gemini 503 → Groq/Cerebras, COPILOT-02) and make the models
"switch automatically and answer immediately".
- Groq/Cerebras: IDs and limits from the official documentation on 2026-10-23 (console.groq.com/docs/models, /rate-limits,
  inference-docs.cerebras.ai/models/overview, /support/rate-limits). Llama models were removed from free Groq; Cerebras
  has no permanent free tier ($5 for 30 days with a card). Keys are entered by the owner (Settings → Keys).
- Parallel requests — `ProviderChain.runHedged`; the sequential mode and its tests are unchanged.
- The cause of "0 hints in 2 h" could not be established from the saved logs (the info log is not kept). A mechanism that
  explains it was found and fixed: after a question a noise fragment without text produced no final, and the turn waited for it until
  the next non-empty phrase. Added `discarded`, timeouts and the `turn_stall` diagnostics.
- The 11:00 session showed a turn delay of ≈2.6 s because of the Ukrainian Whisper final (R-35) — removed by the two-stage final:
  `copilot-eval stt-stream … --hybrid`: fast final 501–516 ms, refined 2.8–3.4 s
  ("поуст Грескл, Редіс і Qbornec" → "PostgreSQL, Redis і QBornids").
- COPILOT-02: terms — via Whisper refinement (R-37); long phrases — synthetic 18–20 s uk/ru: 0 errors for Parakeet
  and Whisper (chunk joining did not show up on them); noise filter — partially (R-38: empty finals), "Yeah." on noise remains.
- Checks: `swift test` 184 tests PASS; turn eval 36 cases 0%/0%, bank 94.9% / 0%; secret scan 0.
- NOT RUN: live requests to Groq/Cerebras (no keys), capture restart on a real stream stop.

## R-40 (2026-10-23): answers without a profile
Owner request (a screenshot of the Profile menu): the model must answer regardless of the profile and by itself, without hints.
The owner chose both options: a "No profile" item and free technical answers with a profile.
- The cause of the old behavior — the prompt rule "Use only facts from the candidate profile… write [уточнить]".
- `PromptBuilder.system(profile: Profile?)`: without a profile — a separate prompt without `<profile>`; with a profile — technical
  questions from the model's knowledge, "[уточнить]" only for personal facts.
- `AnswerRouter.decide(…, useProfile:)`: without a profile the bank is not used in any mode; `AnswerController` does not search
  the bank and does not pass cards (also for ⌃⌥C); the AI interview gets an empty profile.
- `AppSettings.useProfile` (true by default, old settings load without a migration), a Profile menu with the choice.
- Checks: `swift build` PASS; `swift test` 189 tests PASS (+5); turn eval 36 cases 0%/0%, bank 94.9% / 0%;
  secret scan 0 findings. Version 0.1.6 (build 7).
- NOT RUN: a live model answer in "No profile" mode (owner check, AC-36).

## Known limitations
- Gemini Free is overloaded (503, slow first token): a question may take 10–30 s to prepare.
- The PII filter (R-12) does not detect phones with a different digit grouping, for example a German number "+49 151 …" with eight digits in a row (an existing `PIIFilter` limitation).
- The interviewer voice is synthetic: question accuracy is not the accuracy on a live interviewer; the live voice is measured by correcting answers.

## Next step
Owner: a run of 5–6 questions in each language, correcting 2–3 answers, a JSON report. Pushing the branch and a PR — only on the owner's command.
