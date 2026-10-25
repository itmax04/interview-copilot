# COPILOT-03: Intent — AI voice interview

ID: COPILOT-03-intent · Status: **accepted** (2026-10-22) · Version: 1 · Date: 2026-10-22 · Owner: itmax04
Links: [spec.md](spec.md), [handoff.md](handoff.md), [COPILOT-01 spec](../COPILOT-01/spec.md), [ADR-0001](../../decisions/ADR-0001-stack.md)

## Problem
The test call (v0.1.2) checks recognition on 15 memorized synthetic phrases. The owner wants to check the app in a live
conversation: unfamiliar questions, their own voice, hints in the panel — without a second person.

## Desired outcome
The menu item "AI interview…" opens a local page in Chrome. A model from the settings chain asks questions about the job
and the résumé with a macOS voice; the audio goes through a Chrome tab and real capture, so the app recognizes the
question and shows a hint, as on a call. The owner answers into the microphone; the answer is recognized and sent to the
model, which asks the next question (including follow-ups). The page shows the dialogue, the recognition accuracy of the
questions and — after the owner corrects them — the accuracy on the owner's voice.

## Owner decisions (2026-10-22, Claude Code session)
| # | Question | Decision |
|---|---|---|
| Q1 | Option | An AI interviewer (not free dictation and not the existing Microphone mode) |
| Q2 | Interviewer voice | Built-in macOS speech synthesis, language of choice (uk/ru/en), audio through a Chrome tab |

## Scope
In: the interview page and controller, speech synthesis into an in-memory WAV, switching the recognition source
"Chrome audio ↔ microphone", recognizing the owner's answer, answer correction and WER, a JSON report on a button.
Out: model grading of answers, voices other than the system ones, Zoom/Telegram as the interviewer voice source,
saving the dialogue to session history (except the questions, as with any call).

## Constraints
- The owner's and the interviewer's audio stay in memory only (R-04); nothing is written to disk.
- The owner's answer text goes to the same model as the hints (decision Q6 of COPILOT-01 allows transcripts to Gemini/DeepSeek).
- No new dependencies: AVFoundation (AVSpeechSynthesizer) is a system framework.

## Assumptions
- A-1. Chrome is required: its audio comes from a separate process and is captured by the app filter, like Meet.
- A-2. An answer ends after N s of silence (3 s by default) or on the "I'm done" button.
- A-3. The first question is a greeting plus a question; the model decides itself whether to ask a follow-up or a new topic.
