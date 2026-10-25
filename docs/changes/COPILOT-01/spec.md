# COPILOT-01: Specification v1

ID: COPILOT-01-spec · Status: **accepted** (2026-10-06) · Version: 1 · Date: 2026-10-06 · Owner: itmax04
Links: [intent.md](intent.md) (goal, scope, decisions Q1–Q12) · [ADR-0001](../../decisions/ADR-0001-stack.md) (stack) ·
[plan.md](plan.md) (implementation) · [evals/README.md](../../../evals/README.md) (datasets and thresholds)
This file is the only source of requirements. plan.md and handoff.md only reference R-/AC- numbers.

## 1. Terms
- **Session** — the period from "start listening" to "stop" or quitting the app.
- **Utterance** — continuous speech of the other person between pauses.
- **Turn** — an utterance recognized as a finished question or a line that needs an answer (R-05).
- **Card** — a bank entry: question phrasings and the owner's answer (R-06).
- **Provider** — Gemini, DeepSeek or Anthropic. **Chain** — the order of fallback between them (R-09).
- **Strong model** — the provider for "hard questions" and screenshots (Claude Sonnet 5.5 by default).

## 2. Scenarios
- **S-01. A question from the bank.** Given: a Meet call is running, mode "Bank only", the bank has "Расскажите о себе".
  When: the other person asks "Пару слов о вашем опыте?" and stops. Then: no later than 0.5 s later
  the panel shows the `about-me` card marked "Bank · 92%".
- **S-02. Not in the bank, mode "Bank only".** When: a question not in the bank is asked.
  Then: "Not in the bank" and the three closest cards with a match percentage; no request is sent to a model.
- **S-03. Not in the bank, mode "Bank + hint".** Then: Gemini generates the answer, the text appears as it is generated,
  label "Gemini · generated", first words no later than 2.5 s.
- **S-04. Gemini unavailable.** When: Gemini returned 429, 5xx, a network error or did not start answering within 4 s.
  Then: the same request goes to the next provider that has a key; the label shows the actual model.
  If there are no more keys — the message "Models unavailable: <reason>", and S-02 applies.
- **S-05. Strong model manually.** When: the owner presses ⌃⌥C or "↑ Claude" on the card.
  Then: the last question is sent to the strong model. If its key is missing — the button is disabled with the hint "No Anthropic key".
- **S-06. Task screenshot.** When: ⌃⌥S. Then: a screenshot of the display with the cursor, without the assistant panel, is sent
  to the strong model (without a key — to Gemini); the panel shows the solution: approach, code, complexity.
- **S-07. The owner speaks.** When: the other person stopped, but the owner is already speaking into the microphone.
  Then: the automatic answer does not start; ⌃⌥↩ always works.
- **S-08. Pause.** When: ⌃⌥P or "Pause listening". Then: capture and transcription stop, status "Paused",
  nothing is sent. Pressing again resumes.
- **S-09. First launch.** Then: a three-step wizard — permissions (screen and system audio recording, microphone),
  the Gemini key, model download with progress. Without the screen-recording permission listening is impossible, and this is shown explicitly.
- **S-10. Editing the bank.** When: the owner saves `questions.yaml`. Then: the bank is re-read and embeddings are recomputed
  in the background. Parse errors are shown in the menu ("Question bank: error on line N") while the previous working version stays active.
- **S-11. Language.** When: the question is in Ukrainian. Then: the transcript is in Ukrainian, matching works across all card
  languages, the generated answer is in Ukrainian.

## 3. Requirements

### Audio and recognition
- **R-01. Audio source.** Submenu "Listening — <app> ›":
  - Auto (default): the first running of zoom.us → Google Chrome → Telegram;
  - a specific running app;
  - "All system audio".

  The assistant's own audio is always excluded. Switching the source needs no restart.
- **R-02. Microphone.** Used only to detect the owner's speech (VAD).
  Not transcribed, not sent, not stored.
- **R-03. Recognition.** whisper.cpp per ADR-0001, local.
  - Language: Auto (uk/ru/en) / Українська / Русский / English — "Language" submenu.
  - Interim text updates in the panel; the final utterance text is fixed after a pause.
