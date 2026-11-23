# COPILOT-17: Intent — a Ukrainian question must stay Ukrainian, and a new question must not become a "follow-up"

ID: COPILOT-17-intent · Status: **draft** (owner chose fixes 1+2+3, variant B for uk only, opt-in audio saving on 2026-11-23) · Version: 1 · Date: 2026-11-23 · Owner: itmax04
Links: [spec.md](spec.md), [plan.md](plan.md), [handoff.md](handoff.md)

## Problem
Diagnosis of the live exam-mode session of 2026-11-23 (18:32:43–18:33:54 local; session file + app log; numbers and event
names only — **no transcript text is kept in the repository**). Session language was `uk`, Parakeet + hybrid, exam mode.
The full evidence (file:line) is in the diagnosis note
`~/Library/Application Support/Claude/side-session-notes/local_b3470773-375b-4b4a-abba-ed615b1e6a58/copilot17-uk-question-diagnosis.md`
(outside the repo); it is not re-derived here. Four confirmed causes:

1. **Parakeet ignores the session language.** `ParakeetEngine.transcribe` calls `AsrManager.transcribe(_:decoderState:)`
   without `language:` (`ParakeetEngine.swift:51`); `lang=uk` in the log is only a label (`:55`). One Ukrainian question
   came out Russian, and turn 1 came out in English.
2. **The English turn 1 became the exam ticket root.** `FollowUpDetector.isExamFollowUp`
   (`ScreenshotTask.swift:219-228`) treats every question of ≤ 8 words without a marker as a follow-up to the active
   ticket. Turns 2–4 were follow-ups of the English root; the card showed «К билету: <English text>», and the English
   text went into the prompt (`<active_topic>`, `PromptBuilder.swift:342-348`) and into the materials search
   (`ActiveTopic.swift:39-47`).
3. **The better text arrived too late and only for history.** The background Whisper turbo uk pass finished ~2.1–2.2 s after
   each turn and is written to history only (`StreamingTranscriber.swift:123-138`); it never corrected the ticket root,
   the «К билету» title or the hint.
4. **The hint is built on the Parakeet text.** The hint's «❓» line is written by the model from the Parakeet redecode
   (`QuestionRedecoder.swift:49`, `hintWaitsForWhisper=false` by default), so a wrong Parakeet text means a wrong hint.

Not explained (stays open, see "Later"): why both engines misheard one key word on live audio (codec, echo, the owner's
voice in both streams, pronunciation). Audio is not saved today, so it cannot be examined.

## Desired outcome
- With a fixed session language (uk, ru, en) Parakeet gets the language hint: a Ukrainian question is not returned in
  English. No added latency.
- A question that starts like a new question («назвіть…», «що таке…», «what is…») starts a **new ticket**, not a
  follow-up of the previous one. No added latency.
- When the Whisper history text of the ticket's root turn arrives, the ticket root, its title and the panel entry title are
  corrected, so «К билету» and later prompts/materials search use the better text. No change to the hint latency.
- For Ukrainian sessions the owner can make the hint wait for Whisper («Точный вопрос (+2 с)»): the hint is built on the
  Whisper text. On by default for exam sessions, only when the session language is uk. Cost: ≈ +2.2 s to the first token.
- Optional, **off by default**: the owner can save the audio of recognized questions locally (retention, auto-delete,
  permissions 600), so that a later bake-off of other STT engines can run on real call audio.

## Owner decisions (2026-11-23)
| # | Question | Decision |
|---|---|---|
| D1 | Which fixes | **1 + 2 + 3** (Parakeet language hint, exam follow-up rule, Whisper updates the ticket) |
| D2 | Hint waits for Whisper | **Variant B for uk only**, behind a setting «Точный вопрос (+2 с)», **on by default for exam sessions** |
| D3 | Cloud STT | **No.** Conflicts with the ADR-0001 amendment of 2026-10-08 (free local recognition, no cloud APIs) |
| D4 | Real call audio for a later STT bake-off | **Opt-in local saving**, off by default |
| D5 | Whisper vocabulary prompt (option 5 of the diagnosis) | Not chosen; effect NOT VERIFIED, left for the bake-off |

## Out of scope
- Cloud STT APIs (D3). The STT bake-off itself (it needs the audio of D4 first; a separate task).
- Whisper vocabulary prompt; Whisper-only engine; changing Whisper model size.
- Fixing misheard single words (no option here claims to fix them).
- Turn detection, bank matching, prompt wording, provider chain.
- No push, no merge into `main` without the owner's decision.

## Later (separate tasks)
- STT bake-off (Parakeet, Whisper turbo/medium, other open-source models) on audio saved by R-09, WER and latency.
- Whisper vocabulary prompt from materials/bank (option 5), measured on the saved audio.
- Echo: the owner's voice present in both mic and Chrome streams (levels −15…−34 dBFS).
