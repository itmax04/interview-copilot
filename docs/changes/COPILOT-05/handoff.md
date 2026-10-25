# COPILOT-05 handoff

ID: COPILOT-05-handoff · Status: **stages 1–4 done (0.2.6) — awaiting a live call test (H-2)** · Updated: 2026-10-23
Branch: `feat/copilot-05-speech-filter` (from `feat/copilot-04-instant-answers` @ `f7e3f94`)
Links: [intent.md](intent.md), [spec.md](spec.md), [plan.md](plan.md)

## Done
- 2026-10-23: a brainstorm with the owner (Q1–Q16 in intent.md), the intent/spec/plan documents. No code changed.
- Checked in FluidAudio 0.17.7 (`.build/checkouts/FluidAudio`): `VadManager` — Silero, 4096-sample chunks (256 ms),
  a streaming API; `CampPlusEmbedder` — a 192-number embedding, cosine similarity; `LocalVqeManager` — AEC + noise suppression,
  v1.3 with 4.8 M parameters, the `.realtime16ms` mode, beta.

- 2026-10-23: H-0 passed ("yes, I accept, start the first stage"), statuses → accepted.
- Stage 1 (P-00…P-03), version 0.2.0 (build 13):
  - `LanguageGate` + `TermDictionary` + a built-in IT list (`Sources/CopilotCore/Filter/`), gray lines in the panel,
    ⌃⌥↩ / a click on a gray line (S-08), the log `filtered reason=lang|vad`.
  - `SileroSpeechGate`: Silero checks a closed utterance before recognition; `filter-models.json`,
    `scripts/fetch-filter-models.py` (the model is installed at the owner's, 5 files verified by SHA256).
  - Settings → Audio: "Language filter", "Neural speech detector".
  - The set and the `filter` eval (`scripts/make-filter-fixtures.py`, `evals/filter/`), `filter-text` in the default run.

## Executor decisions
- R-02: Silero does not replace the energy detector but checks a closed utterance: Silero's step is 256 ms, segmenting with it
  would delay the end of a phrase (the COPILOT-04 goal). The effect is the same — noise without speech is not recognized.
- R-05: the built-in IT list is a Swift array (`BuiltinTerms.swift`), not `Resources/terms-en.txt`: CopilotCore has no resources.
- R-05: the "≤ 4 words" limit counts only significant words ("pull request and code review" — 4 terms).
- R-06: filters are off in the test call — it measures recognition itself.
- A filtered utterance counts for turn detection as discarded noise (`.discarded`); the Whisper refinement does not bring it back.

## Current step
H-1 — the owner spends 5 minutes with a TV in another language in the "Mac microphone" mode (instructions — in the session message).

## Checks
| Step | Command | Result |
|---|---|---|
| P-00 | `swift test`, evals (before changes) | 201 tests PASS; turn 0%/0% (596 ms); bank 94.9% / 0% |
| P-01…P-03 | `swift test` | 212 tests PASS (+11: language filter, dictionary, answering a gray line, speech check, Silero on the real model) |
| P-01 | `scripts/run-evals.sh` | turn 0%/0%; bank 94.9%/0%; filter-text 214/214 |
| P-01 | `scripts/run-evals.sh filter` without filters | foreign language 0/16, lost 0/20, noise 0/20 |
| P-03 | `scripts/run-evals.sh filter` | foreign language **16/16**, lost 1/20 (5%), terms kept 8/8, noise 0/20, Silero ~5 ms — PASS |

## H-1, first live test (2026-10-23 21:20, v0.2.0, "Mac microphone", Українська)
Owner: "the text generates random words by itself" (the panel showed "Дякую!", "Відкарман"). Log (numbers only):
- the owner's engine was again **Whisper medium** (`recognitionBackend = whisper`): final ~1.3 s, Whisper invents words on noise;
- room noise at the microphone −46…−58 dBFS opened utterances: the −62 dBFS detector threshold was tuned for quiet Meet audio;
- Silero cut 8 short segments, but several (0.66–1.2 s) passed and became words.
Fixed in 0.2.1 (build 14): the threshold for the "Mac microphone" source is −45 dBFS (`StreamingTranscriber.microphoneVAD`);
Silero counts speech from 2 chunks (≈ 0.5 s) or one with confidence ≥ 0.9; `HallucinationFilter` — known Whisper
subtitle endings in utterances ≤ 2.5 s are dropped (`filtered reason=hallucination`).
Checks: 214 tests PASS; the filter eval unchanged (16/16, lost 1/20, terms 8/8, noise 0/20); turn/bank/filter-text PASS.
Recommendations to the owner: Parakeet instead of Whisper; the system microphone mode "Voice Isolation" (Control Center) is available
for InterviewCopilot — it suppresses background voices and noise at the macOS level.

## H-1, second test (21:31, v0.2.1, Whisper medium + "Українська")
An English video from a phone — Ukrainian phrases in the panel. Log: all finals `lang=uk`; Whisper with a set language writes
any speech in the selected language, so the language filter sees "Ukrainian" text. The Whisper queue lagged up to 9 s.
Conclusion: the language filter needs recognition without an imposed language — Parakeet (eval: 16/16). A warning was added in Audio
for Whisper + a selected language + the filter (0.2.2, build 15).

## Stage 2 (P-04): voiceprint, version 0.2.3 (build 16)
- `VoicePrint` (print + personal threshold), `VoiceEmbedder` (CAM++), `VoiceGateBox`; a `.foreignVoice` event instead of
  `final` — a gray line "other voice 0.xx"; the check is on in "Mac microphone" and for the answer in the AI interview.
- Settings → Audio → "Your voice": recording a 25 s sample (text in the interview language, Enter — start/stop), deletion,
  an automatic threshold or a 0.50–0.90 slider. CAM++ is installed at the owner's (8 files verified by SHA256).
- Executor decisions: a personal threshold (calibrated on chunks of the sample) — a synthetic "own" voice is unnaturally stable;
  the voice is checked after recognition (the text is needed for the gray line), +~0.2 s to the final only in microphone mode.
- Checks: 220 tests PASS (+6, incl. CAM++ on the real model); the voice eval — own 18/18, others 89/96 (93%) — PASS;
  filter, filter-text, turn, bank — unchanged.

## Live voice test (2026-10-23 22:31, v0.2.3, sample from the owner's file)
- Sample: the owner's 49 s voice recording (Ogg Opus, probably a phone) → `copilot-eval voice-enroll`: 27.5 s of speech,
  spread 0.87, automatic threshold 0.79. The temporary audio copy was deleted, the print — `voice/owner.json` (permissions 600).
- Log: video 0.49 / 0.49; the owner 0.67 / 0.67 / 0.73 — **rejected** (threshold 0.79): the sample was recorded with another microphone.
  Short video utterances (< 1 s, "До свидания") were not checked and added up to a turn.
- Fixed in 0.2.4 (build 17): short utterances from 0.5 s of speech are checked with the threshold −0.1; the similarity of accepted
  ones is logged too (`voice_ok`). Recommendation: re-record the sample through the Mac microphone (Settings → Audio) or a manual threshold ~0.6.

## Stage 3 (P-05): noise suppression, version 0.2.5 (build 18)
- LocalVQE v1.3 installed (8 files verified by SHA256); `SpeechEnhancer`, `EnhancerBox`, cleaning a closed utterance
  before recognition and the voice check (`StreamingTranscriber.setAudioEnhancer`), microphone channel only.
- The `enhance` eval (50 phrases): Parakeet 3.9% → with LocalVQE 6.3% errors — worse on all noises. Per the plan (risks): off by
  default, an "experimental" toggle in Audio → "Your voice" with a note about the measurement; for noise — macOS Voice Isolation.
- Executor decision: echo cancellation (needs a time-aligned call reference signal) — at stage 4 together with
  transcribing the microphone during a call; in the "Mac microphone" mode there is no reference signal.
- Checks: 222 tests PASS (two runs); memory on a live call — NOT RUN (the owner closed the app), AC-06 — at H-2.

## Stage 4 (P-06): the owner's speech as context, version 0.2.6 (build 19)
- A second recognizer for the microphone on a call (the source is the call app or all system audio): the same engine,
  without interim text and without the Whisper refinement (`Config.allowRevision = false`), the −45 dBFS microphone threshold, Silero.
- The voiceprint checks every phrase (`VoiceGateBox.check(ignoringActive:)`): other voices and the interviewer's echo from
  the speakers are cut. Without a sample: the microphone language filter + a timing echo rule (a phrase that ended during speech
  in the call or within 1.5 s after it is not used).
- `CandidateContext`: up to 3 phrases within 3 minutes, ≤ 600 characters, memory only; a `<candidate_said>` block in the prompt (data,
  PII filter), a rule in the system part. The owner's speech is not in the panel or history (Q6). A setting "Use my answers".
- Found and fixed: gray (filtered) transcript lines also went into the prompt — now only lines that passed the filters.
- Executor decision (R-04): streaming LocalVQE echo cancellation on the call audio is not enabled — the voiceprint and the timing rule
  cut the echo, and LocalVQE worsened recognition on the `enhance` eval; the 16 ms model is installed for a future measurement.
- Checks: 225 tests PASS; turn/bank/filter-text unchanged. NOT RUN: a live call (question latency AC-05
  with simultaneous speech, memory AC-06) — H-2.

## Observations
- On synthetic noise Parakeet produces no text even without Silero (0/20): Silero's gain is not visible on this set;
  "Угу/Yeah" on noise was seen on live calls (COPILOT-03) — checked at H-1.
- Parakeet writes terms in synthetic uk/ru questions in Cyrillic (the voices pronounce them "in Russian"): Latin script in the text
  3/8 — that is recognition, not the filter; the filter does not drop them (8/8). The Whisper refinement (03/R-37) and COPILOT-02 help.
- The only loss: Parakeet recognized a Ukrainian question over music as Polish nonsense — the filter cut it.
  The gray line can be clicked or ⌃⌥↩ pressed (S-08).
