# COPILOT-05: Plan

ID: COPILOT-05-plan · Status: **accepted** (2026-10-23, "yes, I accept, start the first stage") · Version: 1 · Date: 2026-10-23 · Owner: itmax04
Links: [intent.md](intent.md) · [spec.md](spec.md) · [handoff.md](handoff.md). Requirements — by R-/AC- references only.

## State
- Branch `feat/copilot-05-speech-filter` from `feat/copilot-04-instant-answers` @ `f7e3f94` (v0.1.11).
- `say` voices on the Mac: Lesya (uk), Milena (ru), Samantha, Fred, Daniel, Karen (en), Anna (de), Thomas (fr).
  There is no second uk/ru voice — the "other voice" for uk/ru: Milena↔Lesya and a pitch shift; the live check — H-2.

## Owner points
| H | When | Action |
|---|---|---|
| H-0 | Before P-00 | Accept intent/spec/plan |
| H-1 | After stage 1 (build 0.2.0) | 5 minutes with a TV in another language in the "Mac microphone" mode — is the foreign language gray? |
| H-2 | After stage 3 | Record a voice sample; 10 minutes with a TV and a person nearby (AC-07) |
| H-3 | P-09 | Acceptance per report.md |

## Steps
Each step: code → checks → handoff → commit `P-xx: …`; push — on the owner's command.

**P-00. Baseline.** `swift test`, evals, the 0.1.11 test call — numbers in the handoff.

**P-01. The set and the `filter` eval.** `scripts/make-filter-fixtures.sh`: "question + background" mixes (a de/fr/en TV with `say` voices,
synthesized music and noise, a second voice), 16 kHz mono, in `evals/audio/filter/`; a manifest with expectations (keep/drop,
reason). `copilot-eval filter` — AC-01…AC-04 per channel. A baseline before the filters.

**Stage 1 — no new models except the VAD, build 0.2.0, H-1**
- **P-02. Language filter and terms** — R-05, R-06, R-09: `LanguageGate` (CopilotCore, pure logic + tests),
  `Resources/terms-en.txt`, a dictionary from the résumé/job/bank, gray lines in the panel, S-08.
- **P-03. Silero VAD** — R-02, R-08: a model manifest and installer, `VadManager` in the stream, a toggle; the turn eval
  no worse (0% / 0%), AC-04.

**Stage 2 — the owner's voice, build 0.2.1**
- **P-04. Sample and voice filter** — R-03, S-03, S-09: a sample recording window, CAM++, a threshold from the eval (AC-03),
  self-check and the AI interview (R-01).

**Stage 3 — noise and echo suppression, build 0.2.2, H-2**
- **P-05. LocalVQE** — R-04, S-06: the 16 ms streaming mode, reference = call audio; AC-05, AC-06.

**Stage 4 — the owner's speech as context, build 0.2.3**
- **P-06. The microphone channel on a call** — R-01, R-07, S-07: transcribing the owner's speech, a `<candidate_said>` block,
  a prompt test.

**P-07. Measurements.** The `filter` eval, the test call, `metrics.py`, `footprint-monitor.sh 10`.
**P-08. Review** with a fresh context on the branch against the spec, fix P0/P1.
**P-09. Report** `report.md`, ADR-0001 (models), evals/README (thresholds). H-3.

## Risks
| Risk | Sign | Action |
|---|---|---|
| Parakeet writes Ukrainian speech "in Russian" | False drops | uk/ru are one group (Q7), already built in |
| Short phrases: the language is not detected | False drops of short questions | R-05: do not drop < 3 words |
| Synthetic voice ≠ live voice | The voice threshold does not fit | A threshold from H-2, a sensitivity slider in Audio |
| LocalVQE (beta) distorts speech | Microphone WER grows | Compare WER with and without it; off by default if worse |
| Memory | > 1.5 GB | Switch off LocalVQE when short of memory; the models are small (VAD ~2 MB, LocalVQE 4.8 M parameters) |

## Done when
AC-01…AC-08 with evidence in report.md, a review without P0/P1, the owner confirmed H-3.
