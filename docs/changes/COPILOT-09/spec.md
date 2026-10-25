# COPILOT-09: Specification — a live assistant on the ParakeetAI level

ID: COPILOT-09-spec · Status: **accepted** (2026-10-24) · Version: 1 · Date: 2026-10-24 · Owner: itmax04
Links: [intent.md](intent.md) · [plan.md](plan.md)

## Requirements
### Session (stage 1)
- **R-01. The "Create session" wizard** (menu, ⌃⌥N, the R-05 notification): the "Details" step — the Interview / Regular / Mock type, the profile,
  the company, the vacancy (text or "Paste a vacancy link", R-04); the "Settings" step — the language, the model (the first in the chain),
  answer settings (R-12), session instructions, Auto Generate, "Save the transcript", "Review after End", a duration plan.
  The draft is kept when moving between steps; the last values are the defaults for the next session.
- **R-02. Lifecycle**: no session → not listening (the menu "Create session…"); Start — capture and recognition; End — stop,
  saving as chosen, the review in the background. States: draft, starting, active, ending, ended, failed — with a clear error.
  "New interview" is replaced by End + a new session. A timer in the overlay; a plan — a warning 5 minutes before.
- **R-03. A pre-start check**: the microphone (level), the call audio (whether there is a signal in the selected app), the recognition
  model, the model keys, the screen recording permission — separate lines with a reason and a "Fix" action.
- **R-04. Importing a vacancy from a link**: loading the page (URLSession, no sign-in), the page text → the model → the company and
  the description; an error or a page behind a sign-in (LinkedIn) — "paste the vacancy text".
- **R-05. Call auto-detection**: when call audio appears in Zoom / Meet (Chrome) / Telegram and there is no session —
  a notification "Start a session?" with the last settings (no more than once in 10 minutes per app).
- **R-06. Types**: Interview — as now (résumé, cards, materials); Regular — "what to say" in the first person on the topic,
  instructions and materials, without the résumé and cards, the review — a summary and agreements; Mock — launching the AI interview.

### Live overlay (stage 2)
- **R-07. Layout**: an action bar (microphone and call indicators, Answer ⌘↩, Screenshot ⌘⇧↩, Chat ⌘⇧Space, move,
  collapse, timer, the ⋮ menu, End); a transcript line (the last line, expands into a list, "Clear" ⌘⇧⌫);
  the question detection status; the answer card: "Question: <short>", the answer, ←/→ (⌘←/→) through the history, copy, expand.
- **R-08. States**: "Listening", "Checking…" (a turn pause / a speculative request is running), "Question detected", "Not a question",
  "Preparing an answer…" (a new request has its own title; the previous answer is dimmed and labeled "previous"), "Error" with
  a reason and "Retry"; the source: "no signal for N s", "recognition is restarting". Only the owning request changes the card.
- **R-09. The session answer history**: ←/→, the position "3 / 7"; a new answer while viewing an old one — a "new answer ↓" badge,
  without a jump. Scrolling during generation — follow until the user scrolls up.
- **R-10. Chat** (⌘⇧Space, a field in the overlay, focus only when opened): a new question; refining the current one ("shorter", "without Kafka")
  — a new version of the same question; quick buttons "Shorter / More detail / Example"; "/always …" — a session instruction
  (a badge in the overlay, removed with a click).
- **R-11. The overlay menu**: Auto Generate, language, scale +/−/reset, "Move to another display", Private (R-17), "End session".
  ⌘ keys — only during an active session; ⌃⌥ stay.

### Answers (stage 3)
- **R-12. Answer settings**: format (script + bullets / bullets only / a continuous script), length (short / balanced
  / detailed), tone (formal / neutral / friendly); a live preview — the model's answer to a sample of the selected question
  type (behavioral, technical, about yourself) based on the active profile; "Save" (session) and "Default".
  The owner's instructions take precedence (08/R-04).

### Review (stage 4)
- **R-13. After End** in the background: an AI comment on each of your answers (what was good, what was missing, how to say it better),
  an overall summary (topics, strengths and weaknesses, next steps; for Regular — a summary and agreements).
- **R-14. The session window**: the tabs "Summary" (question → your answer → comment → the hint shown), "Transcript"
  (Interviewer / You, time, hints separately), "Ask AI" (a chat about this session). Review progress; an error does not hide the transcript.

### Screenshots and context (stage 5)
- **R-15. A screenshot task**: a thumbnail in the overlay; a shot within 30 s goes to the same task (up to 3), later — a new one; the active
  task is in the interview memory (the problem, the solution in brief), voice follow-ups "what if…", "complexity?" refer to it.
- **R-16. Context**: "Clear" clears the line and the "last lines" for the next answer (the memory and history stay);
  a topic change does not pull in old content (07/R-03); a follow-up without an explicit reference ("why so?") refers to the last answer.

### Privacy (stage 2)
- **R-17. Private**: the overlay window is excluded from screen capture (`sharingType`); a "Check visibility" button takes a
  screen capture through ScreenCaptureKit and reports whether the overlay is visible in the capture — with the macOS version; the interface has no promise of
  "invisible to everyone". Storage: "Save the transcript" (R-01), deleting a session with its review and screenshots.

## Acceptance criteria
| AC | Criterion | Check |
|---|---|---|
| AC-01 | Wizard: the draft across steps, validation, last values; Start/End and states | `swift test` (session model) |
| AC-02 | The pre-start check distinguishes "no permission" from "no signal" | `swift test`, manual |
| AC-03 | An answer belongs to its request: a double press, a new question during an answer — no mixing | `swift test` |
| AC-04 | The Checking / Question detected / No question / Preparing states — by events | `swift test` |
| AC-05 | The answer history, a Chat refinement creates a version, a session instruction takes effect | `swift test`, `--smoke` |
| AC-06 | Answer settings change the form, not the facts (short ≤ 40 words, no lists for "script") | `--smoke-memory` |
| AC-07 | Review: a comment on each recorded answer, a summary; a review error does not lose the transcript | `swift test`, `--smoke` |
| AC-08 | A screenshot + the voice follow-up "and the complexity?" answers about the same task | `--smoke` |
| AC-09 | Private: the visibility check gives an honest result on this Mac | manual (owner) |
| AC-10 | No regressions: tests, evals, secret-scan, build; first-word latency no worse than 07 | full check |
| AC-11 | Owner: a call or a self-check with a session from the wizard to the review | owner |
