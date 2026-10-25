# COPILOT-02: Technical plan

ID: COPILOT-02-plan · Status: **draft** · Version: 1 · Date: 2026-10-22 · Owner: itmax04
Precondition: [intent.md](intent.md) and [spec.md](spec.md) are accepted by the owner at H-0. Requirements are not repeated here —
only references to R-/AC- numbers from spec.md (the previous task — with the "01/" prefix).
Executor: Claude Code, `claude-opus-5-5`, effort high (Q5). The prompt — [executor-prompt.md](executor-prompt.md).

## Preconditions and state
- Repository: `~/Desktop/1/interview-copilot`, the private `itmax04/interview-copilot`.
- Base: branch `feat/copilot-01` @ `3b690fc` (v0.1.2 build 3), not merged into `main`.
  Before the work, compare the local copy with `origin/feat/copilot-01`: as of 2026-10-22 the owner's local copy was behind
  by 2 commits (`7acd4cd`, `3b690fc`) — update only by fast-forward, without overwriting the owner's changes.
- Working branch: `feat/copilot-02` from `feat/copilot-01` (Q4). The project CLAUDE.md says to work in `feat/copilot-01` —
  fix it to the current task at P-00 (a separate commit).
- Models: Parakeet v3 (`scripts/fetch-parakeet.py`), Whisper turbo/medium (`scripts/fetch-models.sh`), bge-m3 —
  installed at the owner's in `~/Library/Application Support/InterviewCopilot/models/`. Experiments that break the installation (AC-06)
  — only on a copy through `INTERVIEWCOPILOT_MODELS_DIR`.
- The commands `swift build`, `swift test`, `scripts/run-evals.sh`, `scripts/secret-scan.sh`, `scripts/build-app.sh`,
  `scripts/eval-local-stt.py`, `scripts/metrics.py`, `scripts/footprint-monitor.sh`, `copilot-eval stt|stt-parakeet|stt-stream`
  already exist. New: a fixtures script (P-01), the `vocab` eval (P-03).

## Owner points (H)
The executor reaches a point, stops, gives step-by-step instructions in Russian and waits for "done".
Asks no other questions.

| H | When | The owner's action |
|---|---|---|
| H-0 | Before P-00 | Accept intent/spec/plan (statuses → accepted), answer Q1–Q6 in intent.md |
| H-1 | P-01, only if the AC-02/AC-04/AC-05 thresholds are unreachable or trivial by the baseline | Choose the threshold proposed by the executor |
| H-2 | P-10 (Q6) | A live check: Meet in Chrome on the Mac + a phone, 3 long questions and 5 questions with terms per `evals/live-script-02.md`; rate each "clear / unclear" |
| H-3 | P-11 | Acceptance per COPILOT-02 report.md |

## Steps
Each step: implementation → step checks → handoff.md update → commit `P-xx: <short>` → `git push origin feat/copilot-02`.
Order — by review priority: joins → dictionary → noise and reliability → language → gain and tests.

