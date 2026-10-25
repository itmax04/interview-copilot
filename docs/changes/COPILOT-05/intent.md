# COPILOT-05: Intent — only the interview participants' speech

ID: COPILOT-05-intent · Status: **accepted** (2026-10-23, "yes, I accept, start the first stage") · Version: 1 · Date: 2026-10-23 · Owner: itmax04
Links: [spec.md](spec.md), [plan.md](plan.md), [handoff.md](handoff.md), [COPILOT-04](../COPILOT-04/spec.md),
[COPILOT-03](../COPILOT-03/spec.md), [ADR-0001](../../decisions/ADR-0001-stack.md)
Source of decisions: a brainstorm with the owner on 2026-10-23 (four blocks of questions, answers in the table below).

## Problem
In tests in the "Mac microphone" mode, the transcript picks up other voices (people nearby), TV, video and music,
noise without speech (keyboard, street — turns into "Угу", "Yeah") and speaker echo. This spoils the transcript and the hints.
In addition, speech in other languages gets into the transcript (for example, German from a TV), although the interview is in the selected language.

## Desired outcome
- Only the interview participants' speech gets into the transcript and the hints: interviewers (there may be several) and the owner.
- Speech in other languages does not get in, but English professional terms inside speech in the selected language are kept.
- Filtered content is shown as a gray line and does not affect hints, so a filter mistake is easy to notice.

## Owner decisions (2026-10-23)
| # | Question | Decision |
|---|---|---|
| Q1 | Where the extraneous sounds were noticed | The "Mac microphone" mode |
| Q2 | What interferes | People nearby; TV, video, music; noise without speech; speaker echo |
| Q3 | Whose speech is needed | Several interviewers + the owner |
| Q4 | What to do with filtered content | Show it in gray, it does not go into hints or history |
| Q5 | How to recognize the owner's voice | Record a 20–30 s sample once; only a "print" (numbers) is stored |
| Q6 | Why transcribe the owner's speech | Only as context for hints (the text goes to the model); not in the panel, not in history. **Changed 2026-10-23 (COPILOT-06 Q1): saved in session history** |
| Q7 | Ukrainian is selected but Russian is heard (or vice versa) | Let both through: uk and ru are one group |
| Q8 | A whole English phrase of the interviewer in a uk/ru interview | Let it through in the call channel; the strict filter is for the microphone and "All system audio" |
| Q9 | Terms | Rule + dictionary: Latin script inside a phrase in the selected language — always; a whole English phrase on the microphone — if ≤ 4 words and all words are terms (résumé, job, bank, a built-in IT list) |
| Q10 | Speed | Everything on by default, separate toggles in Settings → Audio |
| Q11 | Headphones | Varies — echo cancellation is needed |
| Q12 | Language "Auto" | Let only uk / ru / en through, the rest — gray |
| Q13 | Self-check "Mac microphone" | Only the owner's voice counts as questions |
| Q14 | Call channel | A neural speech detector + the language filter, no noise suppression (questions are not slowed down) |
| Q15 | Verification | Synthetic mixes + a live test by the owner (~10 min) |
| Q16 | Order | Task → stages with separate builds |

## Scope
In:
- two channels with different rules — the call (interviewers) and the microphone (only the owner);
- a neural speech detector (Silero), a language filter with an exception for terms;
- the owner's voiceprint (CAM++), microphone noise and echo suppression (LocalVQE);
- the owner's speech as hint context; a synthetic set and the `filter` eval.

Out:
- separating interviewers from each other (diarization); filtering other voices on the interviewer's side;
- noise suppression of the call channel (Q14); new languages beyond uk/ru/en;
- showing the owner's speech in the panel and history (Q6).

## Constraints
- Everything is local: audio is not written to disk (01/R-04); the voice sample is deleted after the print is computed.
- The voiceprint is biometric data: only on this Mac, deleted with a button, not in Git and not in logs.
- **Exception to 01/R-02** (the microphone is not transcribed): per decisions Q3/Q6 the owner's speech is transcribed,
  its text goes to the model only as hint context.
- New FluidAudio models (Silero VAD, CAM++, LocalVQE) — with a pinned revision and SHA256, recorded in ADR-0001.
  No new SwiftPM packages: everything is in FluidAudio 0.17.7.
- Memory ≤ 1.5 GB (01/R-25); the latency of questions from the call does not grow (COPILOT-04).

## Assumptions
- A-1. On a real call the voices in the owner's room do not get into the call channel (capture per app); their source is
  only the microphone.
- A-2. In the "Mac microphone" mode without call audio there is nothing to cancel echo against: only noise suppression.
- A-3. The synthetic macOS voices (Lesya, Milena, Samantha, Daniel, Fred, Anna, Thomas) are enough for the initial
  threshold tuning; thresholds are checked on the live voice at H-2.

## Open questions
No blockers. Checked along the way: the voice similarity threshold on the live voice (P-04, H-2); whether echo cancellation works
without headphones at loud speaker volume (P-05).
