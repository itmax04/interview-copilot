# COPILOT-02: Specification — Parakeet v3 accuracy

ID: COPILOT-02-spec · Status: **draft** · Version: 1 · Date: 2026-10-22 · Owner: itmax04
Links: [intent.md](intent.md) (goal, scope, questions Q1–Q6) · [plan.md](plan.md) (implementation) ·
[ADR-0001](../../decisions/ADR-0001-stack.md) · [COPILOT-01 spec](../COPILOT-01/spec.md) · [evals/README.md](../../../evals/README.md)
This file is the only source of requirements for this task. R-/S-/AC- numbers without a prefix belong to COPILOT-02;
requirements of the previous task are written with a prefix: "01/R-04", "01/AC-05". The COPILOT-01 requirements remain in force.

## 1. Terms
- **Phrase (utterance)** — the interviewer's speech between VAD pauses (01/R-03); the final text of a phrase is the **final**.
- **Long phrase** — a phrase whose audio for the final recognition is longer than 15 s (more than one Parakeet window).
- **Join (seam)** — the place where FluidAudio glues the results of neighboring 15 s windows.
- **Term dictionary** — a list of canonical spellings (`Kubernetes`, `PostgreSQL`, `CI/CD`) and their variants,
  built per R-03.
- **Correction** — replacing a fragment of the final with a canonical term from the dictionary.
- **Raw WER** — the word error rate as in COPILOT-01 report.md v0.1.2: word edit distance,
  ignoring case and punctuation, ё = е, apostrophes normalized, numbers in their original spelling.
- **Baseline v0.1.2** — the test call of 2026-10-08, 15 phrases, Parakeet v3: RU 7/96 (7.29%), UK 9/97 (9.28%),
  EN 4/123 (3.25%), the median final latency 501 ms.

## 2. Scenarios
- **S-01. A long question.** Given: the Parakeet engine, source — Chrome. When: the interviewer speaks for 20 s without pauses ≥ 350 ms
  and stops. Then: the panel shows one final without dropped, repeated or "glued" words at a join; the text language does not change
  in the middle of the phrase.
- **S-02. A term from the bank.** Given: `questions.yaml` has "PostgreSQL". When: the interviewer says
  "Как вы оптимизировали запросы в PostgreSQL?", and the model recognized "постгрес кьюэль". Then: the final has "PostgreSQL".
- **S-03. A similar ordinary word.** Given: the dictionary has "Jira". When: the interviewer says "жира в этом блюде много" ("there is a lot of fat in this dish").
  Then: no correction (the word is not replaced without enough similarity and context per R-04).
- **S-04. Noise without speech.** When: the call audio has a keyboard, music or rustling without speech, and the VAD opened a phrase.
  Then: a final with one or two words and low confidence is not shown and does not start a bank search.
- **S-05. A Parakeet failure.** Given: the Parakeet folder lacks one file from the manifest or Core ML did not load the model.
  When: listening starts. Then: Whisper from the settings is loaded, the status is
  "Parakeet did not load: <reason>. Using Whisper <model>".
- **S-06. Explicit English.** Given: Language = English, the Parakeet engine. When: an English question is heard
  on compressed audio. Then: the final has no Cyrillic letters.
- **S-07. Explicit Ukrainian or Russian.** Given: Language = Українська or Русский, the Parakeet engine.
  Then: the text is recognized as in Auto (English terms are kept in Latin script), and the Language menu and Settings → Audio
  show a label that for Parakeet the UK/RU choice only sets the language label.

## 3. Requirements

### Long phrases
- **R-01. A set of long phrases.**
  - ≥ 9 synthetic phrases 18–25 s long: 3 each for uk/ru/en; each has ≥ 1 English technical term or a number.
  - For each — a clean variant and a "compressed call audio" variant (like `*-long-compressed`): AAC 8 kHz ~12 kbit/s → WAV 16 kHz mono.
  - The reference text — in `Resources/TestCall/clips.json` (the test call) and in the manifest for `scripts/eval-local-stt.py`.
  - The fixtures are created by a reproducible script from the repository (there is no script for `evals/audio/test-call/` now),
    voices as in 01/P-04: uk — Lesya, ru — Milena, en — Samantha.
  - A run along two paths: directly into the engine (`copilot-eval stt-parakeet`, without VAD) and through the test call
    (Chrome capture → VAD → StreamingTranscriber). The audio length of each final (`audio_ms`) is written to the results.
- **R-02. Join protection.** If per R-01 the WER of long phrases is above the AC-02 threshold or join errors are found
  (≥ 2 consecutive words dropped, a repeat, a word in a foreign alphabet), enable protection and choose an option by measurement:
  1. `ASRConfig.dualDecodeArbitration = true` (FluidAudio, the v3 no-mel path);
  2. own slicing of the final into ≤ 15 s pieces at the point of minimum energy in the 10–15 s window, with the text merged.

  The choice, measurements and time cost are recorded in ADR-0001. If there are no join errors, protection is not enabled
  and the fact is recorded in ADR-0001 and report.md.

