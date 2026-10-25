# COPILOT-05: Specification — filtering extraneous speech and language

ID: COPILOT-05-spec · Status: **accepted** (2026-10-23, "yes, I accept, start the first stage") · Version: 1 · Date: 2026-10-23 · Owner: itmax04
Links: [intent.md](intent.md) (decisions Q1–Q16) · [plan.md](plan.md) · [handoff.md](handoff.md)
Numbers without a prefix belong to this task; previous ones — "01/", "03/", "04/". Requirements of previous tasks apply, except for the exceptions below.

## 1. Terms
- **Call channel** — the audio of the call app (Chrome/Zoom/Telegram) or "All system audio". The source of the interviewers' speech.
- **Microphone channel** — the Mac microphone. The source of the owner's speech; in the "Mac microphone" mode — also of questions (self-check).
- **Voiceprint** — 192 numbers (a CAM++ embedding) from a sample of the owner's speech; compared by cosine similarity.
- **Allowed languages** — uk+ru (a group), en; the set depends on the Language choice (R-05).
- **Filtered utterance** — a final text that did not pass the filter; shown in gray with a reason, does not go into hints.

## 2. Scenarios
- **S-01. A TV in German.** Given: "Mac microphone", Language = Українська. When: a TV speaks German nearby.
  Then: the TV line is gray "ignored: language de", no hint appears.
- **S-02. Terms.** Given: Language = Русский. When: "Как вы настраивали CI/CD и code review в GitLab?".
  Then: the utterance passes, the Latin terms are kept.
- **S-03. Another voice nearby.** Given: a voice sample is recorded, "Mac microphone". When: a person nearby speaks Russian.
  Then: gray "ignored: other voice".
- **S-04. An English phrase by the interviewer.** Given: a Meet call, Language = Русский. When: the interviewer says
  "Let's continue in English. Tell me about your last project." Then: the utterance passes (Q8), there is a hint.
- **S-05. Noise without speech.** When: a keyboard, music without words, a street. Then: no utterances (speech detector).
- **S-06. Echo without headphones.** Given: a call, Mac speakers. When: the interviewer speaks, the microphone hears the speakers.
  Then: the echo is not transcribed as the owner's speech; the owner's speech is.
- **S-07. The owner's answer as context.** When: the interviewer asks a follow-up after the owner's answer.
  Then: the model gets the owner's last lines and does not repeat what was said; they are not in the panel.
- **S-08. A filter mistake.** When: a needed utterance became gray. Then: a click on the gray line or ⌃⌥↩ within 15 s —
  an answer to it.
- **S-09. Voice sample.** When: Settings → Audio → "Record a voice sample", reading a text for 20–30 s.
  Then: "Sample saved", there are "Re-record" and "Delete"; the sample audio is deleted after the computation.

## 3. Requirements
- **R-01. Two channels.** The call channel — as now (01/R-01, 01/R-03), filters R-02 and R-05. The microphone channel:
  - on a call it is transcribed (an exception to 01/R-02), passes R-02…R-05, the result is only hint context (R-07);
  - in the "Mac microphone" mode — the source of questions, only the owner's voice is accepted (Q13);
  - in the AI interview (03/R-32) the owner's answer passes the same voice filter.
  The "the owner is speaking" detection (01/R-02, S-07 TurnDetector) stays.
- **R-02. Speech detector.** Silero VAD (FluidAudio `VadManager`, streaming mode) instead of the energy detector
  on both channels; segments without speech are not recognized. The threshold — by the `filter` eval. A "Neural speech detector" toggle.
- **R-03. Voiceprint.** A 20–30 s sample (text on screen, uk/ru/en to choose); CAM++ → an embedding in
  `…/InterviewCopilot/voice/owner.json`, the sample audio is not saved. A microphone phrase ≥ 1 s is accepted if the similarity
  is ≥ the threshold (from the eval, recorded in evals/README); shorter than 1 s — by the similarity of neighboring phrases or as in R-05.
  Without a sample: only R-02, R-04, R-05 and the hint "Record a voice sample" in Audio. A "Only my voice" toggle.
- **R-04. Microphone noise and echo suppression.** LocalVQE v1.3, the 16 ms streaming mode. The echo reference signal is
  the captured call audio if capture is running; otherwise — only noise suppression (A-2). The call channel is not processed (Q14).
  A "Noise and echo suppression" toggle.
- **R-05. Language filter** (the final text of each utterance).
  - Allowed: Українська/Русский → {uk, ru}; English → {en}; Auto → {uk, ru, en} (Q7, Q12).
  - Phrase language: Apple `NLLanguageRecognizer` (on device) + the share of Cyrillic/Latin; uk and ru are one group.
  - Latin words inside a phrase in an allowed language are always kept (Q9).
  - A whole English phrase with uk/ru: passes in the call channel (Q8); on the microphone and in "All system audio" — only
    if ≤ 4 words and all words are dictionary terms: résumé, job, `questions.yaml`, a built-in IT list (`Resources/terms-en.txt`).
  - A phrase shorter than 3 words with an uncertain language is not dropped (better to let it through than to lose a question).
  - A "Language filter" toggle.
- **R-06. Filtered content.** A gray line in the transcript with a reason ("language de", "other voice"); does not go into turn
  detection, hints, history or context; S-08 — an answer to it on request. In call mode the filtered microphone speech
  is not shown (the owner's speech is not shown in the panel — Q6).
- **R-07. Context from the owner's speech.** Up to 3 of the owner's last phrases that passed the filter (≤ 600 characters) in the prompt
  as a separate `<candidate_said>` block — data, not instructions (01/R-11), the PII filter (01/R-12).
- **R-08. Models.** Silero VAD, CAM++, LocalVQE v1.3 — the official FluidInference repositories on Hugging Face,
  a pinned revision and SHA256 in a manifest (like `parakeet-models.json`), the installer `scripts/fetch-filter-models.py`,
  `ModelHub.offlineMode = true` at runtime. No models → the corresponding filter is off, with a hint in Audio.
- **R-09. Log.** Numbers only: `filtered reason=lang|voice|vad channel=call|mic lang=… similarity=…`; no text is logged (01/R-24).
- **R-10. Audio settings.** Four toggles (R-02…R-05), on by default (Q10); voice sample buttons (S-09).

## 4. Acceptance criteria
| AC | Criterion | Check |
|---|---|---|
| AC-01 | Foreign language: on ≥ 30 synthetic mixes (a uk/ru/en question + a de/fr/en TV, music, noise) ≥ 90% of foreign phrases are filtered; ≤ 5% of needed phrases dropped | `filter` eval |
| AC-02 | Terms: ≥ 15 uk/ru phrases with English terms — 0 dropped, Latin script kept | `filter` eval |
| AC-03 | Voice: the "owner" (a synthetic voice with a sample) accepted ≥ 95%, other voices rejected ≥ 90% | `filter` eval (`say` voices) + H-2 on the live voice |
| AC-04 | Noise without speech: ≥ 20 recordings — no more than 1 utterance | `filter` eval |
| AC-05 | Latency: call channel — the median "end of speech → final" no worse than 0.1.11 + 50 ms; microphone channel — no more than +300 ms | `scripts/metrics.py`, the test call |
| AC-06 | Memory ≤ 1.5 GB over 10 minutes with all filters | `scripts/footprint-monitor.sh 10` |
| AC-07 | A live 10-minute test (TV / a person nearby): the owner rates "no extraneous speech in hints" in ≥ 4 of 5 episodes | H-2 |
| AC-08 | `swift test`, bank/turn evals (previous thresholds), secret scan 0, build and signing | commands in the report |
