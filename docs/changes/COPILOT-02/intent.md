# COPILOT-02: Intent — Parakeet v3 accuracy on real questions

ID: COPILOT-02-intent · Status: **draft** · Version: 1 · Date: 2026-10-22
Result owner: itmax04 · Links: [spec.md](spec.md), [plan.md](plan.md), [executor-prompt.md](executor-prompt.md),
[handoff.md](handoff.md), [ADR-0001](../../decisions/ADR-0001-stack.md) (the "Refinement 2026-10-08" section),
previous task — [COPILOT-01](../COPILOT-01/report.md)
Source: a review of the Parakeet v3 integration in a Claude Code session on 2026-10-22 (branch `feat/copilot-01`, commit `3b690fc`,
FluidAudio 0.17.7). No code was changed during the review.

> Repository note (COPILOT-12): this task stayed a draft on the separate branch `docs/copilot-02` and was never merged into the
> task chain; its goals were taken over by COPILOT-03 (the Whisper refinement, the hybrid engine) and COPILOT-05 (Silero, filters).
> The English translation is kept here so the task history in `main` is complete.

## Problem
Since v0.1.1 the main recognition engine is Parakeet v3 (FluidAudio, Core ML). On short synthetic phrases it is accurate
(test call v0.1.2: raw WER RU 7.29%, UK 9.28%, EN 3.25%), but the review found places where accuracy in a real
interview has not been checked or is already lost:

1. **Long questions are not checked.** Parakeet processes ≤ 15 s of audio in one pass
   (`ASRConstants.maxModelSamples = 240_000`), while an utterance can last up to 25 s
   (`StreamingTranscriber.swift:47`). Phrases of 15–25 s are cut into pieces and glued together. According to the FluidAudio documentation
   (`Documentation/ASR/LongTranscription.md`) the joins are the main source of errors: dropped words,
   repeats, bursts of text in the wrong alphabet with v3. All 15 phrases of the test call are shorter than 14 s (4.6–13.7 s).
2. **No remedy for term errors.** Most v0.1.2 errors are technical terms and numbers.
   Whisper had a hint from the bank (`initial prompt`); Parakeet does not accept it: `ParakeetEngine.swift:34`
   receives `prompt`, but the `manager.transcribe` call (line 51) does not pass it. The toggle "Hint the bank wordings to
   recognition" is inactive for Parakeet, and there is no replacement.
3. **The noise filter does not work for Parakeet.** `noSpeechProbability` is only 0 or 1 (`ParakeetEngine.swift:57`),
   so the `< 0.8` check in `StreamingTranscriber.swift:373` filters nothing. Short garbage on noise
   ("Угу.", "Да.") reaches the panel.
4. **No fallback engine on a load failure.** `ListeningController.swift:276` only checks that the model folder
   exists. If the Parakeet installation is incomplete, loading fails and there is no recognition, although Whisper is installed.
5. **The language choice in the menu does not affect Parakeet** — the language is used only as a label (`ParakeetEngine.swift:55`).
   COPILOT-01 report.md recommends choosing the language as a remedy for uk ↔ ru confusion; for Parakeet this is not true.
6. **Minor mismatches:** the logic that pins the conversation language (`stickyLanguage`, the 0.7/0.75 thresholds tuned for Whisper)
   runs for Parakeet for nothing; the quiet-audio gain up to ×40 (`WhisperEngine.normalized`) was taken from Whisper without
   a measurement for Parakeet; there are no tests of the `ParakeetEngine` adapter itself; memory on a call with Parakeet + bge-m3 is not measured.

## Desired outcome
Parakeet v3 stays the main local engine, and on interview questions of any length:
1. long questions (15–25 s) are recognized no worse than short ones — this is measured, and there is protection against join errors;
2. terms from the owner's question bank are written correctly more often than in v0.1.2, and ordinary words are not replaced;
3. noise without speech does not create lines in the panel;
4. on a Parakeet failure the app switches to Whisper by itself and says so;
5. the interface honestly shows that the UK/RU choice is only a label for Parakeet, and choosing EN excludes Cyrillic in the text;
6. short-phrase accuracy and latency are no worse than v0.1.2, memory ≤ 1.5 GB.

Observable metrics and checks — AC-01…AC-12 in [spec.md](spec.md).

## Users and systems
- User: one (the owner). MacBook Air M1, 8 GB, macOS 15.7.2.
- Systems: the InterviewCopilot app (branch `feat/copilot-01`, v0.1.2 build 3), FluidAudio 0.17.7, whisper.cpp `b5454`,
  Parakeet v3 models (`FluidInference/parakeet-tdt-0.6b-v3-coreml`, the revision from `parakeet-models.json`), Whisper (ggml).
