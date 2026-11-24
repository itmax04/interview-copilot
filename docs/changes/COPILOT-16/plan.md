# COPILOT-16: Plan

ID: COPILOT-16-plan · Status: **draft** (for the owner's review) · Date: 2026-11-23
Links: [intent.md](intent.md) · [spec.md](spec.md) · [handoff.md](handoff.md)

Branch: `feat/copilot-16-source-language`. Commit after every step; no push without the owner's permission. After every
step update `handoff.md` (done, commit, checks PASS/FAIL/NOT RUN, next step). Quick check per step:
`swift build && swift test`.

| Step | What | Requirements | Check |
|---|---|---|---|
| P-01 | Baseline at 9922aee (done 2026-11-23: 502 tests, evals, secret-scan, localization PASS; `build-app.sh` NOT RUN). Record the merged commits in the handoff | — | handoff |
| P-02 | Eval first: change the 4 `english-call` cases to drop; add `pseudo-en-call` (≥ 12) and `terms-call` (≥ 8) synthetic cases. Expect filter-text to fail on the new drop cases before P-03 | R-07 | `scripts/run-evals.sh` — filter-text FAIL expected, count recorded |
| P-03 | `LanguageGate`: drop whole English on `.call` when English is not allowed; update the doc comment and COPILOT-05 note on Q8 | R-01, R-02 | `LanguageGateTests` (AC-02); filter-text PASS (AC-01) |
| P-04 | `SessionLanguageLock` in CopilotCore; wire into `ListeningController` gate creation (reset on session start, `language_locked` log); R-04 notice and "Разрешить английский" action in the panel, `language_unlocked` log | R-03, R-04 | `SessionLanguageLockTests` (AC-03) |
| P-05 | `MicSilenceDetector` (pure logic) + panel notice «Микрофон не даёт звука» with the input device name; `mic_silent` log; mute banner priority | R-05 | `MicSilenceDetectorTests` (AC-04); UI snapshot |
| P-06 | "All system audio" notice with «Только звонок» action; wizard footnote; Chrome-tabs note in the source description | R-06 | unit test + UI snapshot (AC-05); `scripts/check-localization.sh` |
| P-07 | Documents (ARCHITECTURE filter section and §9, AGENTS.md, COPILOT-05 Q8 note, CLAUDE.md latest task); independent review of the diff (fresh subagent, standard tier); full check and `scripts/build-app.sh` | R-09, AC-06, AC-08 | full check command |
| H-1 | **Owner live check:** a real call (Meet in Chrome or Telegram) with background foreign/English speech; check gray lines and hints; reproduce the Telegram setup and look at the input device while the microphone is silent (Audio MIDI Setup / System Settings → Sound input, which app holds the mic) | AC-07 | owner's answer; numbers and the cause in the handoff |
| P-08 | Apply H-1 findings (threshold tweaks only, or a documented cause); final handoff with the AC evidence table and unverified items; ask the owner for acceptance | AC-07, AC-08 | handoff; owner acceptance |

Order: P-02 → P-03 → P-04 (gate first); P-05 and P-06 are independent of P-03/P-04 and of each other; P-07 after all code.

Tiers (relay): P-02…P-06 — standard (pure logic plus small UI); P-07 docs — light, review — standard; H-1 — owner.
