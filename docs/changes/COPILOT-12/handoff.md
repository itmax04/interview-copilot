# COPILOT-12 handoff

ID: COPILOT-12-handoff · Status: **done (0.15.1, build 37) — `main` fast-forwarded; H-2: the owner's live check** · Updated: 2026-10-25
Branch: `feat/copilot-12-final-review` (from `feat/copilot-11-test-call-fixes` @ `ea56b47`)
Links: [intent.md](intent.md), [spec.md](spec.md), [plan.md](plan.md); onboarding — [AGENTS.md](../../../AGENTS.md)

## Audit (P-01)
The whole codebase was read: `CopilotCore` (audio, recognition, filters, turns, bank, profiles, LLM chain, memory, review,
session, storage, localization), the app target, `copilot-eval`, scripts, tests, documents and the Git state.

| Severity | Finding | Outcome |
|---|---|---|
| High | Capture start/stop race: `End` starts an async stop and the next `Start` (or a resume after a pause) an async start; a slow stop could finish after the new start and leave the session without audio, and a late start could resume capture in standby | Fixed — R-01 |
| High (privacy) | "Delete all history" deleted only the sessions that `list()` could decode; damaged or old-format files (with transcripts) stayed on disk | Fixed — R-02 |
| Medium (privacy) | Provider error bodies were shown and logged as is: Groq 429 texts include the organization id (`org_…`), some proxies echo the key; plain-text bodies were dropped, so a useful reason was lost | Fixed — R-03 |
| Medium | Groq `gpt-oss` requests asked for `maxTokens + 1024`; Groq counts the requested maximum against the 8 000 tokens-per-minute free budget, so with ~6 k prompt tokens every hint cost a full minute of a key | Fixed — R-04 (512 for hints; the live COPILOT-11 test never used more than 423 reasoning + answer tokens) |
| Low | The answer kind label next to the model name showed the internal English value (`generated`) in the Russian UI | Fixed — R-05 |
| Low | The overlay resize callback was reinstalled on every settings change; `handle(MenuAction)` had a `default:` that would silently swallow a new action | Fixed — R-06 |
| Low | `scripts/__pycache__/*.pyc` were committed by mistake in `f8b1d15` | Fixed — R-07 (untracked, ignored) |
| Repository | `main` held only the initial commit; README, architecture and task history were in Russian; COPILOT-02 existed only on a side branch; there was no onboarding document | Fixed — R-08…R-10 |
| Info | No compiler warnings in a clean build; no TODO/FIXME left in code; no secrets in the tree (`secret-scan.sh`) | — |
| Info | No LICENSE and no CI | Not changed: the license is the owner's choice; the full check needs Xcode 26, local models and a signing identity. Listed in `AGENTS.md` §12 |

## Done
- P-02, commit `f8b1d15` — fixes:
  - `ListeningController`: `captureWanted` is set by `start()`, resume and the test call start, cleared by standby, pause and
    shutdown; `applySource` returns early when capture is not wanted and stops a capture that finished starting after the
    intent changed; the standby/pause tasks re-apply the source if capture is wanted again; `captureStopped` restarts only
    while capture is wanted. The test call restores the intent it found (`!standbyBeforeTest && !pausedBeforeTest`).
  - `SessionStore.deleteAll()` removes every `*.json` in the sessions folder under the store lock.
  - `SSE.errorMessage`: plain-text bodies are shown (up to 200 characters), HTML is not; `redactIdentifiers` replaces
    `org_…` with `org_[id]` and key-like strings with `[key]`.
  - `OpenAICompatibleProvider.reasoningHeadroom(_:)`: 512 for hints, 1 024 for screenshots.
  - `AnswerController.kindTitle(_:)`: localized labels for `generated`, `strong`, `screenshot` and refinements.
  - `App`: `panel.onResizedByUser` is set once at launch; `handle(MenuAction)` lists every case.
  - Tests: `ProviderErrorTests` (4), `deleteAllRemovesUnreadableFilesToo`; `FastProvidersTests` expects `400 + 512`.
- H-1 (2026-10-25): the owner chose "Fast-forward main (recommended)".
- P-03, commit `3c1c800` — `AGENTS.md` (13 sections); `README.md`, `CLAUDE.md`, `docs/ARCHITECTURE.md`,
  `docs/decisions/ADR-0001-stack.md`, `evals/README.md`, `evals/live-script.md` and COPILOT-01 in English;
  `CLAUDE.md` now says: answer the owner in Russian, repository documents, branch names, commit messages and PR texts in English.
