# Evals — Interview Copilot

Status: **accepted** (2026-10-06) · Date: 2026-10-06 · Links: [spec.md](../docs/changes/COPILOT-01/spec.md) (R-05, R-07, AC-01…AC-04, AC-10)
Datasets are created in plan steps P-05, P-06 and P-12. All data is synthetic: real résumés and transcripts never go here.
Test phrases are intentionally in Ukrainian, Russian and English — the languages the app recognizes.

## Why
Bank search and end-of-question detection are non-deterministic: they depend on the embedding model, thresholds and
transcription quality. Unit tests do not cover them, so datasets with thresholds and baselines are needed.
A run is mandatory when the embedding model, the Whisper model, thresholds or the bank format change.

## `bank` set (AC-04)
- File: `evals/bank/cases.jsonl`. Uses `profile.example/questions.yaml`.
- Line: `{"q": "Пару слов о вашем опыте?", "lang": "ru", "expected": "about-me"}`;
  for a question outside the bank — `"expected": null`.
- Content: ≥ 30 paraphrases of bank cards (≥ 8 per language uk/ru/en; wording does not match the cards' `questions`
  verbatim) and ≥ 10 questions outside the bank.
- Metrics: top-1 accuracy on bank questions, false-match rate on out-of-bank questions, top-3 accuracy.
- Thresholds: top-1 ≥ 85%, false matches ≤ 10%. The score threshold is tuned on this set and recorded here.
- Run: `scripts/run-evals.sh bank` → `evals/results/bank-<date>.txt` (not in Git) and a summary on stdout.
  By default the app configuration is used (model and threshold from settings); `copilot-eval bank --tune --sweep --model …` tunes.
- Content (P-06): 39 paraphrases (13 uk, 13 ru, 13 en) and 12 out-of-bank questions; no verbatim matches with the cards.
  Holdout set `evals/bank/holdout.jsonl` (12 + 4) — to check that the threshold is not fitted to the main set.
- **Threshold: 0.74** (bge-m3 Q8_0). A match counts only if the best card is above the threshold and is the right one.

## `turn` set (R-05)
- File: `evals/turn/cases.jsonl` — sequences of transcript segments with pauses.
  Example line: `{"segments":[["Расскажите",0],["о проекте,",300],["который",900]], "expected_turn_at": null}`.
- Cases:
  - a finished question;
  - a pause in the middle of a phrase ("который… сделали в прошлом году");
  - short interjections ("угу", "так");
  - the owner started speaking;
  - a forced turn.
- Metrics: premature turns ≤ 10%, missed turns ≤ 5%, trigger latency = T.
- Line format (P-05): `{"id", "segments": [[text, start_ms, end_ms], …], "expected_turn_at": ms | null,
  "owner": [[from, to], …], "force_at": ms}`; a pair `[text, t]` means start = end = t. The final phrase text arrives
  500 ms after speech ends (as with recognition, P-04). `expected_turn_at` is the end of the question's last phrase.
  A premature turn fires earlier than `expected_turn_at`, without the question's last phrase, or where no turn should
  happen (`null`).
- Content (34): finished questions, mid-phrase pauses (on a function word and on a "thinking" pause of 550–650 ms),
  short interjections, the owner speaking, speaker echo in the microphone, a forced turn; uk / ru / en.
- Run: `scripts/run-evals.sh turn` (or `copilot-eval turn --threshold-ms N --verbose`).
- Choosing T (P-05): 400 and 500 ms — 3 premature turns of 34 (8.8%), 600 ms — 1 (2.9%), **700 ms — 0**, 1000 ms — 0.
  The default stays 700 ms (R-05): the smallest threshold without premature turns on the set.

## Audio fixtures (P-04)
- `evals/audio/*.wav` — phrases generated with `say` (uk / ru / en), 16 kHz mono. Used for Whisper measurements and
  `WhisperEngineTests`.
- Synthetic voices only.

## Live script (AC-01…AC-03, AC-10)
- `evals/live-script.md` — 15 questions (5 uk, 5 ru, 5 en) for the H-4 call: some paraphrase cards, some are outside the
  bank, one long question with a pause in the middle.
- Metrics from logs: `scripts/metrics.py` (median and p90 of `phrase_end → transcript_final`, `turn_end → card_shown`,
  `turn_end → first_token`).

## Baseline
Filled in by the executor in P-06 and P-12: date, commit, models, thresholds, results.

| Date | Commit | Embedding model / Whisper | Threshold | bank top-1 | False | turn premature / missed |
|---|---|---|---|---|---|---|
| 2026-10-06 | P-05 (after `e836139`) | — / whisper small q5_1 | T = 700 ms | NOT RUN (P-06) | NOT RUN (P-06) | 0% / 0% (34 cases) |
| 2026-10-06 | P-06 (after `61bfd6d`) | bge-m3 Q8_0 / whisper small q5_1 | 0.74; T = 700 ms | 94.9% (holdout 91.7%) | 0% (holdout 0%) | 0% / 0% |

## `filter` set (COPILOT-05, R-02, R-05; AC-01, AC-02, AC-04)
- **Text** — `evals/filter/text-cases.jsonl` (214 cases, in Git): phrase, menu language, channel, expected keep/drop.
  Run: `scripts/run-evals.sh filter-text` (part of the default run, no models needed). Threshold: all cases correct.
