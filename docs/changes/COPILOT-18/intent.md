# COPILOT-18: Intent — the owner's own voice must not start hints, and the owner can switch the app's microphone off

ID: COPILOT-18-intent · Status: **draft** (owner decisions D1–D8 of 2026-11-24) · Version: 1 · Date: 2026-11-24 · Owner: itmax04
Links: [spec.md](spec.md), [plan.md](plan.md), [handoff.md](handoff.md)

## Problem
In the owner's Meet self-test (a second device next to the Mac, Meet sound through the Mac speakers, so the Mac microphone heard both
voices) the overlay showed an extra «Версия 2 · с вашего голоса» and a retitled question. The owner's own microphone phrase had been
classified by `OwnerQuestionDetector` as a voice clarification of the last question (≤ 5 words within 25 s, or a starter such as
«коли / що таке / як»); wiring: `listening.onOwnerSaid` (`App.swift`) → `AnswerController.handleOwnerQuestion` (label `ownerVoice`).
Not a COPILOT-17 regression. No transcript text is kept in this repository.

Two separate needs follow:
1. The automatic «уточнение голосом» is a surprising side effect for most sessions. It must be an explicit opt-in.
2. During a call the owner sometimes talks to someone else, coughs, or speaks near the speakers; there is no way to tell Copilot
   "do not listen to me now" without muting Meet itself.

## Decisions (brainstorm, 2026-11-24)
- **D1** The automatic voice clarification (owner voice → new, replaced or clarified hint) becomes a setting, **off by default** for all
  session types. Off: owner speech never starts or changes a hint; it still goes to memory, history and review as an answer.
- **D2** A toggle «Микрофон выкл.»: press to turn off, press again to turn on (not hold-to-mute, not automatic).
- **D3** Off means the owner microphone is fully ignored by Copilot: no recognition, no owner text in history, memory or review, no
  hints. Meet and the system mute are not touched.
- **D4** Every session starts with the microphone on; the state is not remembered.
- **D5** An overlay toolbar button between «Скриншот» and «Чат» and a global hotkey ⇧⌘M (works while Meet is focused).
- **D6** Indicator only: a red "off" state; no reminders, no auto-unmute; the «Микрофон не даёт звука» notice is suppressed while off.
  Separate from `PanelModel.micHardwareMuted` (macOS mute).
- **D7** Session history and review mark the muted intervals, so the review does not say the owner did not answer.
- **D8** New task on `feat/copilot-18-mic-toggle` from `feat/copilot-17-uk-question`; one live check (H-1) covers COPILOT-17 and 18.

## Scope
In: the setting (D1); the toggle, button, hotkey, indicator (D2–D6); history/review marks (D7); effect on turn detection, echo
handling, `voiceGate`, test call and rehearsal (checked, see spec). Out: changing the detector's rules, cloud features, pushing
anything, touching system security settings.
