# COPILOT-12: Plan

ID: COPILOT-12-plan · Status: **accepted** (2026-10-25) · Date: 2026-10-25
Links: [intent.md](intent.md) · [spec.md](spec.md)

| Step | What | Requirements | Check |
|---|---|---|---|
| P-01 | Audit: read the whole codebase (core, app, scripts, tests), the documents and the Git state; list findings by severity | — | the findings list in the handoff |
| P-02 | Fix the findings, add tests | R-01…R-07 | `swift test`, no compiler warnings |
| H-1 | The owner decides what happens to `main` | R-10 | the owner's answer ("Fast-forward main") |
| P-03 | `AGENTS.md`; README, CLAUDE.md, architecture, ADR, evals in English | R-08, R-09 | link check |
| P-04 | Task history COPILOT-01…11 and the design research in English; COPILOT-02 added to the chain; COPILOT-12 documents | R-08 | Cyrillic scan, link check |
| P-05 | Version 0.15.1 (build 37), the full check | R-11, AC-07 | the full CLAUDE.md check |
| P-06 | Commit, push the branches, fast-forward `main`, push `main`, verify the remote | R-10, AC-08 | `git ls-remote` |
| H-2 | The owner's live check of 0.15.1 | — | the owner |

Risks: a translated document could lose a fact — the translation keeps every number, identifier, file name and table row;
a fast-forward fails if `main` has commits that are not in the chain — then stop and ask the owner (no merge commit,
no force-push).