- **R-04. No audio is written to disk.** A ring buffer in memory ≤ 30 s. Following the owner's accuracy priority of 2026-10-08, closed phrases are additionally kept in queue memory until recognition finishes.

### Turn detection
- **R-05.** A turn is complete when all of the following hold:
  - the other person is silent ≥ T ms (700 by default, 400–1500 in settings);
  - the utterance has ≥ 3 words;
  - the owner is not speaking (R-02).

  ⌃⌥↩ ("Answer now") completes the turn immediately using the last utterance, even if not all conditions hold.
  The threshold T is tuned by the `turn` eval (evals/README.md).

### Question bank
- **R-06. Format** `profile/questions.yaml`:
  ```yaml
  - id: about-me            # unique, [a-z0-9-]
    questions: [ "Расскажите о себе", "Tell me about yourself", "Розкажіть про себе" ]
    answer: |               # text as is, Markdown: lists, **bold**
      • ...
    tags: [STAR]            # optional; STAR → show S/T/A/R chips
  ```
  Validation: unique id, ≥ 1 question, non-empty answer. Example — `profile.example/questions.yaml` (≥ 15 cards in three languages).
- **R-07. Search.**
  - Similarity of the turn ↔ every phrasing of every card; the maximum per card is taken.
  - A match if score ≥ threshold (0.85 by default, refined by the `bank` eval; configurable).
  - Otherwise — the top 3 cards. Search is local, no network.
- **R-08. Modes** ("Mode" submenu, "Bank + hint" by default):
  - "Question bank only" — S-01/S-02;
  - "Bank + hint" — S-01/S-03;
  - "Generate every answer" — generation on every turn; a found card is passed to the model as the basis of the answer.

### Generation
- **R-09. Chain.** Main — Gemini Flash, fallback — DeepSeek Flash, strong model — Claude Sonnet 5.5
  ("Models" submenu, model IDs are editable in settings).
  - Fallback order: Gemini → DeepSeek → Claude. Providers without a key are skipped.
  - Fallback triggers: HTTP 429/5xx, a network error, no first token within 4 s, `stop_reason = refusal`.
  - Errors 400/401/403 do not lead to a retry at the same provider: settings show "invalid key".
- **R-10. Streaming.** Text is shown as it arrives. A new turn cancels the unfinished generation of the previous one.
- **R-11. Prompt.** A system part (constant, cacheable) + profile (`resume.md`, `job.md`, `stories.md`) + up to 3 closest cards
  + the last 6 utterances + the current question. Model instructions:
  - answer in the first person, in the language of the question;
  - 3–6 bullets, ≤ 80 words;
  - rely only on profile facts; mark a missing fact "[уточнить]";
  - if the utterance is not a question and needs no answer — return exactly `—` (the panel then does not change).

  Profile and utterance text are data, not instructions. The model gets no tools.
- **R-12. Personal data filter.** Emails, phone numbers and URLs are removed from the profile before sending
  (Settings → Privacy, on by default).
- **R-13. Strong model manually** — S-05.
  - For Claude: Messages API, `max_tokens` 1024, minimal latency (thinking off or minimal effort).
  - Server-side fallback on refusal is on (`fallbacks: "default"`).
  - Exact parameters — per the current documentation (the `claude-api` skill) in step P-07.
- **R-14. Screenshot.**
  - ⌃⌥S takes a screenshot of the display with the cursor (ScreenCaptureKit), the assistant panel excluded.
  - The image is downscaled to ≤ 1600 px on the long side.
  - Prompt: problem → approach → code → complexity → test cases.
  - The screenshot is kept only in memory until the answer ends.

