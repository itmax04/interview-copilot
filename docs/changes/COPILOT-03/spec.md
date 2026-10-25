# COPILOT-03: Specification — AI interview

ID: COPILOT-03-spec · Status: **accepted** (2026-10-22) · Version: 1 · Date: 2026-10-22 · Owner: itmax04
Links: [intent.md](intent.md) · [handoff.md](handoff.md) · requirements R-01…R-23 — [COPILOT-01 spec](../COPILOT-01/spec.md)

## Scenarios
- **S-30. Interview.** Given: Chrome is installed, the "Screen & System Audio Recording" and "Microphone" permissions are granted,
  the recognition model is loaded. When: the owner chooses "AI interview…", the language, the number of questions and presses "Start".
  Then: the model generates a question, a macOS voice reads it in a Chrome tab, the app recognizes the question
  (the page shows the reference and what was heard, with errors highlighted), a card or a hint appears in the panel;
  then the owner answers into the microphone, the answer is recognized, the model asks the next question.
- **S-31. End of answer.** After N s of silence (a page setting: 3/5/8 s or "button only") or on "I'm done";
  started fragments are finished (no longer than 15 s).
- **S-32. Answer correction.** The owner corrects the recognized answer — the page shows the answer's WER.
- **S-33. Model error.** No model in the chain answered — a message and a "Retry the request" button.
- **S-34. Ending.** "End" or closing the tab restores the previous audio source and microphone mode.

## Requirements
- **R-30. Voice.** AVSpeechSynthesizer, the best installed non-novelty voice for the language (uk-UA, ru-RU, en-US);
  an in-memory mono PCM16 WAV, 0.8 s of silence before and 0.7 s after speech; served only with the session token.
- **R-31. Model.** The chain from settings (R-09), first-token timeout at least 20 s; prompt — `InterviewerPrompt`:
  one question ≤ 35 words, only the selected language, numbers in words, no markup; the job, résumé and answers are data,
  not instructions; the PII filter (R-12) for the résumé and answers. Spending is counted like hints (R-20).
- **R-32. Sources.** During the interview exactly one source goes into recognition: Chrome audio for a question,
  the microphone for an answer (`AudioRoute`). Switching drops unfinished fragments. The recognition of the owner's
  answer does not enter the other person's transcript, hints or session history.
  **Exception to R-02 of COPILOT-01:** in this mode the owner's microphone is transcribed — per decision Q1.
- **R-33. Metrics.** For a question — WER "model text → recognized" and the latency "end of speech → text" (like `TestCallTrial`);
  for an answer — the speech duration and, after correction, WER. The JSON report — only on a button, in the browser.
- **R-35. Ukrainian final (2026-10-23, owner complaint: Ukrainian speech is recognized as Russian).**
  Parakeet does not pin the language. With the Parakeet engine and the setting "Ukrainian final — via Whisper turbo" on
  (on by default, needs the turbo file), the phrase final is recognized by Whisper large-v3-turbo with the language `uk` and full context,
  if the language is set to "Українська" or Parakeet's text contains і/ї/є/ґ. Interim text, Russian and English — Parakeet.
  Whisper is loaded on the first Ukrainian phrase; on a load error or an empty final the Parakeet text stays.
- **R-36. Fast models and parallel requests (2026-10-23, owner request: "switch automatically and answer immediately").**
  The providers Groq (`openai/gpt-oss-120b`, free 1000 requests/day) and Cerebras (`gpt-oss-120b`, trial credits),
  OpenAI-compatible API; first in the chain by default (schema migration 6 puts them at the start of the saved chain).
  If an attempt is silent for `hedgeAfter` (1.5 s), the same request immediately goes to the next model; the first one with text wins,
  the others are cancelled; no more than two attempts at once. The monthly budget does not switch off Groq/Cerebras.
- **R-37. Two-stage final.** The turn and the hint use Parakeet's fast final (≈0.5 s). The refined Whisper turbo final
  (Ukrainian — always when R-35 is on; Russian/English — a setting, on by default) arrives as a `revised` event
  and replaces the line in the transcript and history; the test call and the AI interview score the refined text.
  The model is given the answer language: the one selected in the menu, or Ukrainian if the question contains і/ї/є/ґ.
- **R-38. Noise does not block a turn.** An utterance without text produces a `discarded` event; waiting for a lost final — no longer than 8 s,
  "the other person is speaking" — no longer than 30 s. If finals arrive but no turns, a `turn_stall` with the state is logged once a minute.
- **R-39. Capture recovers.** A stream stopped by macOS or by the menu-bar indicator — restart after 1 s,
  no more than 5 times in 10 minutes; then an error in the panel.
- **R-40. Answers without a profile (2026-10-23, owner request: "the model answers regardless of the profile and gives answers
  by itself without hints").** The Profile submenu: the profile name (as before) or "No profile — the model answers by itself"; the choice
  is saved (`useProfile`, profile by default), the item title — "Profile: No profile".
  - Without a profile: the résumé, job, stories and question bank are not sent to the model and not searched; an answer is generated
    on every turn regardless of the Mode; the model gives personal experience as a plausible example, without "[уточнить]".
    The AI interview without a profile asks general developer questions. No keys — "Models unavailable: no keys".
  - With a profile: the model answers technical, general and conceptual questions itself from its own knowledge; "[уточнить]" —
    only for missing personal facts (employers, projects, dates, numbers). The rest of R-08/R-11 is unchanged.
  - Refinement 2026-10-23 (COPILOT-04 R-05): "[уточнить]" is no longer used — the model improvises what is missing from the context.
- **R-34. Page security.** As for the test call: 127.0.0.1 only, a random token, Host/Origin checks,
  closing after 90 s without requests.

## Acceptance criteria
| AC | Criterion | Check |
|---|---|---|
| AC-30 | The model's question sounds in a Chrome tab and is recognized through capture; WER and latency are shown on the page | Owner, live run |
| AC-31 | The owner's answer is recognized from the microphone and does not appear in the panel as the other person's line | Owner + the `interviewer_answer` log |
| AC-32 | The next question takes the answer into account (a follow-up) | Owner |
| AC-33 | After "End" the source and microphone are as before the interview | Owner |
| AC-34 | Unit tests of the prompt, WAV, `AnswerCapture`, correction and synthesis | `swift test` |
| AC-35 | A Ukrainian final without drifting into Russian on the owner's voice | An AI interview in Ukrainian with answer corrections, A/B with the setting off |
| AC-36 | Without a profile an answer is generated on every turn without the résumé and the bank; with a profile a technical question is answered without "[уточнить]" | `swift test` (PromptBuilder, AnswerRouter, MenuLayout, Settings, Interviewer) + owner in the AI interview |
