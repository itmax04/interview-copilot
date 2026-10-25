# COPILOT-01: Intent — an interview assistant for macOS (v1)

ID: COPILOT-01-intent · Status: **accepted** (2026-10-06) · Version: 1 · Date: 2026-10-06
Result owner: itmax04 · Links: [spec.md](spec.md), [plan.md](plan.md), [ADR-0001](../../decisions/ADR-0001-stack.md)
Source of decisions: the owner's answers to questions Q1–Q12 in the Claude Code session of 2026-10-06 (table below).
Approval: the owner (itmax04) accepted version 1 of the set — intent, spec, plan, ADR-0001, evals/README, executor-prompt —
together with assumptions A-1…A-4 and the design deviations. The answer "I accept" in the Claude Code session 2026-10-06, after commit `2f76499`.

## Problem
In online interviews (Google Meet, Zoom, Telegram) it is hard for the owner to quickly recall a prepared answer and to
phrase an answer to an unexpected question. Existing services (for example, Parakeet AI) are paid and keep the
conversation at a third party.

## Desired outcome
A personal macOS app that during a call:
1. listens only to the other person and shows the transcript (uk/ru/en) with a delay ≤ 1 s;
2. finds the question in the owner's answer bank and shows the prepared answer within ≤ 0.5 s;
3. if the question is not in the bank, generates a hint according to the selected mode (first words ≤ 2.5 s)
   through Gemini Flash (free) with fallback to DeepSeek or Claude;
4. on a hotkey sends a screenshot of a task to a strong model and shows the solution.

Observable metrics and checks — AC-01…AC-14 in spec.md.

## Users and systems
- User: one (the owner). MacBook Air M1, 8 GB, macOS 15.7.2.
- Systems: macOS (ScreenCaptureKit, AVFoundation, Keychain, TCC), whisper.cpp, a local embedding model,
  Gemini API, DeepSeek API, Anthropic API, GitHub (private repository `itmax04/interview-copilot`).
- Call platforms: Google Meet in Chrome (main for tests: Zoom is not installed), Zoom, Telegram.

## Scope
In v1:
- a menu-bar app and a floating panel (design from `docs/design/menu-v2.webp`);
- capturing the audio of the selected app, local uk/ru/en transcription, end-of-question detection;
- a question bank (`questions.yaml`), semantic search, modes "Bank only" / "Bank + hint" / "Generation";
- generation: Gemini → DeepSeek → Claude, streamed output, a manual call of the strong model;
- screenshot → strong model;
- settings, keys in the Keychain, session history, spending tracking, ⌃⌥ hotkeys;
- evals for bank search and end-of-question detection.

Not in v1 (candidates for next intents):
- hiding the panel from screen sharing (Q3 — no);
- Jev and automatic classification of "hard" questions;
- a training mode (the menu item is inactive, "soon");
- multiple profiles (one profile in v1);
- Windows, distribution, notarization, auto-update, paid accounts;
- speech output (TTS) and audio recording.

## Constraints
- Memory: the whole app with models ≤ 1.5 GB (the 8 GB Mac is shared with a browser and the call).
- Budget: testing on free Gemini ($0). Paid providers are connected with keys later;
  their monthly spending limit is $5 by default (configurable).
- Data: the owner allowed sending the résumé and transcripts to Gemini and DeepSeek (Q6).
  Emails, phone numbers and links from the profile are removed before sending by default.
- Keys never get into the repository, logs or chat.
- Tools: Swift 6 CLT are installed; Xcode is installed if it cannot be avoided (Q10) — the owner installs it.
- Git: private repository, work in the `feat/copilot-01` branch, no force-push (Q11).
- Executor: Claude Code, `claude-opus-5-5`, effort high (Q8). Questions to the owner — only at points H-0…H-5 (Q9).
- Usage risk: using it in real interviews may violate an employer's rules — the owner's decision and responsibility;
  it does not affect the technical solution.

## Owner decisions (2026-10-06)
| # | Question | Decision |
|---|---|---|
| Q1 | What is the project | An interview assistant for macOS (not a website from Figma) |
| Q2 | v1 scope | As proposed; generation — Gemini with fallback to DeepSeek or Claude |
| Q3 | Hide from screen sharing | No |
| Q4 | Languages | Ukrainian, Russian, English |
| Q5 | Keys and budget | Free Gemini for testing |
| Q6 | Data to Gemini/DeepSeek | Allowed |
| Q7 | Design | As in the generated images |
| Q8 | Executor | `claude-opus-5-5`, effort high |
| Q9 | Manual action points | Agreed: pause + instructions |
| Q10 | Downloads, dependencies, Xcode | Yes; do not look for workarounds without Xcode |
| Q11 | GitHub | Private repository, separate branch, no force-push |
| Q12 | Acceptance criteria | Agreed |

## Assumptions (not blocking, can be corrected at acceptance)
- A-1. The answer to Q2 reads as "the proposed v1 scope is accepted, the main model is Gemini".
- A-2. Answers are generated in the language of the question; bank cards are shown as the owner wrote them.
- A-3. Hotkeys use ⌃⌥ instead of ⌘ from the picture (conflicts with Chrome, Meet, VS Code); they can be remapped.
- A-4. The "Gemini quota 92%" line from the picture is replaced by a request counter: the Gemini API does not report the remaining quota.

## Open questions
No blockers. Non-blocking questions are checked in plan steps:
- whether Xcode is needed for tests (P-00 → H-0);
- whether whisper large-v3-turbo fits memory and latency on an M1 8 GB (P-04; on failure — the small model);
- which embedding model gives ≥ 85% on uk/ru/en paraphrases (P-06).
