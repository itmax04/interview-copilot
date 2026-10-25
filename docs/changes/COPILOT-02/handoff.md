# COPILOT-02 handoff

ID: COPILOT-02-handoff · Status: **draft — awaiting H-0** · Version: 1 · Updated: 2026-10-22
Documents branch: `docs/copilot-02` (from `feat/copilot-01` @ `3b690fc`) · Working branch after H-0: `feat/copilot-02` (Q4)
Goal and scope: [intent.md](intent.md), requirements: [spec.md](spec.md), steps: [plan.md](plan.md),
prompt: [executor-prompt.md](executor-prompt.md).

> Repository note (COPILOT-12): H-0 never happened — the task was superseded by COPILOT-03 and COPILOT-05, and the
> `feat/copilot-02` branch was never created. The original Russian documents stay on the `docs/copilot-02` branch.

## Done
- 2026-10-22: a review of the Parakeet v3 integration (the code `feat/copilot-01` @ `3b690fc`, the FluidAudio 0.17.7 sources);
  as a result intent, spec, plan, executor-prompt and this file were created. The app code was not changed.

## Current step
H-0 — the owner accepts the documents and answers Q1–Q6 (intent.md). P-00 has not started.

## Checks
| Step | Command | Commit | Result |
|---|---|---|---|
| — | — | — | NOT RUN (the task code has not been written yet) |

## Baseline
Filled in at P-00 and P-01.

| Date | Commit | Set | Engine | RU | UK | EN | Final median |
|---|---|---|---|---|---|---|---|
| 2026-10-08 | v0.1.2 (`3b690fc`) | The test call, 15 phrases | Parakeet v3 | 7/96 (7.29%) | 9/97 (9.28%) | 4/123 (3.25%) | 501 ms |

## Executor decisions
A reference to R-/AC-, the date, the decision, the reason.

- 2026-10-22, R-09 / intent item 6 (a review refinement): the "Accurate final text" toggle in Settings → Audio is already
  shown only for Whisper (`OtherSettingsViews.swift`, the `recognitionBackend == .whisper` branch), so
  it is not in the requirements. The "Hint the bank wordings to recognition" toggle is inactive for Parakeet —
  the loss of the hint is visible in the interface, but there is no replacement (R-03, R-04).
- 2026-10-22, R-01: there is no fixture generation script for `evals/audio/test-call/` in the repository (there is only
  `scripts/make-audio-fixtures.sh` for `evals/audio/`); creating it is part of P-01.

## Open questions
- Q1–Q6 (intent.md) — until H-0.

## Permissions
- Allowed: code, tests, scripts and synthetic fixtures; commits and `git push` to `feat/copilot-02`; models from ADR-0001
  (CTC 110M — if Q3 = yes).
- Not allowed: force-push, `reset --hard`, deleting branches, merging into `main` / `feat/copilot-01`; TCC and Keychain trust;
  changing the owner's original models and profile; cloud services; publishing.

## Risks and rollback
The return point: `feat/copilot-01` @ `3b690fc`. Rolling back a step — `git revert` of its commit.