- **Audio** — `scripts/make-filter-fixtures.py` generates 56 files in `evals/audio/filter/` (not in Git): uk/ru/en questions
  with technical terms (voices Milena, Lesya, Samantha) and the same over music; "TV" in de/fr/en (Anna, Thomas, Daniel,
  Fred, Karen) quieter than the question; noise without speech (white, "street", keyboard, 50 Hz hum, music). Manifest —
  `evals/filter/audio-cases.json`. Run: `scripts/run-evals.sh filter` (needs Parakeet and Silero). One file = one
  utterance: Silero → Parakeet → language filter.
- Thresholds: foreign language dropped ≥ 90%; wanted phrases lost ≤ 5%; questions with terms never dropped; noise without
  speech — ≤ 1 utterance.
- **Silero threshold: 0.5** (maximum speech probability over 256 ms chunks). On the set: speech 1.00, noise and silence below 0.5.

| Date | Configuration | Foreign language | Wanted lost | Terms kept | Noise → utterances |
|---|---|---:|---:|---:|---:|
| 2026-10-23 | no filters (0.1.11) | 0/16 | 0/20 | 8/8 | 0/20 |
| 2026-10-23 | Silero + language filter (0.2.0) | **16/16** | 1/20 (uk question over music recognized as Polish) | 8/8 | 0/20 |

## `voice` set (COPILOT-05 R-03, AC-03)
- `scripts/make-voice-fixtures.py`: "owner" samples Milena (ru), Lesya (uk), Samantha (en) and 4 phrases each from 8 macOS
  voices, plus the owner's voice in another language (Milena in English, Lesya and Samantha in Russian). Audio —
  `evals/audio/voice/` (not in Git), manifest — `evals/filter/voice-cases.json`. Run: `scripts/run-evals.sh voice` (needs CAM++).
- The threshold is personal: `VoicePrint.recommendedThreshold` = spread of the sample chunks − 0.08, within 0.55…0.85.
  0.85 is the highest threshold at which the own synthetic voice is accepted 100%: other voices rejected 92–93%.

| Date | Threshold | Own voice | Own voice, other language | Other voices | Own accepted | Others rejected | CAM++ per utterance |
|---|---|---|---|---|---:|---:|---:|
| 2026-10-23 | auto (0.85) | 0.89–0.97 | 0.88–0.95 | 0.33–0.90 (median 0.67) | 18/18 | 89/96 (93%) | ~0.2 s |

Apple's synthetic voices are similar to each other (Milena↔Lesya up to 0.89); live voices differ more, but the owner's
live voice also varies more — so the threshold is personal and checked on the live voice (H-2).

## `enhance` set (COPILOT-05 R-04)
- `scripts/make-noisy-fixtures.py`: 10 questions (Milena ru, Lesya uk, Samantha en), clean and over a background —
  "street" (pink noise, SNR 5 dB), music 5 dB, keyboard 5 dB, German "TV" speech 10 dB. Audio — `evals/audio/noisy/`
  (not in Git), manifest — `evals/filter/noisy-cases.json`. Run: `copilot-eval enhance` (needs Parakeet and LocalVQE).

| Date | Background | Parakeet | Parakeet + LocalVQE v1.3 |
|---|---|---:|---:|
| 2026-10-23 | clean | 1.5% | 1.5% |
| 2026-10-23 | street 5 dB | 0.0% | 4.5% |
| 2026-10-23 | music 5 dB | 1.5% | 1.5% |
| 2026-10-23 | keyboard 5 dB | 1.5% | 3.0% |
| 2026-10-23 | "TV" speech 10 dB | 14.9% | 20.9% |
| 2026-10-23 | **total** | **3.9%** | **6.3%** |

Conclusion: noise suppression before Parakeet worsens recognition — off by default (setting marked "experimental").
LocalVQE ~48 ms per 1 s of audio (M1, CPU).

## `materials` set (COPILOT-08 R-06, AC-05)
- `evals/materials/docs/` — synthetic notes: Swift concurrency (uk), system design (ru), company and role (en);
  `evals/materials/cases.jsonl` — 24 questions about the materials in three languages (the expected chunk is a substring)
  and 8 unrelated ones.
- Run: `copilot-eval materials [--threshold 0.xx] [--sweep] [--verbose]` (needs bge-m3). PASS: the right chunk in the
  top 4 for ≥ 90% of questions, chunks attached to unrelated questions — no more than 3 of 8.

| Date | Chunking | Chunks | Threshold | Found in top 4 | Unrelated with a chunk |
|---|---|---:|---:|---:|---:|
| 2026-10-24 | paragraphs merged up to 800 | 8 | 0.45 | 22/24 | 3/8 |
| 2026-10-24 | paragraph = chunk (short ones merged up to 200) | 16 | 0.45 | 24/24 | 4/8 |
| 2026-10-24 | same | 16 | **0.47** | **23/24** | **2/8** |
| 2026-10-24 | same | 16 | 0.50 | 21/24 | 2/8 |

The miss at 0.47 is "реентерабельность" (ru) vs "реентрантність" (uk) in the notes: a rare term in different languages.

## `bank --first-only` (COPILOT-08 AC-04): why "Prepare" matters
Each card of the example keeps only its first phrasing — as the owner's question before preparation.

| Date | Phrasings | Threshold | top-1 | en / ru / uk | False |
|---|---|---:|---:|---|---:|
| 2026-10-24 | first only (ru) | 0.74 | 48.7% | 10/13 · 4/13 · 5/13 | 0/12 |
| 2026-10-24 | first only (ru) | 0.65 | 79.5% | 12/13 · 8/13 · 11/13 | 0/12 |
| 2026-10-24 | 2+ per language (as after "Prepare") | 0.74 | **94.9%** | 12/13 · 12/13 · 13/13 | 0/12 |
