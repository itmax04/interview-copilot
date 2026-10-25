# COPILOT-09: Intent — a live assistant on the ParakeetAI level

ID: COPILOT-09-intent · Status: **accepted** (H-0 2026-10-24: "start stage 1") · Version: 1 · Date: 2026-10-24 · Owner: itmax04
Links: [spec.md](spec.md), [plan.md](plan.md); source — the owner's research "ParakeetAI Technical Research" (2026-10-24,
77 pages, public data; not stored in the repository)

## Problem
According to the ParakeetAI research, its value is a short loop "hear → keep the context → a question (manual or automatic) →
an answer next to the call" with clear states, plus session preparation and a review after the call. We already have
recognition, automatic and manual answers, screenshots, memory, profiles, materials, questions, the AI interview. Missing:
an overlay with an action bar and an answer history, visible question-detection states, text input, the session as an object
(a wizard, Start/End, a timer, a pre-start check), answer format settings with a preview, a review with AI comments,
a screenshot task as context, visibility control during screen sharing.

## Desired outcome
The behavior and structure of the live assistant are close to ParakeetAI (layout, actions, states, sessions, review), while
our strengths are kept (local recognition, uk/ru/en at once, the voiceprint, the free model chain,
first words in ~1–1.5 s) and the weak spots noted by the research are not copied: an old answer under a new request,
unclear states, "invisibility" without a check.

## Owner decisions (brainstorm 2026-10-24)
| # | Question | Decision |
|---|---|---|
| Q1 | Priorities | Everything: the live overlay, Chat and answer settings, sessions and review, screenshots and a pre-call check. Plus 7 mechanisms: personalization by facts; conversation context (follow-ups, screenshot → voice questions, topic change, clearing); reliable audio and connection/recovery states; manual and automatic answers without repeats and mixing; a gradual answer and clear states, an old answer does not look new; overlay control (moving, size, collapsing, scale, scrolling, keys without stealing focus); privacy (storage, deletion, a visibility check during screen sharing). Mock, the question bank, the résumé, headshots — discuss after the main part |
| Q2 | Appearance | Close to ParakeetAI: a button bar with key hints at the top, a transcript line below it, a semi-transparent answer card below that; our own style, without their logo and graphics |
| Q3 | Session | As in ParakeetAI: "Create a session" → Start → timer → End → review. Without a session the app does not listen |
| Q4 | Automatic answer | An Auto Generate toggle (in the wizard and the overlay menu) + a visible status Checking / Question detected / No question; the manual Answer is always available |
| Q5 | Session types | Interview, Regular call, Mock |
| Q6 | Answer settings | Format, length, tone with a live preview (the model's answer to a sample of the selected question type based on the profile); "Save" — for the session, "Default" — for all |
| Q7 | Chat | A new question as text; refine the current answer (a new version, the old one stays in the history); quick buttons "Shorter / More detail / Example"; an instruction for the whole session (visible in the overlay) |
| Q8 | Review | An AI comment on each of your answers, an overall summary, "Ask AI" about the session, a transcript by speaker with time |
| Q9 | Screenshot | The whole screen under the cursor; a shot within 30 s is added to the same task, later — a new task; voice follow-ups refer to the active task |
| Q10 | Keys | The ParakeetAI scheme (⌘↩ answer, ⌘⇧↩ screenshot, ⌘⇧Space chat, ⌘⇧⌫ clear, ⌘←/→ answers) — only during a session; outside a session they are not intercepted |
| Q11 | Private | Add a toggle and an honest built-in visibility check (a screen capture via ScreenCaptureKit), without promising "invisible" |
| Q12 | Launch | A pre-start check; automatic detection of a call start (the offer "Start a session?"); importing a vacancy from a link; a timer with a plan and a warning |
| Q13 | Clear | Clears the transcript line and the "last lines" for the next answer; the interview memory and the saved transcript stay |
| Q14 | Regular call | "What to say" in the first person on the topic, instructions and materials of the profile, without the résumé and cards; after the call — a summary and agreements |
| Q15 | Review — when | Right after End in the background (can be turned off in the wizard); the transcript is visible right away |
| Q16 | Order | 1) sessions; 2) the live overlay; 3) answer settings; 4) review; 5) screenshot tasks and context |

## Scope
In: everything from the table. Not in this task (the owner's decision — after the main part): a company question bank, a résumé
builder, AI photos, changes to the AI interview other than launching it from the wizard. Not done: accounts, payment, cloud storage.
New dependencies — none (ScreenCaptureKit, AppKit, SwiftUI are system frameworks).
