# COPILOT-16: Intent — foreign speech on the call channel, call-only capture, silent microphone

ID: COPILOT-16-intent · Status: **draft** (2026-11-21: the owner chose "source and language" after the brainstorm and answered O1–O5) · Version: 2 · Date: 2026-11-21 · Owner: itmax04
Links: spec.md (next stage)

## Problem
The owner noticed that the app recognizes stray sounds and voices: it must hear only the owner and the interviewer(s).
Evidence from the session of 2026-11-21 19:05–19:09 local (session file + app log; numbers and event names only, no
transcript text is kept here).

**Test setup (owner, 2026-11-21):** a Telegram call with himself. The MacBook (running the app, Telegram) was the
candidate side — the owner answered into the Mac. The questions were asked from an iPhone with wired AirPods.
**People near the owner were speaking German** during the call.

1. **German room speech came through the call channel.** The iPhone/AirPods microphone picked up the German speakers, and
   Telegram delivered it to the Mac. Parakeet transcribed it mostly as English-like phrases (the text language detector
   said `en` for ~20 phrases from 19:06:37, steady −40…−55 dB, no pauses; one Spanish-like phrase; only 2 phrases were
   detected as `de` and dropped). So the stray speech is **the interviewer's background**, not another app on the Mac:
   per-app capture alone would not have removed it.
2. **The language gate lets whole English phrases through on the call channel.** Session language was "auto"
   (`LanguageGate(.auto)` → {uk, ru, en}). And even with uk/ru, a whole English phrase on the `.call` channel is always
   kept (COPILOT-05 Q8); only `.mic` / `.allSystem` drop it. The owner confirmed (O3) that interviewers do not switch to
   English — only separate (IT) words appear.
3. **Hints on noise.** 8 of the 13 hints were built on such phrases (the model answered "Could you clarify …").
4. **Source "All system audio".** The session (and the three earlier sessions of that day) captured every sound of the Mac.
   In this session it did not cause the noise (point 1), but it would let any video or notification in.
5. **Silent microphone during a Telegram call.** `mic_db=-120.0` (digital zero) for the whole session while the owner
   answered into the Mac and "owner channel" was on: `owner_speaking` was never true, 0 owner utterances were saved. The
   owner's answers and the "owner is speaking" turn signal were lost. Suspected: the call app holds the input (voice
   processing) or a different input device is selected — to be investigated, not guessed. The earlier sessions of the day
   saved owner utterances (2, 8, 4), so the mic capture works in general. (Info-level log lines of the earlier sessions
   are no longer in the system log; the 19:05 log excerpt was taken during the analysis.)
6. The voiceprint gate (CAM++, `ownerVoiceOnly`) works only on the microphone channel; the call channel has no speaker
   filter. That is out of scope here (see "Later").

## Desired outcome
- With session language uk/ru, a whole phrase in English (or any other language) is a gray line on **every** channel,
  including the call; short IT-term phrases (the term dictionary rule) still pass. Speech that the recognizer turns into
  pseudo-English from another language (German) is dropped the same way.
- "Auto" does not let a foreign language in by default: the session settles on the language group of the interview
  (from the wizard or from the first questions); English is allowed only when the session is in English.
- By default the app captures only the call app (Meet in a browser, Telegram, Zoom, Discord), not all system audio;
  "All system audio" shows a warning before the start.
- A silent microphone (digital zero / no signal for N s) during a session is noticed and shown, not only in the preflight;
  the cause found for the Telegram case is fixed or documented.
- No change to the hint latency of normal questions.

## Owner decisions and answers (2026-11-21)
| # | Question | Answer / decision |
|---|---|---|
| Q1 | Direction after the brainstorm | **Source and language** (options 1 + 2) plus the silent-microphone diagnosis. Interviewer voice anchoring and the "not an interviewer" hotkey are later tasks |
| O1 | Where did the stray speech come from? | People near the owner speaking **German** (it reached the Mac through the call) |
| O2 | Call apps | Mostly **Google Meet**; sometimes Telegram, Discord, Zoom (Discord is not in `AudioSourceResolver.autoPriority` yet) |
| O3 | Do interviewers switch to English? | **No**, only separate words (IT terms) |
| O4 | Setup of the test | Telegram call with himself: Mac = candidate (answers), iPhone + wired AirPods = interviewer |
| O5 | How many interviewers | Varies (matters for the later voice-anchoring task) |
| O6 | Browser for Meet | **Google Chrome** (already first-class in `AudioSourceResolver.autoPriority`; capturing Chrome captures all its tabs — another audible tab leaks in) |

## Open (for the spec stage)
- Why the Mac microphone gave digital zero during the Telegram call (investigate on the device; H-checkpoint with the owner).

## Out of scope
Speaker identification on the call channel, speech separation, new models, changes to the STT pipeline, turn detection,
hint text quality filters. No push, no merge into `main` without the owner's decision.

## Later (separate tasks)
- Interviewer voice anchoring on the call channel with CAM++ (a varying number of interviewers), gray line for unknown
  voices — the direct fix for a same-language voice in the interviewer's room.
- Hotkey "this is not the interviewer".
- No hint for incoherent phrases (low recognition confidence + not a question).
