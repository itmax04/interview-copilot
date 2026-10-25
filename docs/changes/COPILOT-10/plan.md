# COPILOT-10: Plan

ID: COPILOT-10-plan · Status: **accepted** (2026-10-25) · Date: 2026-10-25
Links: [intent.md](intent.md) · [spec.md](spec.md)

| Step | What | Requirements | Check |
|---|---|---|---|
| P-01 | Stage 1. Theme: settings, dynamic tokens, "General", a dark overlay, dark snapshots | R-01, R-02, R-03 | `swift test`, `dark-*` snapshots |
| P-02 | Stage 2. Language: L10n, overloads, window roots, menu, core, review, onboarding, pages, a ~780-string table, a check script, English snapshots | R-03…R-09 | `swift test`, `scripts/check-localization.sh`, `en-*` snapshots |
| P-03 | Version 0.14.0, the full check, handoff; H-1 — the owner's live check (switching the theme and the language in the running app) | all | the full CLAUDE.md check |

Risks: a new string without a translation shows in Russian in the English interface — caught by `check-localization.sh`; strings
glued from pieces (`"…" + "…"`) are not translated — UI texts are written as one string.
