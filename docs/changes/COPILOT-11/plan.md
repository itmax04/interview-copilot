# COPILOT-11: Plan

ID: COPILOT-11-plan · Status: **accepted** (2026-10-25) · Date: 2026-10-25
Links: [intent.md](intent.md) · [spec.md](spec.md)

| Step | What | Requirements | Check |
|---|---|---|---|
| P-01 | An analysis of the test call history and the log: the cause of the interruption | — | the `llm` log, session 2026-10-25T08-22-18 |
| P-02 | Chain: last resort, hedge to another provider, screenshots, the Gemini timeout floor | R-01…R-04 | `ChainResilienceTests`, `swift test` |
| P-03 | The "have you worked with X" rule + a live scenario | R-05 | `--smoke-memory` (5/5), `ExperienceRuleTests` |
| P-04 | Resizing the overlay with the mouse | R-06 | `--smoke-panel-resize`, `PanelResizingTests`, snapshots |
| P-05 | Version 0.15.0, the full check, handoff; H-1 — the owner's live check | all | the full CLAUDE.md check |
