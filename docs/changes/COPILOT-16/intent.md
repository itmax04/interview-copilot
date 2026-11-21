# COPILOT-16: Intent — capture only the call, lock the session language

ID: COPILOT-16-intent · Status: **draft** (2026-11-21: the owner chose "source and language" after the brainstorm) · Version: 1 · Date: 2026-11-21 · Owner: itmax04
Links: spec.md (next stage)

## Problem
The owner noticed that the app recognizes stray sounds and voices: it must hear only the owner and the interviewer(s).
Evidence from the session of 2026-11-21 19:05–19:09 local (session file + app log; numbers and event names only, no
transcript text is kept here):

1. **Source "All system audio".** The session (and the three earlier sessions of that day) captured every sound of the Mac,
   not only the call app. The saved setting is now Telegram, but the session ran with all system audio.
2. **Session language "auto".** `LanguageGate(.auto)` allows {uk, ru, en}, so the "All system audio" rule that drops whole
   English phrases (Q8/Q9 of COPILOT-05) never applies. From 19:06:37 about 20 English phrases at a steady −40…−55 dB with no
   pauses (looks like background video/podcast, not the interviewer) passed as questions; the actual questions were ru/uk.
   Only 5 phrases were dropped by language (de, uk), 22 by VAD.
3. **Hints on noise.** 8 of the 13 hints were built on such phrases (the model answered "Could you clarify …").
4. **Silent microphone.** `mic_db=-120.0` (digital zero) for the whole session while "owner channel" was on:
   `owner_speaking` was never true, 0 owner utterances were saved. The owner's answers and the "owner is speaking" turn
   signal were lost. Cause unknown (wrong input device, headset, mic held by another app); the preflight has a "quiet mic"
   warning, it is unknown whether it was shown or ignored.
5. The voiceprint gate (CAM++, `ownerVoiceOnly`) works only on the microphone channel
   (`ListeningController.updateVoiceGateActive`); the call channel has no speaker filter at all. That is out of scope here
   (see "Later").

## Desired outcome
- By default the app captures only the call app (Telegram / Zoom / Meet in Chrome), not all system audio; choosing
  "All system audio" is a conscious choice with a visible warning before the start.
- The owner sees before the start when other apps play sound that the chosen source would capture.
- A session has a fixed language (or language pair) of the interview; phrases in another language are shown as a gray line
  and never become a question or a hint. The owner can switch the language during the call in one action.
- A silent microphone (digital zero / no signal for N s) during a session is noticed and shown, not only in the preflight.
- No change to the hint latency of normal questions.

## Owner decisions (2026-11-21)
| # | Question | Decision |
|---|---|---|
| Q1 | Direction after the brainstorm | **Source and language** (options 1 + 2 of the brainstorm) plus the silent-microphone diagnosis. Interviewer voice anchoring (option 3) and the "not an interviewer" hotkey (option 4) are later tasks |

## Open questions (for the spec stage; the owner has not answered them yet)
| # | Question | Executor default if unanswered |
|---|---|---|
| O1 | Where did the English speech come from: another tab/video on this Mac, or a person near the owner / the interviewer? | Assume another app on the Mac (the levels and the lack of pauses point to it) |
| O2 | Which call apps are used: Telegram, Meet in Chrome, Zoom? | All three; Meet in Chrome captures every Chrome tab — warn about other audible Chrome tabs |
| O3 | Does an interviewer switch to English mid-interview? | Possible: keep a one-action language switch during the call and the existing exception for short term phrases |
| O4 | Which microphone was used in the session (built-in, AirPods, headset)? | Unknown: detect and report a silent mic, do not guess the device |
| O5 | How many interviewers usually (1, 2–3)? | Not needed for this task (matters for option 3) |

## Ideas to evaluate in the spec
- Session wizard / preflight: default source = detected call app; "All system audio" → warning item; list of other apps
  currently producing audio (ScreenCaptureKit shareable content / NSWorkspace + audio activity, to be checked).
- Language anchoring: language from the wizard, or "auto" fixed to the language group of the first 1–2 questions;
  English phrases from "All system audio" dropped even in auto unless the session language includes English.
- Live silent-mic detector: digital zero or below a floor for ≥ 10 s with the owner channel on → overlay/status warning and
  a log event (`mic_silent`).

## Out of scope
Speaker identification on the call channel (interviewer voice anchoring), speech separation, new models, changes to the
STT pipeline, turn detection, hint text quality filters. No push, no merge into `main` without the owner's decision.

## Later (separate tasks)
- Interviewer voice anchoring on the call channel with CAM++ (several interviewers), gray line for unknown voices.
- Hotkey "this is not the interviewer".
- No hint for incoherent phrases (low recognition confidence + not a question).