- P-04 — COPILOT-03…11 (intent, spec, plan, handoff) in English; COPILOT-02 translated from the `docs/copilot-02` branch and
  added to `docs/changes/COPILOT-02/`; `docs/design/redesign/research.pdf` re-rendered from the English `research.html`
  (headless Chrome); comments in `.gitignore`, `models.sha256`, `filter-models.json`, `Resources/pricing.json` in English;
  `scripts/__pycache__/` untracked and ignored; these COPILOT-12 documents.
- P-05 — version 0.15.1 (build 37).

## Executor decisions
- Russian stays only where it is data or code: UI string keys (the COPILOT-10 design — the Russian text is the key, English
  comes from `Localizable.strings`), code comments and test suite titles, script messages, eval sets and fixtures,
  `profile.example/` (a synthetic Russian/Ukrainian candidate the tests use), the interviewer and test call pages (their
  English comes from `en.json`), and quoted interview phrases and UI labels inside documents.
- Old commit messages are not rewritten (forbidden by the project rules). New commits are in English.
- The old feature branches stay untouched as snapshots of each task; their names are English. Adding translation commits on
  top of them would fork the chain, so the English versions live in `main` only.
- The fast-forward uses `git merge --ff-only`: if `main` ever gets a commit outside the chain, the command fails instead of
  creating a merge commit.

## Checks (2026-10-25)
| Command | Result |
|---|---|
| `swift test` | PASS — 361 tests in 56 suites |
| `scripts/run-evals.sh` | PASS — turn 0%/0% (596 ms), bank top-1 94.9% / 0 false, filter-text 214/214, memory 8/8 and 0/2, materials 23/24 and 2/8 |
| `scripts/secret-scan.sh` | PASS — 0 findings |
| `scripts/check-localization.sh` | PASS — 796 keys, 796 translations, 0 missing, 0 format mismatches |
| `scripts/build-app.sh` | PASS — `dist/InterviewCopilot.app` 0.15.1 (37), `codesign --verify --strict --deep` OK |
| Cyrillic scan of tracked documents | PASS — 57 Markdown/HTML documents; the only Cyrillic left is quoted interview phrases, UI labels, language names (Українська / Русский), alphabet letters and the phrases of `evals/live-script.md` that are read aloud in a live test |
| Relative links in all Markdown files | PASS — 62 files, 0 broken |
| `git ls-remote` after the push | PASS — see "Repository state" |

## Acceptance
| AC | Evidence | Status |
|---|---|---|
| AC-01 | `ListeningController` review, `swift test` | PASS (tests); a live session start/stop — H-2 |
| AC-02 | `deleteAllRemovesUnreadableFilesToo` | PASS |
| AC-03 | `ProviderErrorTests` | PASS |
| AC-04 | `groqReasoningHeadroomIsSmallerForHints`, `FastProvidersTests` | PASS |
| AC-05 | `git ls-files` has no generated files | PASS |
| AC-06 | the Cyrillic scan and the link check | PASS |
| AC-07 | the full check | PASS |
| AC-08 | `git ls-remote` | PASS |

## Repository state
Every local branch is on GitHub (`git ls-remote --heads origin`, 2026-10-25, after commit `9f05fcf`):

| Branch | Head |
|---|---|
| `main` | `9f05fcf` — fast-forwarded from `f82f8c2` (the initial commit) with an ff-only update, no merge commit, no force-push |
| `feat/copilot-12-final-review` | `9f05fcf` (new) |
| `feat/copilot-11-test-call-fixes` | `ea56b47` (new) |
| `feat/copilot-10-theme-language` … `feat/copilot-01` | unchanged (`9dcf965`, `e1b0bad`, `1f88465`, `ab4b53f`, `f76c8ca`, `ff1b27b`, `f7e3f94`, `b32fdec`, `3b690fc`) |
| `docs/copilot-02` | unchanged (`9576cdf`) |

This commit only adds the table above; `main` is fast-forwarded to it the same way, so `main` and
`feat/copilot-12-final-review` end on the same commit.

## Not verified
- A live call with 0.15.1 (session start/stop timing, the Groq budget under real limits, the localized answer label): there is
  no call audio, microphone input or screen input in this environment.

## Next step
H-2: the owner installs 0.15.1 (`~/Downloads/InterviewCopilot.app`), runs a session from the wizard to the review, ends it
and starts another one right away (the start/stop race), and checks "Delete all history" in the main window → Sessions.
