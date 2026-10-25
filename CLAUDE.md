# Interview Copilot — project instructions

## Project
Native macOS app in Swift 6 (SwiftUI + AppKit), built with SwiftPM, no `.xcodeproj`.
Read `AGENTS.md` first (purpose, setup, repository map, architecture, conventions, recipes, checks), then
`docs/ARCHITECTURE.md` for module details. Stack and reasons — `docs/decisions/ADR-0001-stack.md`.
Tasks live in `docs/changes/COPILOT-NN/` (intent → spec → plan → handoff); the latest has the highest number
(currently COPILOT-12).

## Checks
- Quick: `swift build && swift test`
- Full: `swift test && scripts/run-evals.sh && scripts/secret-scan.sh && scripts/check-localization.sh && scripts/build-app.sh`
- Commands appear step by step in plan.md; if a command does not exist yet, write NOT RUN — never invent a result.

## Rules
- Answer the owner in Russian. Repository documents, branch names, commit messages and PR texts are in English.
- Never write API keys or personal data (résumés, transcripts) into code, logs, tests, commits or messages.
  Test data is synthetic only, from `profile.example/` and `evals/`.
- A new task gets its own branch `feat/copilot-NN-<short-name>` from the previous task's branch. Commit after every step;
  `git push` only when the owner has allowed it.
  Forbidden: force-push, `reset --hard`, deleting branches, rewriting history, merging into `main` without the owner's decision.
- New dependencies — only those listed in ADR-0001; anything else requires an ADR entry and a note in the handoff.
- Models and downloads: Whisper/embedding/speech models and SwiftPM/Homebrew dependencies may be downloaded.
  Verify downloaded files by SHA256.
- Do not touch system security and privacy settings (TCC, Keychain trust): the owner does that by hand.
- Questions to the owner — only at the H-… checkpoints of the current plan.md. Resolve other ambiguities yourself using
  the spec, the design and Apple HIG, and record the decision in handoff.md ("Executor decisions").
- After every step update the current task's `handoff.md`: what was done, commit, checks (PASS/FAIL/NOT RUN), next step.

## Design
- Source: the COPILOT-09 redesign — ImageGen references P00–P19 (`docs/design/redesign/prompts.md`; comparison with the
  implementation — `docs/design/copilot-09/stage6/`); tokens and components — `Sources/InterviewCopilot/Design/DesignSystem.swift`
  (`IC`, `ICDark`). Deviations from the references are listed in `docs/changes/COPILOT-09/handoff.md`. The menu-bar menu
  follows `docs/design/menu-v2.webp`.
- The owner's global frontend rules (21st.dev, component.gallery, Kinetics, DESIGN.md) apply to the web and do not apply
  to this native project — the style source here is Apple HIG plus the references. Owner decision of 2026-10-06.
- Window colors only via `IC` tokens (light and dark, COPILOT-10); the overlay is always dark (`ICDark`).
- UI strings are Russian in code, as one literal (never concatenate `"…" + "…"`); strings built in code use `L("…")` /
  `L10n.t`/`f`. Add the English translation to `Resources/en.lproj/Localizable.strings`; check with
  `scripts/check-localization.sh`.
- Animations: system ones; respect Reduce Motion (`accessibilityReduceMotion`).

## Done when
The acceptance criteria of the current spec.md are backed by evidence in its handoff.md (or report.md), unverified items
are listed, and the owner has accepted the result.