- Platforms: the test call through Chrome (the app's local page), Google Meet in Chrome.
  Zoom and Telegram are not part of this task.

## Scope
In:
- a synthetic set of long phrases (18–25 s) in uk/ru/en and running it through the engine and through the test call;
- protection against join errors if the measurement shows them (a FluidAudio setting or own slicing ≤ 15 s at pauses);
- a term dictionary and correcting the final text with it (for both engines);
- researching dictionary boosting through CTC (FluidAudio Custom Vocabulary) — only with the owner's permission (Q3),
  off by default;
- a filter for short finals with low confidence;
- switching to Whisper on a Parakeet load failure and checking installation completeness against the manifest;
- an alphabet filter when English is explicitly chosen; interface labels about the language for Parakeet;
- turning off the sticky logic for Parakeet, measuring the quiet-audio gain, adapter smoke tests, a memory measurement;
- a reproducible script that generates the test call fixtures (there is none in the repository now).

Out (candidates for next tasks):
- capturing Zoom and Telegram audio, Core Audio process taps, browsers other than Chrome;
- new recognition engines (WhisperKit, Apple SpeechAnalyzer, Nemotron streaming), updating FluidAudio;
- fine-tuning models;
- cloud recognition;
- changes to the bank search, answer generation and the interface, except the language labels and the engine status.

## Constraints
- All recognition is local; audio is not written to disk (COPILOT-01 R-04, ADR-0001 "Refinement 2026-10-08").
  `ModelHub.offlineMode = true` at runtime.
- Memory ≤ 1.5 GB (COPILOT-01 R-25/AC-05), including the dictionary and, if accepted, the CTC encoder.
- Latency: the median "end of phrase → final" ≤ 1 s (COPILOT-01 AC-01); the owner values accuracy over latency,
  so ≤ 1.5 s is allowed for long phrases.
- New dependencies and models — only with an ADR-0001 entry and the owner's permission (CLAUDE.md).
  The Parakeet CTC 110M model for dictionary boosting is a new model and needs a separate approval (Q3).
- Only synthetic data in Git (`evals/`, `profile.example/`). Recordings of the owner's voice and FLEURS — outside Git.
- Utterance text is not written to logs (COPILOT-01 R-24): the dictionary logs only replacement counters.
- Git: no force-push, `reset --hard`, branch deletion or merge into `main` (CLAUDE.md).

## Owner decisions
Not taken yet. The executor's proposals are in the "Proposed" column; the owner's answer is recorded at H-0.

| # | Question | Proposed |
|---|---|---|
| Q1 | Where the term dictionary comes from | Automatically from `questions.yaml` (Latin words, abbreviations, capitalized words inside a phrase) + an optional `profile/vocabulary.yaml` with spelling variants |
| Q2 | Accept the AC-02, AC-04, AC-05 thresholds from spec.md | Yes; refined from the baseline at P-00/P-01 with a note in the handoff |
| Q3 | Allow researching CTC dictionary boosting (download Parakeet CTC 110M ~100 MB from Hugging Face FluidInference with SHA256) | Yes, as a time-boxed research; enabling it by default — only after a measurement and a separate decision |
| Q4 | Branch | A new `feat/copilot-02` from `feat/copilot-01` (it is not merged into `main`); update CLAUDE.md at P-00 |
| Q5 | Executor | Claude Code, `claude-opus-5-5`, effort high, as in COPILOT-01 |
| Q6 | A live check on the owner's voice (H-2) | Yes: 3 long questions and 5 questions with terms through Meet from a phone or own recordings outside Git |

## Assumptions (non-blocking)
- A-1. The terms that matter to the owner are in `questions.yaml` or will be added to `vocabulary.yaml`;
  a general IT term dictionary is not compiled.
- A-2. The dictionary correction applies to the final text; the interim text is not corrected (it changes anyway).
- A-3. The interviewer does not speak longer than 25 s without pauses ≥ 350 ms; the utterance limit (`maxUtterance`) does not change.
- A-4. The synthetic macOS voices (`say`: Lesya, Milena, Samantha) are enough to find join errors;
  accuracy on live speech is confirmed by H-2.
- A-5. If the VAD cuts synthetic long phrases at the pauses between sentences, 15–25 s phrases are rare in a real stream;
  this is recorded as a result, not as an AC-01 failure.

## Open questions
No blockers except the answers to Q1–Q6 at H-0. Checked along the way:
- whether Parakeet v3 has join errors on 15–25 s phrases (P-01);
- whether CTC 110M works on Cyrillic or only on English terms inside a Cyrillic phrase (P-04, if Q3 = yes);
- whether Parakeet needs volume normalization (P-08).
