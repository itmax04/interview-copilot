# COPILOT-04: Specification — instant answers

ID: COPILOT-04-spec · Status: **accepted** (2026-10-23) · Version: 1 · Date: 2026-10-23 · Owner: itmax04
Links: [intent.md](intent.md) · [handoff.md](handoff.md) · COPILOT-01 requirements are prefixed "01/", COPILOT-03 — "03/"

## Requirements
- **R-01. Speculative request.** As soon as the final of a finished utterance arrives (≥ 3 words, not cut off, the other person
  and the owner are silent, no final of a next phrase is expected), the model gets the question without waiting for the pause T
  (`TurnDetector.draft`, `AnswerController.prefetch`). The answer accumulates and is shown when the turn with the same text
  arrives (01/R-05); a different text or a pause cancels the request. A bank card does not need a speculative request.
  Spending and key errors are counted for cancelled requests too (01/R-20). The Audio setting
  "Start answering early, without waiting for the pause", on by default.
- **R-02. Pause after a question.** If the utterance ends with "?", the turn fires after `questionPauseMs` (350 ms by default,
  200–1500, no more than T). Starting with a question word — the `questionStarters` flag, off (no gain on the eval).
- **R-03. The gist on the first line.** The answer starts with one short bold phrase, then 2–5 bullets, ≤ 80 words.
- **R-04. Measurement.** Log: `draft_start`, `draft_used` (start from the end of speech, the margin before the turn), `draft_cancelled`,
  `first_token … speculative=0|1`. `scripts/metrics.py`: the metric "end of speech → first words" and a summary of
  speculative requests. `copilot-eval turn`: a `draft:` line (request start, extra requests).
- **R-05. Improvisation.** The model does not write "I don't know", does not refuse and does not put "[уточнить]" placeholders:
  when data is missing it improvises a plausible answer from the context (job, profile, conversation, industry practice);
  it does not contradict personal profile facts, and missing ones are given in general words, without invented companies and exact numbers.
  A question with recognition errors — answer the most likely one given the context. Replaces the "[уточнить]" rule
  in 01/R-11 and 03/R-40.
- **R-06. Custom API (2026-10-23, owner request "the ability to add my own API key").** The `custom` provider —
  any OpenAI-compatible Chat Completions (OpenRouter, OpenAI, Together, Mistral, Ollama/LM Studio on this Mac).
  Settings → Keys, a "Custom API" block right after Groq: API address, model, key (Keychain), "Check" (`GET …/models`),
  "Make first in the chain". The address — HTTPS only; HTTP — only localhost/127.0.0.1 (01/R-23).
  Without an address or a model the provider is not in the chain and is not shown in the "Models" line. Request parameters are generic:
  `max_tokens` (for api.openai.com — `max_completion_tokens` and no `temperature`); images are not sent.
  The budget does not switch it off: the app does not know the prices, spending is visible at the provider.

## Acceptance criteria
| AC | Criterion | Check |
|---|---|---|
| AC-01 | Median "end of question → first words" ≤ 1000 ms on 20 AI-interview questions (Groq first) | `scripts/metrics.py` on the logs, owner (H-1) |
| AC-02 | turn eval: premature 0%, missed 0%; the speculative request starts before the turn | `scripts/run-evals.sh turn` |
| AC-03 | Cancelled speculative requests ≤ 25% of started ones in a live run | `scripts/metrics.py` |
| AC-04 | Prompt: gist on the first line, improvisation instead of "[уточнить]" | `swift test` (PromptBuilderTests) + owner assessment |
| AC-05 | Unit tests of TurnDetector ("?" pause, draft) and eval summaries | `swift test` |
| AC-06 | Custom API: address check, request, chain, settings; a live answer through the owner's key | `swift test` (CustomProviderTests) + owner |