### Interface (design: `docs/design/menu-v2.webp`, native macOS, Apple HIG)
- **R-15. Menu-bar menu.** Icon — a parrot (a monochrome template for the menu bar; a color one in the About window).
  Content and order as in the picture:
  1. "● Listening — <app> ›" (dot: green — listening, gray — paused, red — no permission); "Pause listening ⌃⌥P".
  2. "Mode: … ›", "Models: Gemini → DeepSeek → Claude ›", "Language: Auto (UK/RU/EN) ›".
  3. "Profile: <name from profile.yaml> ›" (in v1 — the current one and "Open profile folder"), "Question bank (N cards)…",
     "Edit resume & stories…" (opens the profile folder), "Practice mode…" — **disabled, marked "soon"**.
  4. "Answer now ⌃⌥↩", "Screenshot → <strong model> ⌃⌥S", "Show panel ⌃⌥H", "Session history…".
  5. A gray status line: "Today: $0.03 · Gemini: 41 req" (after a 429 — "Gemini: limit").
  6. "Settings… ⌘,", "Quit ⌘Q".

  **Deviations from the picture (decisions A-3, A-4):** ⌃⌥ shortcuts instead of ⌘; a request counter instead of "quota 92%";
  "Practice mode" disabled; the label "Language: Auto (RU/EN)" → "(UK/RU/EN)".
- **R-16. Panel** (`NSPanel`, non-activating, floating, on all desktops). There is no picture of the panel — this section is the source.
  - Appearance: `.hudWindow` material / dark glass, 16 pt corner radius; width 380 pt (adjustable 300–520);
    opacity 70–100%; font size S/M/L; position and size are remembered.
  - Focus: does not take focus from Chrome, Zoom or Telegram.
  - Structure from top to bottom:
    1. Header: icon, a status pill ("● Listening — Chrome" / "Paused" / "Thinking…"), a model badge or "Bank",
       the latency of the last answer ("1.2s").
    2. "Interviewer": the last 3 utterances, the current one with a cursor.
    3. Answer card: source ("Bank · about-me · 92%" or "Gemini · generated"); text in Markdown;
       S/T/A/R chips for cards tagged STAR; buttons "Copy", "↑ Claude".
    4. Footer: hints ⌃⌥↩ / ⌃⌥S / ⌃⌥H.
  - Panel states:

    | State | What is visible |
    |---|---|
    | idle | "Choose a source" |
    | listening | Transcript |
    | paused | Status "Paused" |
    | thinking | Generation indicator |
    | answer | Answer card |
    | no-match | "Not in the bank" + top 3 |
    | error | Reason + action: "Open settings" / "Retry" |
    | no-permission | Button "Open System Settings" |
    | downloading | Model download progress |

  - Accessibility: VoiceOver labels on buttons, text contrast ≥ 4.5:1, "Reduce Motion" disables animations.
- **R-17. Hotkeys** (global, remappable):
  - ⌃⌥↩ — answer now;
  - ⌃⌥S — screenshot;
  - ⌃⌥H — show/hide the panel;
  - ⌃⌥P — pause;
  - ⌃⌥C — strong model.

  If a shortcut is taken (registration failed) — a warning in settings.
- **R-18. Settings** (a window with tabs):
  - Keys — Gemini, DeepSeek, Anthropic: an input field, buttons "Check" and "Delete"; the value is not shown after saving;
  - Models — model IDs, chain order, first-token timeout;
  - Audio — source, language, pause threshold T;
  - Bank — match threshold;
  - Privacy — the R-12 filter, history retention (30 days by default);
  - Panel — opacity, font;
  - Hotkeys;
  - Budget — a monthly limit for paid providers ($5 by default). When the limit is reached, paid providers are switched off
    until the owner confirms; Gemini Free keeps working.

### Data and accounting
- **R-19. History.** Each session — a JSON file `…/InterviewCopilot/sessions/<date-time>.json`.
  - Content: utterances, turns, answer, source (bank/provider), model, latencies, tokens.
  - "Session history…" window: list, view, delete one or all sessions.
  - Automatic deletion of sessions older than the R-18 retention.
- **R-20. Spending.**
  - Tokens from provider responses × prices from `pricing.json`. Prices as of 2026-10-06: Gemini 3.8 Flash $0.75/$3.75,
    DeepSeek Flash $0.30/$1.20 at peak hours (half off-peak), Claude Sonnet 5.5 $2/$10, Haiku 4.5 $1/$5 per 1M tokens.
  - While the Gemini key is free, its cost is $0 (the "Free tier" checkbox in Keys).
  - Counters: day and month.
- **R-21. Profile.** Folder `…/InterviewCopilot/profile/`: `profile.yaml` (name, default language), `resume.md`, `job.md`,
  `stories.md`, `questions.yaml`. Copied from `profile.example/` on first launch.
