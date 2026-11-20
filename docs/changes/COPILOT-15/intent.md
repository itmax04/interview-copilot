# COPILOT-15: Intent — accurate turns (whole-question recognition)

ID: COPILOT-15-intent · Status: **accepted** (2026-11-20: the owner chose "A+C+D′" after the architecture comparison) · Version: 1 · Date: 2026-11-20 · Owner: itmax04
Links: [spec.md](spec.md)

## Problem
Words of the interviewer's questions get mixed up in the hints. Evidence from the live call log of 2026-11-20 (15:40–17:05,
numbers only, no transcript text is kept) and a synthetic dense-speech experiment:

1. The energy VAD cuts dense speech into short pieces: 450 final phrases, median audio length 1.12 s, 78% shorter than 1.5 s.
   A word is often cut in half ("пост" + "Греску"). The turn text, and therefore the hint, is the concatenation of per-phrase
   Parakeet finals.
2. Parakeet on such pieces gives **23.2% WER** (26 errors in 112 words). Parakeet on the whole question gives **4.5%** in
   0.12 s; Whisper turbo on the whole question gives the same 4.5% but takes 2.3 s. The dominant error is the segmentation,
   not the model.
3. The Whisper "revision" changed 91% of the phrases, but its text never reaches the turn or the hint (it only patches
   `InterviewMemory`). It also competed for the CPU/GPU: the revision backlog reached 107 s, and the hint
   `speech_end → first_token` was 4–7.5 s during the backlog (median 2.2 s, p90 7.5 s overall). The revision cap
   (`revisionMaxQueueDelay = 8 s`, branch `claude/stt-revision-voice-gate-193912`) stops the growth but does not make the
   hint text better.

## Desired outcome
- The hint is built from the question recognized **as a whole**, not from stitched fragments; unfinished fragments are only
  a provisional on-screen preview and never the final text.
- A few extra seconds are acceptable if the answer is accurate and coherent (the owner's priority: accuracy first).
- The owner sees what the app understood: the hint starts by restating the understood question.
- No revision backlog and no heavy background work that delays the next question.

## Owner decisions (2026-11-20, "A+C+D′ + gated drafts")
| # | Question | Decision |
|---|---|---|
| Q1 | Architecture | **A**: re-decode the whole question with Parakeet at turn end and at draft time; partials and phrase finals become provisional only; per-phrase Whisper revision is removed, one background Whisper pass per question stays for history only |
| Q2 | Turn pause | **C**: T 700 → 1000 ms; after "?" 350 → 600 ms |
| Q3 | Understanding | **D′**: the first line of the hint restates the understood question, then the answer (no extra LLM call) |
| Q4 | Speculative drafts | **E, gated**: drafts run only on re-decoded text |
| Q5 | Whisper before the hint | **B** (hint waits for Whisper on the whole question, +2.2–2.4 s) is **not** the default; it stays a fallback decided at the live check on the owner's voice (H-checkpoint in the plan) |
| Q6 | Rehearsal with an interviewer | The re-decode uses joined interviewer-phrase audio (8.0% WER in the experiment), because the audio is not continuous |
| Q7 | Branch base | `claude/stt-revision-voice-gate-193912` (revision cap, `.speaker` event, rehearsal routing — the same code is touched) |

## Out of scope
Changing the STT models, the language gate, the bank/material search, the LLM provider chain, the post-call review and the UI
design (only the provisional marker of a phrase and the first line of the hint are added). No push, no merge into `main`
without the owner's decision.