**P-00. Baseline**
- Record in handoff.md: `git status`, `git log -1`, the Xcode/Swift version, the installed models (names and sizes, without the owner's paths in Git).
- `swift build`, `swift test` (157 PASS expected), `scripts/run-evals.sh`, `scripts/secret-scan.sh`, `scripts/build-app.sh`.
- The v0.1.2 test call (15 phrases, Parakeet, Auto) — the baseline of the current build next to the numbers of report.md v0.1.2.
- Update the project CLAUDE.md: the current task COPILOT-02, branch `feat/copilot-02`.

**P-01. Long phrases and the join measurement** — R-01, AC-01, AC-02
- `scripts/make-test-call-fixtures.sh`: generating all test call fixtures (the existing 15 and the new long ones)
  with `say` voices + "quiet" and "compressed" variants through `afconvert`; the result goes to `evals/audio/test-call/`.
  Regenerating the existing 15 must not change their reference text; if the durations differ from the current files —
  do not replace the old files, record the difference in the handoff.
- ≥ 9 long phrases (3 per language), references in `Resources/TestCall/clips.json` and in the manifest `evals/stt/long.json`
  (the `scripts/eval-local-stt.py` format: id/language/condition/path/expected).
- A direct run: `scripts/eval-local-stt.py evals/stt/long.json …` (the parakeet-auto and turbo-full profiles for comparison).
- A run through the test call; record `audio_ms` of each final (the A-5 check: whether phrases > 15 s reach the engine).
- An error analysis by location: at a join (12–18 s from the start) or not.
- If the AC-02 thresholds are unreachable or trivial by the baseline — H-1.

**P-02. Join protection** — R-02 (only if P-01 found join errors)
- Option 1: `ASRConfig(dualDecodeArbitration: true)` in `ParakeetEngine.load`.
- Option 2: slicing the final into ≤ 15 s pieces at the energy minimum in the 10–15 s window, recognizing the pieces, merging.
- Compare by AC-02 and AC-09, choose, record in ADR-0001. Tests: slicing (unit, without a model), a long file (R-12).
- If the joins are clean — the step is skipped with a note in the handoff and ADR-0001.

**P-03. The term dictionary and correcting the final** — R-03, R-04, AC-04
- `CopilotCore/Vocabulary/TermDictionary.swift` (collecting from `questions.yaml` + `vocabulary.yaml`, watching the files),
  `TermCorrector.swift` (matching, the stop list, thresholds).
- Wiring: after a `StreamingTranscriber` final → `TermCorrector` → turn detection and search (both engines).
- Settings → Audio: "Correct terms from the bank" (on by default); a menu item for parse errors — like 01/S-10.
- `profile.example/vocabulary.yaml`; the `evals/vocab/` set: ≥ 15 phrases with terms (fixtures through the P-01 script) and
  ≥ 30 control phrases without terms (text ones; running the correction on text is enough).
- The `vocab` eval in `copilot-eval` and `scripts/run-evals.sh vocab`; the similarity threshold — in evals/README.
- Tests: `TermDictionaryTests`, `TermCorrectorTests` (S-02, S-03, Cyrillic ↔ Latin, numbers are not touched).

**P-04. Research of CTC boosting** — R-05 (only if Q3 = yes; time-boxed — one step)
- A Parakeet CTC 110M model manifest with SHA256 from the official FluidInference repository; downloading into a copy of the models folder.
- A measurement on the `vocab` set: Cyrillic and English terms separately; memory and latency.
- An ADR-0001 entry: accept / reject. The code is behind a disabled flag, or does not get into the branch if rejected.

**P-05. Noise filter** — R-06, AC-05
- A noise set (≥ 20 synthetic recordings: keyboard, music without words, rustling, clicks) — generated by a script
  (`sox`/`afconvert` or synthesis in Swift/Python; new tools — only if already installed, otherwise ask at H-1).
- Threshold C from the noise set and short lines; recorded in evals/README.
- Implementation in `StreamingTranscriber.runFinal` (or in the adapter through a `noSpeechProbability` derived from `confidence`
  and the word count — choose and justify in the handoff). Tests on a fake recognizer.

**P-06. Installation check and switching to Whisper** — R-07, AC-06
- `ParakeetEngine.isInstalled(at:manifest:)` against `parakeet-models.json` (existence and size).
- `ListeningController.loadRecognizer`: on a Parakeet error — Whisper, the S-05 status; the setting does not change.
- Tests: the manifest (complete / a missing file / a different size), the engine choice on fake loaders.
- A manual check on a copy of the models folder (`INTERVIEWCOPILOT_MODELS_DIR`), not on the owner's original.

**P-07. Language: filter, labels, sticky** — R-08, R-09, R-10, AC-07, AC-08
- `ParakeetEngine.transcribe`: `language: .english` only with explicit English.
- The R-09 labels in the Language menu and Settings → Audio; refine COPILOT-01 test-plan.md and report.md with a reference to COPILOT-02.
- `StreamingTranscriber`: the sticky logic only with `!recognizer.nativeMultilingual`.
- Tests: the filter choice, sticky off for nativeMultilingual, the existing `StreamingTranscriberTests` without changing expectations.
- Screenshots → `docs/changes/COPILOT-02/evidence/`.

**P-08. Quiet-audio gain** — R-11
- An `eval-local-stt.py` run over quiet and compressed phrases with and without the gain (a temporary engine parameter / an environment variable
  only for the eval). The decision and numbers — in ADR-0001.

**P-09. Adapter tests** — R-12
- `ParakeetEngineTests` (skipped without a model). Can start earlier, at P-01, if it speeds up the work.

**P-10. Final measurements and a live check** — AC-03, AC-07, AC-09, AC-10
- A full test call (15 + long + terms), `scripts/metrics.py`, `scripts/footprint-monitor.sh 10`.
- Prepare `evals/live-script-02.md` (3 long questions, 5 questions with terms, by language).
- H-2.

**P-11. Review and report** — AC-11, AC-12
- An independent review with a fresh context (`/code-review high` over `feat/copilot-02` against spec.md and CLAUDE.md).
  Fix P0/P1 findings, list the rest.
- A clean clone: `swift build`, `swift test`, `scripts/build-app.sh`.
- `docs/changes/COPILOT-02/report.md`: AC → method → PASS / FAIL / NOT RUN → evidence; ADR-0001 and evals/README
  updated. H-3.

## Dependencies
No new SwiftPM packages are needed: FluidAudio 0.17.7 already has `ASRConfig.dualDecodeArbitration`,
`TokenLanguageFilter`, `CustomVocabulary`. A new model is possible only at P-04 (Parakeet CTC 110M) — if Q3 = yes,
with an ADR-0001 entry. Updating FluidAudio is outside the task.

## Checks
| Command | Steps | Expected evidence |
|---|---|---|
| `swift build` | all | Builds without errors |
| `swift test` | all | All tests green; the number of tests ≥ 157 + new, in the handoff |
| `scripts/make-test-call-fixtures.sh` (new) | P-01+ | Files and durations (AC-01) |
| `scripts/eval-local-stt.py evals/stt/long.json <out>` | P-01, P-02, P-08 | WER by language and variant (AC-02) |
| `scripts/run-evals.sh` (bank, turn, vocab) | P-03+ | bank/turn — previous thresholds; vocab — AC-04 |
| The test call (the "Test call…" menu) | P-00, P-01, P-07, P-10 | The page's JSON report (AC-03, AC-05, AC-07) |
| `scripts/metrics.py` | P-10 | Final latency medians (AC-09) |
| `scripts/footprint-monitor.sh 10` | P-10 | Peak ≤ 1.5 GB (AC-10) |
| `scripts/secret-scan.sh` | before each push | "0 findings" |
| `scripts/build-app.sh` + `codesign --verify --strict` | P-00, P-07, P-10, P-11 | `dist/InterviewCopilot.app` is signed |

Tests and thresholds must not be weakened for a green result. Anything not run — NOT RUN with a reason.

## Risks and rollback
| Risk | Sign | Action |
|---|---|---|
| The VAD cuts synthetic long phrases at the pauses between sentences | Finals' `audio_ms` < 15 s on the test call | The direct run into the engine stays the AC-02 measure; record the fact (A-5) |
| Corrections spoil ordinary words | False corrections on the control set | Tighten the threshold, extend the stop list; if 0 false ones is impossible — only explicit variants from `vocabulary.yaml` |
| `dualDecodeArbitration` doubles the time on long phrases | AC-09 > 1.5 s | Option 2 (own slicing) or protection only for phrases > 15 s |
| The CTC encoder does not work on Cyrillic | P-04 | Reject or keep only for Latin script; an ADR entry |
| Memory > 1.5 GB | AC-10 | Without CTC; unloading dictionary structures; escalation |
| No tool to generate noise | P-05 | Synthesis in Swift/Python without new dependencies; otherwise H-1 |

Rollback: each step is a separate commit in `feat/copilot-02`; on failure — `git revert` of one's own commit.
`feat/copilot-01` and `main` do not change. Destructive git commands are forbidden (CLAUDE.md).

## Stop conditions (escalation to the owner)
- A dependency, model or service outside ADR-0001 and the intent is needed (except CTC 110M if Q3 = yes).
- An AC threshold is unreachable without changing the task scope.
- Keys or personal data are found in Git.
- Three attempts in a row on one problem without progress — the state and hypotheses go to handoff.md.
- Any action from the "Forbidden" list in CLAUDE.md.

## Done when
AC-01…AC-12 have evidence in report.md (PASS or NOT RUN with a reason accepted by the owner), the P-11 review has no
open P0/P1, the `feat/copilot-02` branch is pushed, handoff.md is current, the owner confirmed H-3.
