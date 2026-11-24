# COPILOT-15: Spec

ID: COPILOT-15-spec · Status: **draft** (for the owner's review) · Version: 1 · Date: 2026-11-20
Links: [intent.md](intent.md), plan.md (written in the next stage)

Measured baseline (experiment of 2026-11-20, synthetic `say` voices Lesya/Milena, 6 dense questions, 112 words, audio cut near
every 1.1 s like the live median):

| Condition | WER | compute per question |
|---|---|---|
| Parakeet per chunk (today's hint text) | 23.2% | 0.37 s |
| Whisper turbo per chunk (today's revision) | 19.6% | 10.1 s |
| Parakeet, whole question, continuous audio | 4.5% | 0.12 s |
| Parakeet, phrase audio joined with 150 ms gaps | 8.0% | 0.11–0.37 s |
| Whisper turbo, whole question | 4.5% | 2.26 s |

## Requirements
| ID | Requirement |
|---|---|
| R-01 | **Whole-question re-decode.** When a turn completes (and when a draft is requested, R-08), the question text is obtained by one Parakeet pass over the audio of the whole question, not by concatenating phrase finals. The re-decoded text is the question for the hint, the bank/material lookup, `InterviewMemory.addQuestion`, answer history and the review |
| R-02 | **Audio range.** The question audio range runs from the start of the first phrase of the turn (including the pre-roll) to the end of the last phrase. If the range is continuous and ≤ 30 s, it is read from `AudioRingBuffer` (`read(from:to:)`). Otherwise (turn longer than the 30 s buffer, a range with a gap or a dropped phrase, or rehearsal routing where only interviewer phrases belong to the question) the saved audio of the turn's phrases is joined with 150 ms silence gaps and decoded. Audio stays in memory only and is released after the pass; nothing is written to disk |
| R-03 | **Rehearsal routing.** In "Rehearsal with an interviewer" the `.speaker` event decides which phrases belong to the question; only those phrases are joined (R-02). Owner phrases (answers) never enter the question audio |
| R-04 | **Provisional text.** `.partial` and phrase `.final` text is provisional: it may be shown in the transcript and used for end-of-turn heuristics (word count, "?", unfinished phrase) but is never the final question text. The transcript line of the turn is replaced by the re-decoded text when it arrives; the UI marks a not-yet-confirmed phrase (subdued style, no new colour tokens: `IC` tokens only) |
| R-05 | **Fallback.** If the re-decode fails or exceeds its budget (2 s), the turn falls back to the concatenated phrase finals, a metric `redecode_failed` is logged, and the hint is generated as before; the failure never blocks the answer |
| R-06 | **Revision removal.** The per-phrase Whisper revision (`.revised` per utterance, `allowRevision`, the revision queue and `revisionMaxQueueDelay`) is removed from the live path. The revision backlog can no longer exist |
| R-07 | **Background Whisper pass for history.** After a question's turn completes, one Whisper pass over the same question audio (R-02) runs in the background, at most one in flight (a newer question replaces a waiting older one; a stale result older than 8 s of queue is dropped). Its text only replaces the question text in `InterviewMemory`/history/review (whole-word `reviseText` rules stay); it never changes a hint already shown and is never an input of the current hint. It is skipped when the CPU is needed for the next question (a new utterance has started) |
| R-08 | **Gated drafts.** A speculative draft (`AnswerController.prefetch`) is started only on re-decoded text: when a phrase ends and the pause approaches T, a re-decode of the audio so far is run first and its text is the draft text. A draft is adopted by the turn only if the final re-decode text equals the draft text (existing adopt/cancel logic); if the speaker continued, the draft is cancelled. With `speculativeAnswers` off nothing changes |
| R-09 | **Turn thresholds.** `TurnDetector.Config.thresholdMs` 700 → 1000; `questionThresholdMs` 350 → 600 (after "?"). `continuationExtraMs` (1300) and the rest stay. `evals/turn` is re-run and its expected latencies/limits are updated for the new defaults |
| R-10 | **Understood-question line (D′).** The hint prompt (`PromptBuilder`) requires the first line of every generated hint to restate the question as understood (one short sentence, in the question's language, marked so the UI can style it, e.g. a leading "❓ "), followed by the answer. It restates, it does not correct or invent: terms and facts not in the audio or the profile are not added. The line is not sent to the bank-card path (cards have their own question text), is excluded from the "—" (not a question) answer, and is excluded from the copy-to-clipboard text unless the owner copies the whole hint. The strong-model/coding path is unchanged |
| R-11 | **Owner channel.** The owner's answers (second `StreamingTranscriber`, `InterviewMemory.addAnswer`) follow the same rule: phrases are provisional, and an answer is re-decoded as a whole when the owner's speech ends (microphone VAD plus the same pause logic), using the owner's own audio range. No Whisper pass is run on this channel in the live path (CPU is needed for the interviewer); the background Whisper pass (R-07) may run on it only when idle |
| R-12 | **Metrics.** New `Log.metrics` lines: `redecode turn=… audio_ms=… decode_ms=… source=ring\|joined words_provisional=… words_final=…`, `redecode_failed`, `whisper_history turn=… decode_ms=… queued_ms=…`. The existing `first_token … ms_from_speech_end` line stays and is the source of AC-03 |
| R-13 | **Settings.** No new user-facing settings. Turn thresholds and the re-decode budget are `Config` defaults (testable); the live check (H-checkpoint) may flip a single internal switch to fallback B (R-14) without a rebuild of the logic |
| R-14 | **Fallback B (prepared, off by default).** A `Config` switch `hintWaitsForWhisper` (default false): when true, the hint starts only after Whisper turbo has decoded the whole question (+2.2–2.4 s on M1), and that text replaces the Parakeet text. It is enabled only if the live check shows Parakeet drift (uk→ru, wrong terms) on the owner's voice. Implemented minimally so that the decision is a one-line change; not exposed in the UI |
| R-15 | **Documents and localization.** `docs/ARCHITECTURE.md` (§ speech/turns, §9 task index) and `evals/README.md` describe the new flow and the new eval; new UI strings follow the localization rules (`L(...)`, `en.lproj`, `scripts/check-localization.sh`) |

## Acceptance criteria
| ID | Criterion | How to check |
|---|---|---|
| AC-01 | **Dense-speech STT eval.** A new eval set `stt-dense` (`evals/stt-dense/`, synthetic audio generated by a script like `scripts/make-voice-fixtures.py`; ≥ 6 dense questions, ≥ 100 words, uk/ru/en as the app uses them) run by `copilot-eval stt-dense` compares *chunks* (today's behaviour) with *whole question* (continuous) and *joined phrases* (rehearsal). Thresholds: whole-question WER ≤ 8%, joined-phrase WER ≤ 12%, and whole-question WER ≤ half of the chunk WER. Baseline from the experiment: 4.5% / 8.0% / 23.2% | `scripts/run-evals.sh stt-dense` (needs the Parakeet model; NOT RUN is reported if absent) |
| AC-02 | **No revision backlog.** The live path has no per-phrase Whisper queue (R-06). In a replay of the dense-speech fixture as a continuous call, the maximum of the Whisper history queue is ≤ 1 in flight and no result older than 8 s is applied; the old `phrase_end_to_revised_ms` metric no longer exists | unit tests for the history scheduler; replay run; grep of the metrics in the log |
| AC-03 | **Latency budget.** On the replay and on the live check, hint `speech_end → first_token` has median ≤ 3.0 s and p90 ≤ 5.0 s (baseline outside the backlog: median ≈ 2.2 s; the re-decode adds ≈ 0.1–0.4 s, the longer T adds ≤ 0.3 s, D′ adds ≈ 0.2–0.4 s). The re-decode itself: median ≤ 0.5 s for a question ≤ 15 s | `first_token` and `redecode` metric lines (`scripts/metrics.py`) |
| AC-04 | **Turn eval PASS.** `scripts/run-evals.sh turn` passes with the new defaults: premature 0, missed 0 on the 36 existing cases; mean latency within the new limits (baseline at T = 1000: 739 ms) | `scripts/run-evals.sh turn` |
| AC-05 | **Provisional text never final.** Unit tests: a turn built from provisional phrases has its question text replaced by the re-decode result; with a failing re-decode the fallback text is used and `redecode_failed` is logged; a draft is created only from re-decoded text and cancelled when the speaker continues | `TurnRedecodeTests`, `DraftGatingTests` |
| AC-06 | **Audio range.** Unit tests: continuous range ≤ 30 s → ring read; range > 30 s, gap, dropped phrase or rehearsal routing → joined phrases with 150 ms gaps; owner phrases excluded in rehearsal mode; no audio file is created | `QuestionAudioRangeTests` |
| AC-07 | **Rehearsal mode.** The rehearsal scenario (interviewer + owner voices) yields question text from interviewer phrases only and answers from the owner channel; joined-phrase WER meets AC-01 | rehearsal part of `stt-dense`, `RehearsalRoutingTests` |
| AC-08 | **Hint format.** Generated hints start with the understood-question line; a bank card, "—" and the coding path do not; the line does not add terms absent from the question (checked on the `memory`/`bank` eval cases by comparing the line with the re-decoded question) | `PromptBuilderTests`, `scripts/run-evals.sh memory bank` |
| AC-09 | **Owner channel.** An owner answer is stored from the re-decoded text; the owner channel starts no Whisper pass in the live path | `OwnerAnswerRedecodeTests` |
| AC-10 | **Live check on the owner's voice** (H-checkpoint): at least 10 real questions (uk) over a test call; the owner confirms the understood-question line matches what was asked in ≥ 9/10 cases and decides whether fallback B (R-14) is switched on. The decision and the numbers (WER by eye, `first_token`, `redecode`) are recorded in the handoff | owner, handoff |
| AC-11 | The full check passes: `swift test && scripts/run-evals.sh && scripts/secret-scan.sh && scripts/check-localization.sh && scripts/build-app.sh` (plus `stt-dense` when the models are present) | command output in the handoff |

## Risks
| Risk | Mitigation |
|---|---|
| Parakeet drifts uk → ru on the owner's real voice (not reproduced by the synthetic voice) | Language is passed from the phrase language state, not re-detected; H-checkpoint (AC-10) decides fallback B (R-14), which is prepared but off |
| Re-decode of a long turn (near 30 s) is slow or truncated | Ring read only ≤ 30 s; longer turns use joined phrases; R-05 budget 2 s and fallback to phrase finals |
| Joined phrases lose context at the gaps (8.0% vs 4.5%) | Used only where the range is not continuous; 150 ms gaps were measured |
| Longer T (1000 ms) and "?" (600 ms) add latency | Measured +0.14 s mean in the turn eval; AC-03 budget includes it; the benefit on long mid-question pauses is unmeasured and is checked live |
| D′ restates wrongly or adds invented terms | Prompt forbids correction and invention; AC-08 check; the line shows the owner what was understood, so an error is visible |
| Technical terms (Kubernetes, PostgreSQL, Swift) are still misheard (the remaining errors) | Existing term dictionary; background Whisper text for history only; out of scope to change models |
| Gated drafts rarely adopted because T is longer | A draft saves time only when the re-decode text equals the final one; acceptable, drafts are an optimization |
| Removing the Whisper revision lowers transcript accuracy in history | R-07 background pass per question keeps it for history/review |
| Synthetic eval (small sample, synthetic voices) over-states the gain | Thresholds have margin; live check (AC-10) is the real test |

## Rejected options
| Option | Why rejected |
|---|---|
| **B as default** — the hint waits for Whisper on the whole question | +2.2–2.4 s on M1 for no measured accuracy gain (4.5% = Parakeet 4.5%); kept only as a prepared fallback (R-14) |
| **D** — separate LLM "understanding" call before the hint | Estimated +0.5–1.5 s, extra Groq tokens per minute, risk of invented corrections, not measured; D′ gives the same visibility without a call |
| **F** — text-level merge of adjacent phrases | Cannot rebuild cut words ("пост" + "Греску"); the audio must be re-decoded |
| Keep the per-phrase Whisper revision | 91% of phrases changed, but the text never reached the hint; it caused the backlog (up to 107 s) and CPU contention |
| Whisper instead of Parakeet for the re-decode | Same WER on the experiment (4.5%) at 2.3 s instead of 0.12 s; ADR-0001 FLEURS: Parakeet 4.52% vs turbo 4.70% |
