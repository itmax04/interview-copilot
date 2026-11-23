# COPILOT-16: Spec

ID: COPILOT-16-spec · Status: **draft** (for the owner's review) · Version: 1 · Date: 2026-11-23
Links: [intent.md](intent.md), [plan.md](plan.md), [handoff.md](handoff.md)

## Starting point (2026-11-23, HEAD 9922aee)
Six commits landed on this branch after the intent (89522df…9922aee, see handoff "Work merged before the spec"). Two of
them touch this task:
- a45f63b — Quick Start always captures **All system audio** (or the microphone without screen-capture permission);
  `AudioSourceResolver` Auto now falls back to `.allSystem` instead of `.none`; Teams, Discord and Safari were added to
  the Auto list. **Owner decision 2026-11-23:** keep this (all system audio as the Quick Start / Auto fallback) and add a
  warning. This replaces the intent's "call-only capture by default".
- 9922aee — a banner when macOS mutes the default input (`kAudioDevicePropertyMute`) with an "unmute" action. It covers
  one cause of a silent microphone, not the digital-zero case of the analyzed session.

Not done: the language gate (`LanguageGate.swift` is unchanged; whole English phrases still pass on `.call`), the "auto"
language settling, the silent-microphone detection during a session, the "All system audio" warning.

## Requirements
| ID | Requirement |
|---|---|
| R-01 | **Call channel follows the session language.** `LanguageGate.check` drops a whole English phrase (≥ `minWordsToDrop` words, not a term phrase) on **every** channel, including `.call`, when English is not allowed (session uk/ru, or "auto" settled on uk/ru, R-03). The term-phrase rule (all meaningful words in `TermDictionary`, ≤ 4 meaningful words) and the "short phrase is kept" rule stay. COPILOT-05 Q8 (call channel always keeps English) is superseded; the doc comment and COPILOT-05 docs are updated |
| R-02 | **Pseudo-English from another language** (German speech transcribed by Parakeet as English-like words) is dropped by the same rule as R-01 — no new detector. Such phrases are covered by eval cases (R-07) |
| R-03 | **"Auto" settles on the interview language.** With session language "auto", a `SessionLanguageLock` (CopilotCore, pure logic) watches the kept interviewer phrases of ≥ 3 words: after the first 3 such phrases with the same group (slavic or en) it locks the gate to that group for the rest of the session (log `language_locked group=… after=…`). Before the lock the gate behaves as "auto" today. The lock is reset when a session starts. A phrase dropped because of the lock is a gray line, as any dropped phrase |
| R-04 | **One action to recover.** A gray line dropped by language keeps the existing "Ответить" action (answer this phrase anyway, PanelView). In addition, if 2 phrases in a row are dropped as `en` in a locked/uk/ru session, the panel shows a one-line notice «Собеседник говорит по-английски? — Разрешить английский» whose action allows English for the rest of the session (session state only, not the settings); log `language_unlocked reason=owner` |
| R-05 | **Silent microphone during a session.** When the owner channel is on (or the source is the microphone), the session is listening, and the microphone peak stays at digital zero (≤ −119 dB) for ≥ 10 s while the system mute flag is off, the panel shows «Микрофон не даёт звука» with the current input device name and a hint (another app may hold the microphone; check the input device in System Settings → Sound). The notice clears when the level rises. Log once per episode: `mic_silent seconds=… device=… muted=false`. The existing mute banner (9922aee) keeps priority when the mute flag is on |
| R-06 | **"All system audio" warning.** When the session captures `.allSystem` (Quick Start, Auto fallback or explicit choice), the panel shows a compact, dismissible notice for the session: «Слушаю весь звук Mac — видео и уведомления тоже попадут в расшифровку» with the action «Только звонок» when a call app from `AudioSourceResolver.autoPriority` is running (switches the source to that app for the session). The session wizard shows the same text under the "All system audio" choice. When the source is Chrome, the source description notes that every Chrome tab is captured |
| R-07 | **Eval.** `evals/filter/text-cases.jsonl`: the 4 `english-call` cases (uk/ru, `.call`) change to `expect: drop`; add ≥ 12 cases tagged `pseudo-en-call` (synthetic English-like text typical of German misrecognition, uk/ru/auto-locked, `.call`, drop) and ≥ 8 cases `terms-call` (uk/ru questions with IT terms and short English term phrases on `.call`, keep). All synthetic, no real transcript text |
| R-08 | **No latency change.** The gate and lock are pure string logic on the final phrase; no new model or audio pass |
| R-09 | **Documents and localization.** `docs/ARCHITECTURE.md` (filter section, §9 row COPILOT-16), `AGENTS.md` if the source rules change, COPILOT-05 spec note for Q8; new UI strings via `L(...)` with English in `Resources/en.lproj/Localizable.strings`; `IC`/`ICDark` tokens only; CLAUDE.md "latest task" updated to COPILOT-16 |

## Acceptance criteria
| ID | Criterion | How to check |
|---|---|---|
| AC-01 | Filter-text eval passes with the new and changed cases: all `english-call`, `pseudo-en-call` dropped; all `terms`, `terms-call`, `term-phrase`, `short` kept; total correct = total cases | `scripts/run-evals.sh` (filter-text line) |
| AC-02 | Unit tests for R-01: whole English phrase on `.call` with uk/ru → drop; with en/auto (unlocked) → keep; term phrase ≤ 4 words → keep; short phrase → keep | `LanguageGateTests` |
| AC-03 | Unit tests for R-03/R-04: lock after 3 same-group phrases; no lock on mixed or short phrases; reset per session; unlock action allows English; 2 consecutive `en` drops raise the notice once | `SessionLanguageLockTests` |
| AC-04 | Unit tests for R-05 detector (pure logic: level samples + mute flag + time → notice on/off, one log per episode) | `MicSilenceDetectorTests` |
| AC-05 | R-06: notice shown for `.allSystem`, not for `.app`/`.microphone`; «Только звонок» offered only when a call app is running (resolver test) | unit test + UI snapshot (`UISnapshots`) |
| AC-06 | Turn, bank, memory, materials evals unchanged (turn 0%/0%, bank top1 ≥ 94.9%) | `scripts/run-evals.sh` |
| AC-07 | **Live check (H-1):** a Meet or Telegram call with a uk/ru interviewer and foreign/English background speech: background phrases are gray, questions with IT terms get hints; a silent microphone (if it happens) is shown; the owner confirms the cause of the Telegram digital-zero case or it is documented as unknown with the device data | owner, handoff |
| AC-08 | Full check: `swift test && scripts/run-evals.sh && scripts/secret-scan.sh && scripts/check-localization.sh && scripts/build-app.sh` | command output in the handoff |

## Risks
| Risk | Mitigation |
|---|---|
| A real interviewer asks a whole English question in a uk/ru session and it is dropped | Owner (O3): interviewers do not switch to English; gray line keeps «Ответить»; R-04 notice allows English in one action |
| "Auto" locks on the wrong group (e.g. first phrases are English small talk) | Lock needs 3 phrases of ≥ 3 words of one group; R-04 unlock; the wizard's explicit language is unaffected |
| Long uk/ru questions mostly made of English terms read as "English" | Majority-of-words rule unchanged; `terms-call` eval cases guard it |
| Digital zero cause is outside the app (Telegram voice processing, another input) | R-05 shows it live; H-1 investigates with the owner; no system settings are changed by the app beyond the existing unmute action |
| Quick Start overwrites the saved source setting with `.allSystem` (a45f63b) | Out of scope; recorded in the handoff for the owner |