### Term dictionary
- **R-03. Dictionary source** (decision Q1):
  - automatically from `profile/questions.yaml`: Latin words inside Cyrillic wordings, abbreviations
    (≥ 2 capital letters), words with inner capitals (`JavaScript`), words mixed with digits (`S3`, `K8s`);
  - an optional `profile/vocabulary.yaml`:
    ```yaml
    - term: PostgreSQL           # canonical spelling
      variants: [постгрес, постгрескуэль, postgres sql]   # optional
    ```
  - the dictionary is rebuilt when `questions.yaml` or `vocabulary.yaml` is saved (like 01/S-10);
    a `vocabulary.yaml` parse error is shown in the menu, the previous dictionary stays;
  - an example — `profile.example/vocabulary.yaml` (synthetic).
- **R-04. Correcting the final.**
  - Applies to the final text of both engines before it goes to turn detection and the bank search; the interim text
    does not change (A-2).
  - Matching: explicit variants from `vocabulary.yaml` — an exact case-insensitive match; the rest — fuzzy
    by transliteration and edit distance (the FluidAudio BK-tree `CustomVocabulary/BKTree` or an own one may be used).
    The similarity threshold is tuned on the AC-04 set and recorded in evals/README.
  - Only fragments of 1–3 words are replaced; a word from the language's frequent-word list (a stop list) without an explicit variant
    is not replaced (S-03).
  - Turned off in Settings → Audio ("Correct terms from the bank", on by default).
  - The log gets only the number of corrections per final, without text (01/R-24).
- **R-05. CTC dictionary boosting — research** (only if Q3 = yes).
  - FluidAudio Custom Vocabulary, Approach 2: a separate Parakeet CTC 110M encoder (≈ 97.5 MB on disk,
    +64–130 MB of memory per the FluidAudio documentation).
  - Check on the AC-04 set: whether it helps on Cyrillic or only on English terms inside a Cyrillic phrase;
    memory (AC-10) and latency (AC-09).
  - The outcome — an ADR-0001 entry "accept / reject" with numbers. Off by default; enabling it is the owner's decision.
  - The model is downloaded from the official FluidInference repository with SHA256 in a manifest (like `parakeet-models.json`).

### Noise filter
- **R-06. Dropping garbage finals.** A Parakeet final is not emitted if both: ≤ 2 words and
  `confidence` (the mean FluidAudio token probability) below threshold C. Threshold C is tuned on the noise set and
  on the short lines of the `turn` set, recorded in evals/README. For Whisper the existing
  `noSpeechProbability` filter does not change. Turn detection (01/R-05) already requires ≥ 3 words, so 1–2-word lines
  do not affect the answer; the filter removes them from the panel and the history.

### Engine reliability
- **R-07. Installation check and switching to Whisper.**
  - Parakeet counts as installed only if all files from `parakeet-models.json` exist and their sizes match
    (the installer checks SHA256; at launch — only existence and size, so as not to slow down the start).
  - Any Parakeet load error → loading Whisper from `whisperModel` per S-05. No Whisper either — the current error
    "No recognition model".
  - The switch does not change the saved engine setting: on the next launch Parakeet is tried again.

### Language
- **R-08. Alphabet filter.** With Language = English and the Parakeet engine the `AsrManager.transcribe` call gets
  `language: .english` (the FluidAudio alphabet filter, `TokenLanguageFilter`). With Auto, Українська, Русский the filter
  is not passed: it does not distinguish uk and ru and would throw away English terms.
- **R-09. Honest labels.** For the Parakeet engine the Language submenu and Settings → Audio show a label:
  "Parakeet detects the language itself; UK/RU only change the language label, English removes Cyrillic".
  The recommendation "choose the language in the menu" in the documentation (test-plan, report) is refined: it applies to Whisper.
- **R-10. Language pinning only for Whisper.** The `stickyLanguage` / `sessionLanguage` / `lowConfidenceStreak` logic
  in `StreamingTranscriber` does not run for engines with `nativeMultilingual = true`. Whisper's behavior does not change
  (the existing `StreamingTranscriberTests` pass without changing expectations).

### Quality and checks
- **R-11. Quiet-audio gain.** Compare Parakeet with and without `WhisperEngine.normalized` on quiet and compressed
  phrases (R-01 + `*-long-quiet`, `*-long-compressed`). Keep the option with the lower raw WER; on a tie (± 1 error
  per language) — without the gain. The decision goes to ADR-0001.
