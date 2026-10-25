# COPILOT-12: Spec

ID: COPILOT-12-spec · Status: **accepted** · Version: 1 · Date: 2026-10-25
Links: [intent.md](intent.md), [plan.md](plan.md), [handoff.md](handoff.md)

## Requirements
| ID | Requirement |
|---|---|
| R-01 | Capture start/stop must not race: a stop requested at the end of a session cannot overtake the next start, and a late start cannot resume capture after a stop. `ListeningController` keeps a capture intent (`captureWanted`) and every async step checks it |
| R-02 | "Delete all history" removes every session file in the sessions folder, including files that no longer decode (damaged or an old format) — no transcript may stay on disk |
| R-03 | Provider error texts shown in the UI and the log never contain account identifiers (`org_…`) or key-like strings (`gsk_`, `sk-`, `sk-ant-`, `csk-`, `AIza…`); plain-text error bodies are shown (trimmed), HTML pages are not |
| R-04 | Groq `gpt-oss` requests reserve 512 reasoning tokens for hints and 1 024 for screenshots: Groq counts the requested maximum against the per-minute token budget (8 000 on the free tier) |
| R-05 | The answer kind label next to the model name is localized (it was English, `generated`, in the Russian UI) |
| R-06 | App wiring: the overlay resize callback is installed once; menu actions are handled exhaustively (no `default:` that hides a new case) |
| R-07 | Repository hygiene: generated files are not tracked (`scripts/__pycache__/` was committed by mistake); `.gitignore` covers them |
| R-08 | Every repository document is in English: `README.md`, `CLAUDE.md`, `AGENTS.md`, `docs/ARCHITECTURE.md`, `docs/decisions/`, `docs/changes/COPILOT-01…12`, `docs/design/` (HTML and PDF), `evals/*.md`, comments in configuration files. Quoted interview phrases, UI labels and test data stay as data |
| R-09 | `AGENTS.md` at the repository root: what the app is, working agreements, setup, repository map, architecture, key components, data on disk, conventions, recipes for common changes, verification, debugging, the task process, limitations, a glossary |
| R-10 | All branch names are English; all feature branches are pushed; `main` is fast-forwarded to `feat/copilot-12-final-review` and pushed (owner decision Q1) |
| R-11 | Version 0.15.1 (build 37) |

## Acceptance criteria
| ID | Criterion | How to check |
|---|---|---|
| AC-01 | The capture intent flag guards every async start/stop path | code review of `ListeningController`, `swift test` |
| AC-02 | Unreadable session files are removed by "Delete all" | `deleteAllRemovesUnreadableFilesToo` |
| AC-03 | Errors hide `org_…` ids and key-like strings, show plain text, hide HTML | `ProviderErrorTests` |
| AC-04 | Groq hint budget 400 + 512 = 912, screenshot 400 + 1 024 = 1 424 | `groqReasoningHeadroomIsSmallerForHints`, `FastProvidersTests` |
| AC-05 | No tracked generated files | `git ls-files` |
| AC-06 | No Cyrillic in documents except quoted data; no broken relative links in Markdown | a script over `git ls-files` (handoff) |
| AC-07 | The full CLAUDE.md check passes | command output in the handoff |
| AC-08 | Remote `main` and `feat/copilot-12-final-review` point to the same commit; every local branch is on the remote | `git ls-remote` |
