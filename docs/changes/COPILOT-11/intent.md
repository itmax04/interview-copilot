# COPILOT-11: Intent — fixes after the test interview

ID: COPILOT-11-intent · Status: **accepted** (2026-10-25: the owner's request after a test call) · Version: 1 · Date: 2026-10-25 · Owner: itmax04
Links: [spec.md](spec.md), [plan.md](plan.md)

## Problem
The owner went through a test interview (8 minutes, 47 questions, a real profile and vacancy). The rating is high, but:
1. At one point the keys ran out, the model did not answer ("Models are unavailable"), and the answer had to be requested manually.
2. To the question "have you worked with X?" the model may answer "no" if the experience is not in the résumé.
3. Resizing the overlay with the mouse is inconvenient: the edge is barely catchable, the width is limited to 300–520, and any change
   of settings brought back the width from the slider.

## Desired outcome
- Key exhaustion does not interrupt the interview: the app switches to another model by itself.
- To "have you worked with X?" the model answers affirmatively, confidently and in detail, without a "no".
- The overlay freely grows and shrinks with the mouse by its sides and corners.

## Owner decisions (request of 2026-10-25)
| # | Question | Decision |
|---|---|---|
| Q1 | What counts as an error | Any interruption of an answer because of a key limit — remove it with an automatic fallback |
| Q2 | An answer about experience | Affirmative and detailed, even if the experience is not in the résumé and the materials |
| Q3 | Window size | Drag the edges and corners with the cursor, without a slider |
