# Handoff — COPILOT-16 (source and language)

## Identity
- Task COPILOT-16, branch `feat/copilot-16-source-language`, HEAD c6b20bf. Not pushed, no PR.
- Task documents: `docs/changes/COPILOT-16/` — intent.md, spec.md, plan.md, handoff.md (the detailed handoff lives there).
- The earlier voice-gate side branch (`claude/stt-revision-voice-gate-193912`) is already contained in this branch.

## State
- Spec/plan written 2026-11-23 for the remaining scope: language gate on the `.call` channel (R-01/R-02), "auto" language
  lock (R-03/R-04), live silent-microphone notice (R-05), All-system-audio warning (R-06), eval cases (R-07).
- Owner decision 2026-11-23: Quick Start / Auto keep falling back to All system audio, with a warning.
- Checks at 9922aee: swift test 502 PASS, evals PASS, secret-scan PASS, localization PASS, build-app NOT RUN.

- P-02 done (d06921b: eval cases; filter-text failed 218/236 before P-03). P-03 done (see commit after d06921b): whole English
  dropped on `.call`; 504 tests PASS, filter-text 236/236, other evals unchanged.

## Next
P-04 `SessionLanguageLock` (R-03/R-04). Next owner checkpoint: H-1 live call.
