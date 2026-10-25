# COPILOT-04: Intent — instant answers without a bank

ID: COPILOT-04-intent · Status: **accepted** (2026-10-23, "yes, do items 1–4") · Version: 1 · Date: 2026-10-23 · Owner: itmax04
Links: [spec.md](spec.md), [handoff.md](handoff.md), [COPILOT-03 spec](../COPILOT-03/spec.md) (R-36…R-40), [ADR-0001](../../decisions/ADR-0001-stack.md)

## Problem
The owner's main idea: the app instantly recognizes a question and answers without a prepared bank.
Answering without a bank is already possible (COPILOT-03 R-40, "No profile"), but from the end of the question to the first words of a hint
it takes ≈ 1.5–2 s: we wait 0.7 s for the pause T, and only then does the model get the question.

## Desired outcome
The first words of a hint appear no later than ~1 s after the end of the question (median); the model never leaves the owner without an answer.

## Owner decisions (2026-10-23)
| # | Question | Decision |
|---|---|---|
| Q1 | What to do | Items 1–4: a speculative request, a short pause after a question, the gist on the first line, a measurement |
| Q2 | If the model does not know | Improvise and give hints from the context (the owner's message during the work) |

## Scope
In: the speculative request, the pause for "?", the answer order, the improvisation rule, metrics and an offline measurement.
Out: lowering the VAD pause (350 ms), requests on interim text during speech, new providers.

## Constraints
- Extra model requests: the speculative request is cancelled if the other person continues. Groq Free — 1000 requests a day.
- The live measurement uses the owner's keys (Settings → Keys); the executor does not enter keys.

## Assumptions
- A-1. Parakeet puts "?" based on intonation; questions without "?" wait for the normal pause T.