- **R-22. Models.** `scripts/fetch-models.sh` and the first-run wizard download models into `…/InterviewCopilot/models/`
  with SHA256 verification (checksums are committed to the repository). On mismatch the file is deleted and an error is shown.

### Security and operations
- **R-23. Keys** — Keychain only. Not logged, not shown after saving, sent only in headers over HTTPS.
- **R-24. Logs** — `os_log` (subsystem `com.itmax04.interviewcopilot`).
  - Utterance and answer text is not logged.
  - Latency metrics are logged (turn ID, timestamps): needed for AC-01…AC-03.
- **R-25. Resources.** The whole app with models during a 10-minute call takes ≤ 1.5 GB of memory
  (`footprint` / Activity Monitor).

### Mini threat model
| Asset | Threat | Measure |
|---|---|---|
| API keys | Leak into Git, logs or chat | Keychain (R-23), `.gitignore`, `scripts/secret-scan.sh` (AC-06), a rule in CLAUDE.md |
| Résumé, transcripts | Disclosure to third parties | Accepted by the owner (Q6) for Gemini and DeepSeek; filter R-12; retention R-19 |
| Models | File substitution during download | SHA256 (R-22), downloads only over HTTPS from official repositories |
| Model behavior | The other person says "ignore the instructions" | Model without tools; the answer is only displayed; profile and utterances are marked as data (R-11) |
| Budget | Uncontrolled spending | Limit R-18; Gemini Free by default |

## 4. Acceptance criteria
| AC | Criterion | How to check |
|---|---|---|
| AC-01 | The other person's utterance text is visible ≤ 1 s after the phrase ends (median over 15 questions) | Test Meet call phone ↔ Mac per `evals/live-script.md`, metrics from logs (`scripts/metrics.py`) |
| AC-02 | A bank card is visible ≤ 0.5 s after the turn completes (median) | Same, metric `turn_end → card_shown` |
| AC-03 | First words of a generated answer ≤ 2.5 s (median, Gemini Free) | Same, metric `turn_end → first_token` |
| AC-04 | ≥ 85% of paraphrases find the right card (≥ 30 examples, ≥ 8 per language uk/ru/en); false matches on out-of-bank questions ≤ 10% | `scripts/run-evals.sh bank` |
| AC-05 | Memory ≤ 1.5 GB over a 10-minute call | `footprint -p <pid>` every minute, maximum in report.md |
| AC-06 | No keys or personal data in the repository | `scripts/secret-scan.sh` (Gemini, DeepSeek, Anthropic key patterns, emails/phones outside `profile.example`) + `.gitignore` check |
| AC-07 | Chain: 429 or an invalid Gemini key → an answer from the next provider with a label; without fallback keys — a clear error | Unit tests with a mock provider + a manual check with a deliberately invalid key |
| AC-08 | The three modes behave per S-01…S-03 | Router unit tests |
| AC-09 | Hotkeys work while Chrome is active; the panel does not take focus | Manual check by the executor + note in report.md |
| AC-10 | uk/ru/en transcription: on a test call ≥ 4 of 5 phrases per language are understandable; the language is detected correctly | `evals/live-script.md`, owner assessment at H-4 |
| AC-11 | The menu matches `menu-v2.webp` with the deviations from R-15 | A menu screenshot next to the picture in report.md, owner assessment |
| AC-12 | History is saved, deleted and purged by retention | Storage unit tests |
| AC-13 | Without the screen-recording permission — the `no-permission` state with instructions, no crash | Owner check at H-3 (before granting the permission) |
| AC-14 | The build is reproducible: `swift build`, `swift test`, `scripts/build-app.sh` pass on a clean clone | Commands with output in report.md |

## 5. Decisions and assumptions
- Facts: the environment (M1 8 GB, macOS 15.7.2, Swift 6.0 CLT, no Xcode, no Zoom, Chrome and Telegram present) was checked on 2026-10-06.
  Prices — from the official Gemini, DeepSeek and Anthropic pages as of 2026-10-06.
- Owner decisions: Q1–Q12 (intent.md).
- Assumptions: A-1…A-4 (intent.md). The executor's decisions during the work are recorded in handoff.md.