- **R-12. Adapter tests.** Swift Testing for `ParakeetEngine`, run only when the model is installed
  (otherwise skipped with a reason, not failed):
  - silence −80 dBFS, 2 s → empty text without calling the model;
  - `cancel()` while recognizing a 20-second file → a cancellation error returned faster than a full recognition;
  - the language label for uk/ru/en fixtures;
  - a file longer than 15 s → non-empty text;
  - English + `language: .english` → no Cyrillic in the text.

  Unit tests without a model: the dictionary (R-03, R-04), the filter (R-06), the manifest check and the switch (R-07), choosing the language
  filter (R-08), turning off the sticky logic (R-10).
- **R-13. Unchanged.** Audio is not written to disk (01/R-04); cloud recognition is not used;
  `ModelHub.offlineMode = true`; new fixtures — synthetic only; the owner's files and FLEURS — outside Git.

## 4. Acceptance criteria
| AC | Criterion | Check |
|---|---|---|
| AC-01 | The long-phrase set exists: ≥ 9 phrases of 18–25 s (3 per language) × 2 audio variants, references in `clips.json` and the manifest, a generation script in `scripts/` | The list of files and durations (`afinfo`) in report.md; rerunning the script gives the same durations ± 0.1 s |
| AC-02 | Long phrases, Parakeet, a direct run: raw WER per language ≤ baseline v0.1.2 + 3 pp (RU ≤ 10.3%, UK ≤ 12.3%, EN ≤ 6.3%); not a single drop of ≥ 3 consecutive words | `scripts/eval-local-stt.py` on the R-01 manifest, a table by language and audio variant |
| AC-03 | No regression: the 15 v0.1.2 phrases through the test call — no more errors than the baseline + 1 per language (RU ≤ 8, UK ≤ 10, EN ≤ 5) | The test call, the page's JSON report |
| AC-04 | Terms: on a set of ≥ 15 phrases with terms (≥ 5 per language) the share of correctly written terms is ≥ 80%, and term errors are at least half of those on the same set without corrections; on a control set of ≥ 30 phrases without terms — 0 false corrections | A new `vocab` eval (`copilot-eval vocab` or an `eval-local-stt.py` mode), the baseline — the same set without corrections |
| AC-05 | Noise: on a set of ≥ 20 synthetic recordings without speech (keyboard, music, rustling, silence with clicks, 5–10 s) ≤ 1 final is shown; not one of the 15 v0.1.2 phrases is lost | The test call or `copilot-eval stt-stream` over the noise set; the number of finals in report.md |
| AC-06 | Switching to Whisper: with a file from the Parakeet manifest removed the app listens with Whisper and shows the status per S-05 | A unit test of the manifest check + a manual check by the executor on a copy of the models folder (do not touch the owner's original) |
| AC-07 | English: on 5 EN test call phrases with Language = English the finals have 0 Cyrillic letters; with Українська / Русский the text matches Auto | The test call with the chosen language + a unit test of the filter choice |
| AC-08 | The R-09 labels are visible in the Language menu and in Settings → Audio with Parakeet | Screenshots in `docs/changes/COPILOT-02/evidence/` |
| AC-09 | Latency: the median "end of phrase → final" ≤ 1 s on the 15 v0.1.2 phrases and ≤ 1.5 s on long phrases (with corrections and the filter) | `scripts/metrics.py` over the test call logs |
| AC-10 | Memory: the maximum `footprint` ≤ 1.5 GB over 10 minutes of listening and recognition (Parakeet + bge-m3; + CTC if accepted) | `scripts/footprint-monitor.sh 10` during a repeating test call |
| AC-11 | Build and checks: `swift build`, `swift test` (all previous 157 + new), `scripts/run-evals.sh` (bank and turn — previous thresholds), `scripts/secret-scan.sh` 0 findings, `scripts/build-app.sh` + `codesign --verify --strict`, a clean clone | Commands and output in report.md |
| AC-12 | Decisions are documented: ADR-0001 (joins, gain, CTC), evals/README (the C and similarity thresholds, new sets), COPILOT-02 report.md with the status of each AC | A review of the documents at H-3 |

The AC-02, AC-04, AC-05 thresholds are a proposal (Q2). If the P-00/P-01 baseline shows that a threshold is unreachable or trivial,
the executor stops at H-1 with numbers and a proposal rather than changing the threshold themselves.

## 5. Decisions and assumptions
- Facts: the code `feat/copilot-01` @ `3b690fc`, FluidAudio 0.17.7 (`ASRConstants.maxModelSamples`, `TokenLanguageFilter`,
  `ASRConfig.dualDecodeArbitration`, `seamGapRepair`, `Documentation/ASR/CustomVocabulary.md`) — read on 2026-10-22.
  The durations of the 15 test call fixtures — 4.6–13.7 s (`afinfo`).
- Owner decisions: Q1–Q6 (intent.md), taken at H-0.
- Assumptions: A-1…A-5 (intent.md). Executor decisions — in handoff.md.
