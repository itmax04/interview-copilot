# COPILOT-12: Intent — final review, fixes and the GitHub repository

ID: COPILOT-12-intent · Status: **accepted** (2026-10-25: the owner's request) · Version: 1 · Date: 2026-10-25 · Owner: itmax04
Links: [spec.md](spec.md), [plan.md](plan.md), [handoff.md](handoff.md)

## Problem
After COPILOT-11 the app is feature-complete for the owner's use, but:
- the code has not had a whole-project review since COPILOT-07; COPILOT-08…11 added a lot of new code;
- the GitHub repository is not in a state a newcomer can use: `main` holds only the initial commit, the work lives on a chain
  of eleven feature branches, and most documents (README, architecture, task history) are in Russian;
- there is no single document that explains the project to an AI agent or a developer who starts without context.

## Desired outcome
1. A full audit of the project: architecture, functionality, code quality, stability, readiness.
2. Every issue found is fixed, and the fixes are verified so that nothing else breaks.
3. The GitHub repository holds the current version of the app with a clear structure; `main` is that version.
4. A detailed document for AI agents and developers: purpose, architecture, folders, how the parts connect, installation,
   setup and running, technologies, how to change and extend the app.
5. All branches and documents of the repository are in English: branch names, README, documentation, the agent document and
   every other repository document.
6. A final verification of all of the above.

## Owner decisions (2026-10-25)
| # | Question | Decision |
|---|---|---|
| Q1 | What happens to `main` | "Fast-forward main" (the recommended option): after the audit and checks `main` is fast-forwarded to the final branch; history is not rewritten, all feature branches stay |

## Executor decisions (the owner asked not to ask extra questions)
- Code comments and UI string keys stay in Russian. They are code, not documents: the localization design (COPILOT-10) uses the
  Russian text as the key, and the English UI comes from `Resources/en.lproj/Localizable.strings`.
- Old commit messages stay as they are (some are in Russian): rewriting history is forbidden by the project rules.
- Russian, Ukrainian and English text inside test data stays: eval sets, fixtures, `profile.example/`, quoted interview
  phrases and UI labels inside documents are data the app works with.
- The old feature branches are kept as historical snapshots; their names are already English. The current English version
  of every document lives in `main`.
- The COPILOT-02 documents existed only on the separate `docs/copilot-02` branch; their English translation is added to
  `docs/changes/COPILOT-02/` so the task history in `main` is complete.
- No CI (the full check needs Xcode 26, local model files and a signing identity); listed as a limitation.
- License: MIT (`LICENSE`), added at the owner's request on 2026-10-25.

## Scope
In: the audit, fixes with tests, repository hygiene, English documentation, `AGENTS.md`, the version bump, the full check,
pushing the branches and fast-forwarding `main`. Out: new features, new dependencies, changes to TCC and the Keychain,
rewriting history, deleting branches.
