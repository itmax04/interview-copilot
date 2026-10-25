# COPILOT-06: Intent — interview memory

ID: COPILOT-06-intent · Status: **accepted** (2026-10-23, the owner's answers to 4 questions) · Version: 1 · Date: 2026-10-23 · Owner: itmax04
Links: [spec.md](spec.md), [handoff.md](handoff.md), [COPILOT-05](../COPILOT-05/spec.md) (the owner's speech, R-07)

## Problem
A hint takes into account only the current question, the interviewer's 6 last lines and the owner's 3 last phrases. After 20–30 minutes
the interviewer returns to a topic ("let's get back to your payment module") — the model no longer knows what was said.

## Desired outcome
The model treats the interview as one conversation: it remembers the questions and answers from the start of the session, finds the right fragment when
a topic comes back, does not contradict what was said and does not invent past answers that are not in the history.

## Owner decisions (2026-10-23)
| # | Question | Decision |
|---|---|---|
| Q1 | What to do with the memory after the interview | Save it in the session history (locally, retention R-18 — 30 days); **changes decision Q6 of COPILOT-05** — the owner's speech is now in the history |
| Q2 | Session boundaries | Automatic (launch, a change of the call app, silence > 30 min) + a "New interview" menu item |
| Q3 | A fact summary by the model | No — only search over what was actually said (bge-m3, locally), no extra requests |
| Q4 | History size in a request | Medium: the 4 last exchanges in full + up to 3 found older ones (~+1.5 k tokens) |

## Scope
In: "question → the owner's answer → hint" exchanges, short and long memory, references to the past, session history,
"New interview", the `memory` eval. Out: a summary by the model, the owner's answers in the AI interview (they go their own way, 03/R-32),
showing exchanges in the history window (the data is in the session JSON).
