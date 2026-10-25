# COPILOT-07: Intent — audit and finishing a working version

ID: COPILOT-07-intent · Status: **accepted** (2026-10-24, the owner's request) · Version: 1 · Date: 2026-10-24 · Owner: itmax04
Links: [spec.md](spec.md), [handoff.md](handoff.md), [COPILOT-06](../COPILOT-06/handoff.md) (the live memory test of 2026-10-24)

## Problem
The live memory test (2026-10-24, v0.3.2, "Mac microphone", 16 questions) showed:
- the model confirmed the trap "Ви згадували, що працювали з Kafka" ("Так, я працював з Kafka"). Kafka was only in the hint
  that the model itself had shown on the previous turn;
- ⌃⌥A was never pressed: there is not a single "owner answering" in the log, the answers were not recorded. The key is not visible anywhere —
  neither in the menu nor in the panel;
- the fragment "Є таке питання." got a placeholder hint and took a place in the history;
- without a profile the model invented the salary "180 000 грн на рік" — unrealistic;
- "Повернемо себе до…" (that is how Whisper wrote "Повернімося") was not treated as a reference to the past.

The owner asks to bring the app to a finished, verified version: fix what was found, find and fix the rest
independently, check everything with the available tests and honestly list what cannot be checked.

## Desired outcome
Hints do not confirm what was not said; answers in the self-check are recorded without hunting for keys; the session history shows
your answers and the time of the interview itself; provider errors do not leave the panel "thinking" forever; history data is only for
the owner. Everything is confirmed by tests, evals and a live run on a real model.

## Executor decisions (the owner allowed deciding independently: "Don't ask unnecessary clarifying questions")
- Scope — the Interview Copilot app (the whole repository). The bots in `telegram-bots/` are not part of the task and were not changed.
- The frontend rules (21st.dev, DESIGN.md) are not applied — the owner's decision of 2026-10-06 (CLAUDE.md, the "Design" section).
- "Mobile devices and tablets" — not applicable: a native macOS app; adaptivity — the panel width and the font size.

## Scope
In: fixes from the live test, a code audit (logic, errors, data, interface, accessibility), tests, evals, a live
prompt check, documents. Out: new features outside the product's purpose, new dependencies, changes to TCC and the Keychain.
