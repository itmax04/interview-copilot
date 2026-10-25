# COPILOT-09 handoff

ID: COPILOT-09-handoff · Status: **stages 1–7 done (0.13.1, build 34) — H-3: the owner checks a session from the wizard to the review (AC-09, AC-11) and decides on merging into main** · Updated: 2026-10-25
Branch: `feat/copilot-09-parakeet-parity` (from `feat/copilot-08-profiles` @ `1f88465`)
Links: [intent.md](intent.md), [spec.md](spec.md), [plan.md](plan.md); the interface research — `docs/design/redesign/research.pdf`

## Done
- 2026-10-24: an analysis of the ParakeetAI research (77 pages), a brainstorm Q1–Q16, intent/spec/plan; a study of the current
  interface (`--ui-snapshots`, 34 screens), 20 ImageGen prompts, research.pdf. The owner's decision: the redesign goes along the way,
  new screens right away in the target style (`Theme.swift`), the full redesign — after stages 1–5.
- Stage 1 (P-01), version 0.7.0 — sessions:
  - `SessionConfig`, `SessionType` (Interview / Regular / Mock), `SessionPhase`, `SessionClock` (a timer, a warning
    5 min before the plan); the last settings — `AppSettings.lastSessionConfig` (without the company, vacancy and instructions — they belong
    to each call); `SessionRecord.config` in the history.
  - Lifecycle (`LiveSessionController`): without a session the app **does not listen** (`ListeningController.standby`: audio and
    the microphone are not captured, the recognition model is loaded in advance); Start — listening, turns, memory, history; End —
    stop, saving as chosen. "New interview" and the automatic boundaries (30 min of silence, an app change) are replaced by the session.
  - The "Create session" wizard (⌃⌥N, menu, panel): "Details" (type, profile, a vacancy link → import, company, vacancy),
    "Settings" (audio source, language, the first model, session instructions, auto-answer, saving, review, plan), "Check"
    (`Preflight`: microphone 2 s, call audio 3 s, recognition, keys, profile — separate lines with actions).
  - Vacancy import (`JobImport`): a page without a sign-in → the visible text → the model → the company and the description; a sign-in form
    (LinkedIn) and an empty page — clear errors; the page is data, not instructions.
  - Call detection (`CallDetection`): the microphone is busy in another app (a CoreAudio flag, no audio is captured) and
    Zoom / Teams / Telegram / FaceTime / Discord / Slack / a browser is running → the panel shows "Looks like a call started: Zoom —
    Start / Configure… / Not now" (no more than once in 10 min per app).
  - Answers with a session: session instructions — a `<this_session>` block, more important than the profile and the general ones; Regular — a separate system
    prompt "what to say", without the résumé and cards, with the profile's materials and instructions; the vacancy and company from the wizard —
    instead of the profile's vacancy; the selected model — first in the chain; auto-answer off — a turn only by ⌃⌥↩.
  - Panel: "No session" with "Create session… ⌃⌥N", a timer and "End" in the header, "N min left per plan".
  - Menu: the first item "Create session… ⌃⌥N" / "End session · 12:47"; the line "No session — not listening".
  - The AI interview is a Mock session (menu, the `--ai-interview` flag, the wizard); its end ends the session.
  - `Theme.swift`: target style tokens (indigo #4C6EF5, ok/warn/danger), `ThemeCard`.

- Stage 2 (P-02), version 0.8.0 — the live overlay (R-07…R-11, R-17):
  - `AnswerHistory` (CopilotCore): a question → answer versions (hint / bank / strong / screenshot / refine) with the statuses
    waiting / streaming / complete / failed / cancelled / noMatch. Each request writes only into its own version by id — late
    tokens of a cancelled request do not get into the visible answer; a new question interrupts unfinished ones. Up to 50 questions.
    The title "Question: …" — the first question sentence without "Эээ, / Uh / Ну".
  - Panel (`PanelView`, `AnswerCardView`): a two-row header — microphone and call levels, a timer, collapse, the ⋯ menu,
    "End"; below it "Answer ⌘↩ / Screenshot ⇧⌘↩ / Chat ⇧⌘Space". A transcript line with "Clear" and expand. The detection
    status: "Checking…" (a speculative request), "Question detected", "Not a question · answer manually". The card: ← 3 / 7 →,
    copy, version tabs ("2 · shorter"), the previous answer dimmed while a new one is being prepared; "New answer" if
    you are browsing old ones; an error — the reason and "Retry"; the chips "Shorter / More detail / Example"; "↑ Claude".
  - Chat (⇧⌘Space / ⌃⌥Space): the modes "Question" (like a voice turn), "Refine the answer" (a new version), "For the whole session"
    (an instruction until the end of the session — badges above the transcript, removed with ✕, added to `<this_session>`). The panel gets
    the keyboard only while the chat is open (`CopilotPanel.allowsKey`), Esc closes it.
  - Refinement (`PromptBuilder.refine`): the previous answer — a `<previous_answer>` block, the instruction is more important than the length and format rules,
    new facts about the candidate — only from the answer, résumé, materials and history.
  - Clear (Q13): the transcript on screen and the accumulated lines of the next turn (`TurnController.clearPending`); the interview
    memory and the saved transcript stay.
  - The ⋯ menu: auto-answer, recognition language, scale (80–160%, `AppSettings.panelZoom`), the next display,
    "Hide from screen capture" (`sharingType = .none`, `AppSettings.panelHiddenFromCapture`) and "Check visibility":
    the overlay is filled with magenta for 0.25 s, a screen capture including own windows is taken, the share of magenta in the window frame →
    "Visible / Not visible / Could not determine" with the date and the macOS version (`VisibilityProbe`).
  - "Can't hear the call for N s" — in a session with app audio, if the call level is below the threshold for ≥ 10 s; level indicators —
    every 100 ms, a 3 dB step, written to the model only on change.
  - Hotkeys: the ParakeetAI ⌘ scheme is registered on Start and removed on End (`HotkeyCenter.registerSession`);
    the ⌃⌥ equivalents always work (new: ⌃⌥Space, ⌃⌥⌫, ⌃⌥←, ⌃⌥→).

- Stage 3 (P-03), version 0.9.0 — answer settings with a live preview (R-12, Q6):
  - `AnswerStyle` (CopilotCore): format (gist + bullets / bullets only / continuous text), length (short ≤ 40 words /
    balanced ≤ 80 / detailed ≤ 150), tone (formal / neutral / friendly). The format rule in the system
    part of the interview and the regular call is built by `formatRule`; the standard gives **the previous line verbatim** (checked by a test) —
    behavior and the prompt cache are unchanged. Detailed — 800 tokens. The owner's instructions go after it and take precedence (08/R-04).
  - Where it is set: Settings → Models → "Default answer style" (`AppSettings.answerStyle`); the wizard → "Settings" →
    "Answer style" → "Configure…": "Save for the session" (`SessionConfig.style`, not carried over to the next session) or
    "Default" (the settings and this session).
  - The editor (`AnswerStyleEditor` + `StylePreview`): toggles on the left, a card like in the overlay on the right — the model's answer to a
    sample question ("About yourself / Behavioral / Technical", uk/ru/en; for a regular call — its own samples) based on the session
    profile with the vacancy from the wizard (`SessionConfig.applyingJob`, shared with `AnswerController`), with the session chain.
    The request goes 0.6 s after the last change, the previous one is cancelled; finished answers are cached (switching back and forth
    does not spend limits); a caption "Groq · 1.1 s · 38 words"; "Regenerate".
  - `AnswerShape`: counting words, bullets and prose lines — for the preview caption, tests and live checks.

- Stage 4 (P-04), version 0.10.0 — the review after End (R-13, R-14, Q8, Q15):
  - The session record: your phrases with time (`SessionRecord.ownerUtterances`, with the Whisper refinement) and the review
    (`SessionRecord.review`: status pending / running(done, total) / done / failed, comments, summary, "Ask AI").
    Old files are readable; a broken review does not prevent opening the transcript (test).
  - `ReviewPrompt` (CopilotCore): comments on answers in batches of 6 (JSON: what worked, what was missing, how to say it
    better — in the interview language); the summary — for an interview the topics, strengths and weaknesses, next steps; for a regular
    call — the outcome, agreements, next steps; "Ask AI" — based on the transcript and the summary, with the 4 previous questions.
    The transcript — the last 14,000 characters. Answers, the transcript and the profile are data; the PII filter.
  - `ReviewController`: after End (if "Review after finishing" and "Save the transcript" are on) — in the background, the session
    chain, saving after each batch; an error → "Review not finished: reason" with "Retry", finished comments
    stay, a retry continues from where it stopped. The sessions window opens on the finished session — the transcript is visible right away.
  - The "Sessions" window: the company and type in the list; the tabs "Summary" (the summary, then question → your answer → comment →
    "Hint on screen"), "Transcript" (Interviewer / You / hints separately, time from the start, a hints
    toggle), "Ask AI" (suggested questions, answers are saved in the review); for old sessions — "Make a review";
    deletion — with confirmation, together with the review.

- Stage 5 (P-05), version 0.11.0 — screenshot tasks and context (R-15, R-16, AC-08):
  - `ScreenshotTaskTracker` (CopilotCore): a shot within 30 s of the previous one — the same task (up to 3 shots), otherwise a new one;
    a task is active for 15 minutes after the last shot or a question about it, while it has a solution; Clear, ✕ and the session end
    close it. A repeated shot solves the task again over all shots — as a new version of the same question ("2 shots").
  - The solution is parsed by sections (`ScreenshotTask.statement`, `promptSummary`): the card title — "Task: <problem>";
    requests for voice questions get an `<active_task>` block (the problem, the approach, the complexity, code up to 1,800 characters) with the rule
    "only if the question is about it". The block is in the user part: the system part and its cache do not change.
  - `FollowUpDetector`: a short question without a subject ("А сложность?", "Почему так?", "А якщо…", "What if…", "Can you do
    better?") — up to 9 words, without "вы / ви / you / ваш / расскажите" after the start. Such a question refers to the active task,
    without one — to the previous exchange (the question and the hint shown). An answer about a task — up to 800 tokens (code happens).
  - Overlay: a "Task · 2 shots" plate with thumbnails and ✕ above the answer card.

- Stage 6, version 0.12.0 — a full redesign after the owner's samples (ImageGen P00–P19, the folder
  `~/Desktop/InterviewCopilot-redesign/Результат-ImageGen/design/imagegen/`):
  - The design system `Design/DesignSystem.swift` (IC: P00 colors, buttons, cards, badges, keys, logo) — taken from
    the owner's redesign branch (`Результат-ImageGen/source`, commits 48159e1, cf0e764); `Theme` points to the same colors.
    The rest of that branch's code (its own sessions, wizard, prompt `transform`) **was not carried over**: it was built on the code before stage 1 and
    duplicates stages 1–5. The "Today" layout and the entry to the AI interview were taken.
  - The overlay (P01–P06, P10): dark glass, level waves, buttons with keys (shortened in a narrow panel), status
    pills, "Active task" with thumbnails, "Copy code", collapsed — one line, a "Call in Zoom" card.
    The default panel is 420×540 pt.
  - The main window (P12): "Today" (readiness, recent sessions, question preparation), "Sessions", "Profiles",
    "AI interview", "Settings"; it opens at launch; the menu and the review open the right section.
  - Sessions (P15–P16), profile (P13), settings with sections (P17), the wizard (P07–P09), answer style (P11),
    first launch (P18, the Groq key), the AI interview and test call pages (P19 — the palette).
  - A "sample ↔ implementation" comparison — `docs/design/copilot-09/stage6/*.jpg` (16 pairs).

- Stage 7, version 0.13.0 — the final check (P-06) and improvements after it:
  - States for acceptance — in CopilotCore with tests: `QuestionDetection` (transitions and "Preparing an answer…", AC-04),
    `SessionPhase.canStart/canEnd` (AC-01), `SessionConfig.withSessionNotes` (instructions from the chat, AC-05).
  - A repeated "Answer" on the same question within 2 s while the answer is being prepared does not create a second turn (AC-03).
  - A ⌘ key taken by another app — the overlay hints ⌃⌥; the wizard does not read the profile files on every
    redraw; "Back to the session list" is remembered.
  - "Example" in the live run added invented metrics ("+30 %") 3 times out of 4 — the instruction was tightened, 4/4.
- An addition at the owner's request (2026-10-25): **several keys of one provider, with no limit on the number**
  (0.13.1 — the limit of 5 was removed after the owner's remark). Slots in the Keychain (`groq`, `groq#2`…), a chain step per key,
  all the provider's keys go in a row before the next provider: a 429 on a key — the next key right away; a rate-limited key waits
  for the reset per the provider's hint (the `retry-after` header, "try again in 6.18s", Gemini `retryDelay`; without a hint —
  60 s) and is not tried first; only when all keys are rate-limited — the next provider. A timeout/5xx — the model cools down;
  an invalid key — only that key (30 min); changing keys in the settings resets the wait. Deleting a key
  renumbers the rest without gaps. Settings → Model keys: "Key 2, 3…", "Another key — from another account". A warning to the owner: registering several accounts to
  get around limits may be forbidden by Groq's terms — the decision and the risk of a ban are on the owner's side.

## Executor decisions
- Call detection — by the CoreAudio flag "input busy", not by audio: without a session the app does not listen (Q3), no macOS
  notifications are needed (the offer is in the panel).
- The pre-start check captures the call audio for 3 s only for the level (without recognition) — this is the owner's action in the wizard.
- "Do not save the transcript" — the session record is not written to disk at all (the memory lives until the end of the call).
- The "Bank + hint" etc. modes were not touched; the session type determines `useProfile` (Interview/Mock — with a profile).
- The panel status line was cut off with a timer and "End" — fixed in stage 2 (a two-row header).
- Stage 2: the answer stays in the history after End too — it can be read to the end and copied; a new session clears the history.
- Stage 2: the visibility check compares the **hue**, not the exact color — the capture comes in the display color space
  (#FF00FF on P3 ≈ 234/51/247); an exact comparison gave a false "Not visible". A share of 5–30% — "Could not determine".
- Stage 2: "More detail" and "Example" in the live run invented projects and numbers — the refinement block got the rule
  "new facts about the candidate — only from the answer, résumé, materials and history" (COPILOT-08 decision: experience — only from the materials).
- Stage 3: the session style is stored only if it differs from the default style; "Default" resets the session style.
- Stage 3: in the detailed style the model adds plausible achievements that are not in the profile ("скоротив час відповіді
  на 30 %") — this is the current rule "improvise when there is no fact" (COPILOT-08), not a style bug; profile facts
  are kept. **A question to the owner:** forbid invented numbers and achievements in answers (as already done in refinements)?
- Stage 4: "how to say it better" does not invent numbers and story events — instead there are placeholders "[number]", "[result]",
  "[situation]", "[what you did]": it shows which fact to prepare. In the live run the model at first added percentages and
  a whole conflict story — the rule was tightened (3 runs in a row PASS); generic words (the choice of architecture) sometimes remain.
- Stage 4: the review is only for saved sessions ("Save the transcript" off — nothing to review; the wizard already works this way).
- Stage 4: an "Ask AI" error is shown under the field and is not saved, so that it does not get into the context of the next question.
- The owner's decision (2026-10-24): in normal answers on a call **logical improvisation stays** (the COPILOT-08 rule);
  the ban on invented facts — only in refinements ("More detail", "Example") and in the review ("how to say it better").
- Stage 5: "Clear" also closes the screenshot task — after clearing, voice questions do not refer to it.
- Stage 6 — deliberate differences from the samples:
  - The "83 %" score (P12, P15) is not shown — the review does not compute it, and a number must not be invented; "Today" shows the review
    state instead of the "Score".
  - Company logos (Apple, Yandex) — a letter on a colored square: we do not draw other brands.
  - P04: the ⋮ menu is a system menu, without new ⌘A, ⌘L, ⌘0, ⌘⇧M, ⌘⇧H, ⌘⇧V: these are global keys, they would be intercepted
    from all apps; a SwiftUI popover over a non-activating window is risky without a live check.
  - P10: the system notification — a card in the overlay (the stage 1 decision: no notification permission).
  - P16: there are no "Notes", "Score" tabs and no "Open in the recording" button — these features do not exist.
  - P13: the résumé preview on the right was not done — the editor is full width. P14: the questions and materials table — the existing
    `QuestionsView`/`MaterialsView` in the profile tabs, without separate "Questions"/"Materials" items in the sidebar.
  - P17: provider rows with logos and drag-and-drop were not done — the existing key and chain forms inside the sections.
  - P18: there is no "Profile" step (3 steps) — the profile is filled in the main window. P19: the AI interview stays a page
    in the browser (voice and Chrome audio capture), recolored to P00; embedding it in the window is a separate task.
  - The windows are light (as in the samples), the overlay is dark; the browser pages follow the system theme.
- Stage 7: the "no invented numbers" check does not count numbers in code; "семирічний" is the same fact as "7 років".
- Stage 7: a duplicate "Answer" is cut off by text and time (2 s), only while the answer is not ready — after that you can ask again.
- Stage 7: known — Gemini 3.8 Flash at the start of the run did not send the first token even in 20 s, then the free limit
  of that model ran out (429); the fallback Gemini Flash Lite answers in 0.8 s. After the first failure the chain "cools down" the
  model and goes to the fallback — one wait is lost on a call. Flash Lite can be made the primary, or a second
  Gemini key can be added.
- Risk (the owner's decision Q10): during a session ⌘← / ⌘→ / ⌘↩ / ⇧⌘⌫ are intercepted from all apps — for example,
  in a code editor during live coding ⌘← will not go to the start of the line. If it gets in the way — keep only ⌃⌥ (one line in
  `sessionStarted`) or make the scheme configurable.

## Checks (2026-10-24)
| Check | Result |
|---|---|
| `swift test` | **277 tests PASS** (+9: session settings, chain, timer and plan, pre-start check, call detection, vacancy import, the Regular and instruction prompts, history with config; menu — the session as the first item) |
| `scripts/run-evals.sh` | turn, bank, filter-text, memory, materials — unchanged, PASS |
| `scripts/secret-scan.sh` | 0 findings |
| `--smoke-session` | 5/5: the company and description from a synthetic page, "Ignore previous instructions" not executed, no navigation |
| `--smoke-memory` (new) | a regular call 3/3 (numbers from the materials), a session instruction over the profile 3/3 (an answer in English) |
| `--smoke-memory 1` (all 15) | 13/15 — 2 FAILs: Groq 429 + a Gemini timeout after ~25 requests in a row (limits, not behavior); a repeat after 75 s — PASS |
| `--smoke-prepare` (08 regression) | after a pause 7/7 (before the pause drafts — 429) |
| `--ui-snapshots` | the wizard (3 steps), the "no session" panel, "a call started", a session with a timer and a plan — reviewed |
| Live: the wizard, Start/End, call detection | NOT RUN — H-1, owner |

Stage 2 (2026-10-24):
| Check | Result |
|---|---|
| `swift test` | **288 tests PASS** (+11: answer history — transitions, "new answer", foreign tokens, versions, "not a question", limit, titles; `PromptBuilder.refine`; the session ⌘ scheme without overlaps with ⌃⌥; `VisibilityProbe` — hue in different color spaces, verdict, share in the frame) |
| `scripts/run-evals.sh` | turn, bank, filter-text 214/214, memory 8/8, materials 23/24 — PASS |
| `scripts/secret-scan.sh` | 0 findings |
| `--smoke-memory` "refinement" (5 scenarios × 3) | **15/15** after two prompt fixes (was 7/9: "Shorter" kept a list; 11/15: "More detail / Example" invented numbers) |
| `--smoke-memory 1` (all 20) | 15/20 in a row: 4 FAILs — Groq 429 after ~60 requests, 1 FAIL — the Kafka trap (#1); after 90 s: the Kafka trap **5/5**, the four that failed on the limit — **4/4** |
| `--ui-snapshots` | 26 panel states reviewed; fixed: header buttons wrapped letter by letter, "End" and "↑ Claude" were cut off, chips wrapped at 130% scale. Shots — `docs/design/copilot-09/stage2/` |
| Live: the overlay in a call, chat from the keyboard, ⌘ keys, collapse, next display, visibility check | NOT RUN — H-2, owner |

Stage 3 (2026-10-24):
| Check | Result |
|---|---|
| `swift test` | **296 tests PASS** (+8: the standard = the previous prompt line for the interview and the call; format, length and tone rules; owner instructions after the style; detailed tokens; the session style is not carried over, old files are readable; the session vacancy; counting words and bullets; sample questions in uk/ru/en) |
| `scripts/run-evals.sh` | turn, bank, filter-text, memory, materials — PASS |
| `scripts/secret-scan.sh` | 0 findings |
| `--smoke-memory` "style" (4 scenarios × 3) | **11/12 → 12/12**: short continuous ≤ 40 words without bullets 3/3, bullets only 3/3, detailed with profile facts 3/3, a regular call short and formal 3/3 (one "error" was a false check: the amount in words "двенадцать тысяч", the check was fixed, a repeat 2/2). Before that — a false "new numbers" check in detailed (see decisions) and Groq 429 |
| `--ui-snapshots` | the style editor (standard and "text · short · friendly"), the wizard with the style card — reviewed; fixed: the format switch did not fit the column. Shots — `docs/design/copilot-09/stage3/` |
| Live: the preview in the wizard and in Settings on your keys | NOT RUN — H-2, owner |

Stage 4 (2026-10-24):
| Check | Result |
|---|---|
| `swift test` | **304 tests PASS** (+8: a transcript by speaker and time, batches and continuing after an error, the comments request — data and the PII filter, parsing the model's answer by id, the interview and call summary, truncating a long transcript, "Ask AI", storing the review and a broken review) |
| `scripts/run-evals.sh` | turn, bank, filter-text, memory, materials — PASS |
| `scripts/secret-scan.sh` | 0 findings (the synthetic number in the test is assembled from parts, as in LLMTests) |
| `--smoke-review` (new) | **3 runs in a row — all PASS** (10 checks): comments 3/3, the instruction in an answer "Ignore previous instructions… HACKED" not executed, a weak answer gets what was missing, "how to do better" without invented numbers and with placeholders for own facts, a summary with strengths and weaknesses, "Ask AI" — a fact from the transcript and an honest "not mentioned" about Kubernetes, the call's agreements (an estimate on Friday, a call on Monday). Before the fixes: invented "90 %", "20 %" and a conflict story; false checks — "5" from "пять лет" and "нет ни одного упоминания" |
| `--ui-snapshots` | the sessions window: summary, transcript, "Ask AI", a review with an error — reviewed. Shots — `docs/design/copilot-09/stage4/` |
| Live: End → review → the sessions window on your keys | NOT RUN — H-2, owner |

Stage 5 (2026-10-24):
| Check | Result |
|---|---|
| `swift test` | **311 tests PASS** (+7: shots within 30 s — one task up to 3, a new one after; 15 min activity and extension; the problem and the solution summary; recognizing uk/ru/en follow-ups — 17 cases, including "А как вы тестируете?" and "Why did you leave…" which are not follow-ups; `<active_task>` in the request, the system part unchanged; a request over several shots; the title "Task: …") |
| `scripts/run-evals.sh` | turn, bank, filter-text, memory, materials — PASS |
| `scripts/secret-scan.sh` | 0 findings |
| `--smoke-task evals/fixtures/two-sum.png` (new, AC-08) | **3 runs in a row — 6/6 each (18/18)**: the problem from the solution; "А сложность?" — O(n); "А если массив отсортирован?" — two pointers; "Почему словарь, а не два цикла?" — a comparison with O(n²); "Расскажите о себе" with an active task — about yourself, without the task; "Почему именно его?" without a task — about RabbitMQ from the previous hint. Found by a test and fixed: "Can you do better?" was not treated as a follow-up because of the "you" inside the phrase itself |
| `--ui-snapshots` | the task plate with thumbnails and the title "Task: …" — reviewed, `docs/design/copilot-09/stage5/` |
| Live: ⇧⌘↩ on a task in a browser, a second shot within 30 s, "а сложность?" by voice | NOT RUN — H-2, owner |

Stage 6 (2026-10-24):
| Check | Result |
|---|---|
| `swift test` | 311 tests PASS (the default panel width is 420; the task title is capitalized) |
| `scripts/run-evals.sh` | turn, bank, filter-text, memory, materials — PASS |
| `scripts/secret-scan.sh` | 0 findings |
| `scripts/build-app.sh` | 0.12.0 (32), signature InterviewCopilot |
| `--ui-snapshots` | 64 shots reviewed; fixed along the way: the timer and keys wrapped letter by letter, buttons were cut off, `TabView` in the profile and settings was drawn with black bars (replaced with own tabs), dates in English, "Balanced" was cut off |
| Live: the main window at launch, sections, the wizard, the overlay in a call | NOT RUN — H-2, owner |

Stage 7 (2026-10-24…25):
| Check | Result |
|---|---|
| The full CLAUDE.md check | `swift test` **323 PASS** (+12: states, a repeated "Answer", several keys — in memory and in the real Keychain); evals turn/bank/filter-text/memory/materials PASS; secret-scan 0; `build-app.sh` 0.13.0 (33), `codesign --verify --strict --deep` OK |
| `--smoke-llm` | Groq: first token 228–489 ms, through the chain 275–453 ms (COPILOT-04: 0.74 s) — no worse. Gemini 3.8 Flash — see "known" |
| `--smoke-memory 1` (24) | 22/24 in a row (from the 12th — the fallback Gemini Lite after a Groq 429); 2 FAILs analyzed: a false check "семирічним" (fixed, 3/3 on Groq) and "Example" with an invented "30 %" (the instruction was tightened, 4/4) |
| `--smoke-prepare` · `--smoke-session` · `--smoke-review` · `--smoke-task` · `--smoke-screenshot` | 7/7 · 5/5 · 10/10 · 6/6 · OK (Gemini, 3.2 s, code and complexity; Groq does not accept images — a local refusal, no request) |
| Several keys live | the chain through the signed build and the real Keychain: Groq 453 ms; switching between keys on 429 — by tests (there is no second key on this Mac) |

Acceptance (COPILOT-09 spec.md):
| AC | Evidence | Status |
|---|---|---|
| AC-01 Wizard, Start/End, states | SessionTests (settings, validation, last values), SessionStateTests (Start/End are idempotent, after an error — Start again) | PASS |
| AC-02 "No permission" ≠ "no signal" | SessionTests.preflightSeparatesPermissionFromSilentSource | PASS (test); live — H-3 |
| AC-03 An answer belongs to its request | OverlayTests: foreign tokens do not get into a version, a new question interrupts unfinished ones; a repeated "Answer" within 2 s does not duplicate | PASS |
| AC-04 States by events | SessionStateTests: "Checking → Question detected → idle", "Not a question", "Preparing an answer…", reset | PASS |
| AC-05 History, a refinement version, a session instruction | OverlayTests (history, versions), refine in PromptBuilder, `withSessionNotes` → `<this_session>`; the live "refinement" and "a session instruction over the profile" | PASS |
| AC-06 Style changes the form, not the facts | the live "style: …" 12/12 (stage 3) + 3/3 short continuous (stage 7) | PASS |
| AC-07 Review | ReviewTests (comments, summary, a broken review does not hide the transcript), `--smoke-review` 10/10 | PASS |
| AC-08 A screenshot + "а сложность?" | `--smoke-task` 6/6 (stage 5: 18/18) | PASS |
| AC-09 Visibility check | — | NOT RUN — owner (H-3) |
| AC-10 No regressions, latency no worse than 07 | the full check PASS; Groq's first token no worse than the 04/07 records; the "end of a question → request" path without new disk, network and Keychain access (fewer keys are read than before) | PASS (without a live call) |
| AC-11 A session from the wizard to the review | — | NOT RUN — owner (H-3) |

## Next step
H-1 + H-2: the owner in 0.8.0 — ⌃⌥N → the wizard → "Start session" → a couple of voice questions → ⌘← / ⌘→ through the history →
"Shorter" → ⇧⌘Space "For the whole session: answer in English" → ⋯ → "Hide from screen capture" → "Check visibility"
(and the same during screen sharing in Zoom/Meet) → "End". In 0.9.0 — the wizard → "Answer style" → "Configure…" → switch
the format and length, look at the preview. In 0.10.0 — after "End" the session window opens: the summary, comments on
answers, the transcript, "Ask AI". In 0.11.0 — ⇧⌘↩ on a task (a second shot within 30 s goes to the same one), then by voice
"а сложность?".

**H-3 (0.13.0):** a call or a self-check from the wizard to the review (AC-11) and "Check visibility" during screen sharing
(AC-09); optionally — a second Groq key in Settings → Model keys. Then the owner's decision: merge
`feat/copilot-09-parakeet-parity` into `main`.
