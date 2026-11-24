# COPILOT-15 — H-1 live check (checklist for a computer-use agent)

ID: COPILOT-15-h1 · Status: ready to run · Written: 2026-11-21
Links: [spec.md](spec.md) · [plan.md](plan.md) (row H-1) · [handoff.md](handoff.md) (P-11 state, P-12 prep state)

## Purpose
Live confirmation of what unit tests and offline evals cannot show: the app built from `feat/copilot-15-accurate-turns`
(commit `27692b1` or later) on real capture, real Parakeet, a real LLM provider and the owner's real voice.
It produces evidence for AC-02, AC-03, AC-05, AC-07, AC-09, AC-10 and R-14 (fallback B decision), and the
dense-call replay that P-12 left NOT RUN.

The check has two parts:
- **Part A — the agent alone** (synthetic voices, ≈ 30 min). Everything that does not need the owner.
- **Part B — with the owner** (≈ 20 min). The owner speaks; the agent drives the app, watches and records.

Result: `docs/changes/COPILOT-15/h1-report.md` (template at the end) and a short summary to the owner in Russian.

## Hard rules for the agent
1. **No code changes.** Do not edit `Sources/`, `Tests/`, settings files or scripts. If something fails, record it — the
   fix belongs to P-13. The only files you create: `h1-report.md` and scratch files outside the repository.
2. **No system security or privacy settings.** Do not open or click in System Settings → Privacy & Security (microphone,
   screen & system audio recording, accessibility), do not answer TCC dialogs, do not touch Keychain. If the app asks
   for a permission or a key, stop and ask the owner to do it by hand.
3. **No API keys.** Never type, paste, read aloud or screenshot a key. If no LLM provider works, the hint parts are
   NOT RUN — say so.
4. **No personal data in files.** The owner's real answers and anything the owner says in Part B are never written to the
   report, commits or chat — only counts, yes/no, numbers. Questions come from the synthetic list below.
   `scripts/metrics.py` and the app log contain numbers only; do not paste overlay transcript text from Part B.
5. **Git:** at most one commit with `h1-report.md` (message `COPILOT-15 H-1: live check report`, English). No push,
   no branch changes, no reset, no stash.
6. **Never invent a result.** Every row is PASS / FAIL / NOT RUN with the observed number or a one-line reason.
7. Talk to the owner in Russian.

## 0. Preparation
| # | Step | How | Expected |
|---|---|---|---|
| 0.1 | Correct branch and clean tree | `git -C <worktree> status -sb`, `git log --oneline -3` | `feat/copilot-15-accurate-turns`, top commit `27692b1` or later, clean |
| 0.2 | Quick check | `swift build && swift test` | PASS, ≥ 470 tests. FAIL → stop, report |
| 0.3 | Build the app | `scripts/build-app.sh` (2–5 min) | `dist/InterviewCopilot.app` exists, script exits 0 |
| 0.4 | Quit any running copy | menu bar icon → Quit, or `pkill -x InterviewCopilot` | no process `InterviewCopilot` |
| 0.5 | Fixtures present | `ls evals/audio/stt-dense/*-full.wav` | 8 files (en1, en2, ru1, ru2, uk1–uk4). Missing → `python3 scripts/make-dense-fixtures.py`; still missing → Part A.2 NOT RUN |
| 0.6 | Launch | `open dist/InterviewCopilot.app` | menu bar icon appears. A permission dialog → stop, ask the owner (rule 2) |
| 0.7 | Mark the log start time | `date "+%Y-%m-%d %H:%M:%S"` → note it as `T0` | used for `metrics.py --start` |

## 1. Settings to verify before the run (read only, change only what is listed)
Open the app's Settings window. Labels below are the Russian UI; with the English UI they are translated (`Resources/en.lproj/Localizable.strings`).
| # | Setting | Expected | Evidence for |
|---|---|---|---|
| 1.1 | «Пауза конца вопроса T: … мс» | **1000 ms** (was 700) | R-09, settings migration (schema 7) |
| 1.2 | «Пауза после вопроса со знаком «?»: … мс» | **600 ms** (was 350) | R-09 |
| 1.3 | Recognition | Parakeet v3 (+ Whisper turbo); the status line says "Распознавание: Parakeet v3 …" | engine |
| 1.4 | «Начинать ответ заранее, не дожидаясь паузы» | on (default) | drafts (R-08) |
| 1.5 | «Учитывать мои ответы в подсказках (на созвоне)» | on (default) | owner channel (R-11) |
| 1.6 | «Репетиция с собеседником: чужой голос — вопросы, мой — ответы» | off for Part A.2 and Part B; on only in A.4 | AC-07 |
| 1.7 | Language | Auto (UK/RU/EN) | — |

If 1.1 / 1.2 show other values: record them. If they are 700 / 350, the migration failed → FAIL (do not fix by hand
before recording; after recording you may set 1000 / 600 so the rest of the check is meaningful, and note that).

## Part A — the agent alone

### A.1 LLM provider available?
Start a session (menu → start session; source **All system audio** («Весь системный звук»), mode "Bank + hint"). In Terminal:
`say -v Milena "Расскажите, пожалуйста, как вы организуете код в большом проекте?"`
- A hint card appears → provider works, continue.
- No card within 15 s and the overlay shows a provider/key error → hint rows (A.2.4, A.2.5, B.*) are NOT RUN; still do
  the transcript and metric rows. Tell the owner the key must be added by hand.

### A.2 Dense-call replay (P-12 replay, AC-02, AC-03, AC-05, R-01…R-04)
Source: **All system audio**, rehearsal off. Play every dense question as one continuous call, 8 s of silence between
questions so each becomes its own turn:
```
for f in evals/audio/stt-dense/{uk1,uk2,uk3,uk4,ru1,ru2,en1,en2}-full.wav; do afplay "$f"; sleep 8; done
```
Watch the overlay while it plays (screenshots are fine in Part A — the content is synthetic).

| # | Check | How to see it | Expected |
|---|---|---|---|
| A.2.1 | Provisional lines | transcript strip while a question is spoken | new phrase lines are dimmed (≈ 50% opacity), no animation |
| A.2.2 | One line per question | transcript strip ≈ 1–3 s after the question ends | the dimmed lines of the question are replaced by **one** full-opacity line with the whole question |
| A.2.3 | Text quality | compare that line with the reference text in `evals/stt-dense/texts.json` (same id) | by eye: no words lost at phrase cuts; count wrong/missing words per question |
| A.2.4 | Understood-question line | answer card | first line, dimmed, starts with "❓" and restates the question (no answer content in it); the answer follows below |
| A.2.5 | Copy without the line | copy button on the card, then `pbpaste \| head -2` | copied text does **not** start with "❓" |
| A.2.6 | One turn per question | log `turn_end` count (§3) | exactly 8 `turn_end`, no question split into two turns, none merged |
| A.2.7 | Re-decode metric | `redecode` / `redecode_failed` in the log | 8 `redecode` lines, `source=ring` for most, `decode_ms` median ≤ 2000; `redecode_failed` 0 (any → note reason) |
| A.2.8 | Latency | `scripts/metrics.py --start "<T0>"` | `C15 redecode decode_ms` PASS; `AC-03 turn_end → first_token` median ≤ 2500 ms (includes re-decode); record `C4-AC-01 speech_end → first_token` too |
| A.2.9 | Drafts | `metrics.py` "Опережающие запросы" block and `draft_used` in the log | some `draft_used` > 0 (drafts adopted because texts are equal). 0 used with drafts started → FAIL of R-08 adoption, note it |
| A.2.10 | History pass | `whisper_history` lines | for uk questions: `outcome=applied` or `unchanged`; ru/en need none. No `whisper_history` before its `turn_end`. Hint card text does not change after it appears |
| A.2.11 | Memory/CPU | `scripts/footprint-monitor.sh 10` running in a second Terminal during A.2 | no growth trend across the 8 questions; record peak MB |

### A.3 Owner channel with a synthetic "owner" (AC-09, R-11)
Purpose: show that owner answers arrive as **one** answer per pause, re-decoded, with no Whisper on that channel.
Limitation: if the owner has a voiceprint enrolled (Settings → voice), the voice gate rejects a synthetic voice — then
A.3 is NOT RUN and is covered in B.3.

Source must be a **call source** (owner channel works only with an app source or All system audio). Use All system audio.
Interviewer audio and owner audio must not overlap (echo rule drops mic phrases during call speech and 1.5 s after).
1. Play one question: `afplay evals/audio/stt-dense/uk1-full.wav`; wait for the hint.
2. Wait 3 s, then speak the "owner" answer into the room so the mic hears it — two sentences with a ~0.6 s gap, then silence:
   `say -v Lesya "Я працював з цим у попередньому проєкті." ; sleep 0.6 ; say -v Lesya "Ми використовували модульну архітектуру."`
   (`say` goes to the speakers; the mic picks it up. Also captured by All system audio, so it will also show in the
   interviewer strip — expected with this setup; ignore it for this check.)
3. Wait 4 s.

| # | Check | Expected |
|---|---|---|
| A.3.1 | `owner_final` lines after step 2 | exactly **one** `owner_final … phrases=2 redecoded=true` (phrases may be 1 if VAD joined them) |
| A.3.2 | No Whisper on the owner channel | no `hybrid revision` stt log line between the owner speech and the next `turn_end` other than the `whisper_history` of the interviewer turn |
| A.3.3 | Answer in memory | History window → this session → the exchange for the question shows one owner answer entry |

If `owner_final` never appears: check `filtered reason=echo channel=mic` (overlap — repeat with a longer wait) or
`reason=lang`; record what was seen.

### A.4 Rehearsal routing (AC-07) — only if a voiceprint is enrolled
Rehearsal routes by the owner's voiceprint; synthetic voices are all "not the owner". So in Part A only check that with
rehearsal **on** and source **Mac microphone**, a synthetic question (`say -v Milena "…?"` out loud) produces a turn and
a hint, and no `owner_final mode=rehearsal`. The owner-voice half is B.4.

### A.5 Pause / Clear while a turn is pending
Play `afplay evals/audio/stt-dense/ru1-full.wav` and press Pause (overlay) within 0.5 s after the audio ends.
Expected: no hint card for that question, no crash; after resuming, the next question works normally.

## Part B — with the owner (the owner's real voice, AC-10, R-14)
Ask the owner to join only when Part A is done. Explain in Russian what will happen (≈ 20 min).

### B.0 Setup
- Meet call as in `evals/live-script.md` "Preparation" (owner reads questions from a phone into Meet; Mac mic muted
  in Meet; headphones if available). Source: Chrome (or Auto), mode "Bank + hint", Auto language.
- Note `T1` (`date`) for `metrics.py --start`.

### B.1 Ten Ukrainian questions (AC-10)
The owner reads each question from the phone, normally, at their usual pace; after the hint appears the owner says
whether the "❓" line matches what they asked (yes / partly / no). Record only the verdict and the question number.

| # | Question (uk, synthetic) |
|---|---|
| 1 | Розкажіть коротко про себе і про ваш останній проєкт. |
| 2 | Яку архітектуру ви обирали для великого iOS-застосунку і чому саме її? |
| 3 | Як ви працюєте з конкурентністю у Swift — актори, async/await, черги? |
| 4 | Розкажіть про найскладніший баг, який ви знаходили, і як ви його шукали. |
| 5 | Як ви організуєте тестування: модульні тести, UI-тести, снапшоти? |
| 6 | Що ви робите, коли дедлайн горить, а вимоги ще змінюються? |
| 7 | Як ви ставитеся до код-рев'ю і що для вас важливо в чужому коді? |
| 8 | Чи доводилося вам навчати молодших розробників? Як це було? |
| 9 | Як би ви прискорили повільний список із тисячами елементів у SwiftUI? |
| 10 | Чому ви вирішили змінити роботу і що шукаєте в новій команді? |
| 11 (spare) | Розкажіть про проєкт, який… *(2 s pause)* …ви вважаєте своїм найкращим. |
| 12 (spare) | Які у вас очікування щодо зарплати? |

Per question record: understood line yes/partly/no; one turn or split; language shown as uk (not ru); terms correct
(SwiftUI, async/await, код-рев'ю…) yes/no. Threshold: **≥ 9 of 10 "yes"**.

### B.2 Fallback B decision (R-14)
Ask the owner, after B.1: did Parakeet drift to Russian or mishear terms on their voice?
- Drift seen in ≥ 2 questions, or the owner says so → recommendation **B on** (P-13 sets
  `config.hintWaitsForWhisper = true` for the interviewer transcriber in `ListeningController.recognizerLoaded` (`var config = StreamingTranscriber.Config()`), then
  `first_token` is re-measured; expect +2.2–2.4 s).
- Otherwise → **B stays off**.
The decision is the owner's. Record the owner's words as "B on" / "B off" — do not change code.

### B.3 Owner answers (AC-09, live)
For 3 of the questions the owner answers out loud into the Mac microphone after the hint (2–4 sentences with natural
pauses shorter than 1 s). Check in the log: one `owner_final … redecoded=true` per answer (not one per sentence);
History shows one answer entry per question. Do not copy the answer text anywhere.

### B.4 Rehearsal (AC-07) — optional, only if a voiceprint is enrolled and the owner agrees
Source Mac microphone, rehearsal on. Someone else (or the phone speaker) asks 2 questions, the owner answers.
Expected: questions → hints; owner phrases → `owner_final mode=rehearsal`, not turns; the "❓" line contains the
question only, none of the owner's words.

### B.5 Thresholds feel
Ask the owner: does 1000 ms / 600 ms feel right (hint not too late, questions not cut)? Record "ok" / "too slow" /
"cuts questions" with the question numbers.

### B.6 Metrics for Part B
`scripts/metrics.py --start "<T1>"` — record the table (numbers only).

## 3. Log commands
```
/usr/bin/log show --predicate 'subsystem == "com.itmax04.interviewcopilot"' --info --start "<T0>" > "$TMPDIR/h1.log"
grep -c "turn_end" "$TMPDIR/h1.log"
grep -E "redecode|redecode_failed" "$TMPDIR/h1.log"
grep -E "owner_final|whisper_history|draft_(start|used|cancelled)|hybrid revision" "$TMPDIR/h1.log"
python3 scripts/metrics.py "$TMPDIR/h1.log"
```
The log holds events and numbers only (no utterance text). Keep `h1.log` outside the repository.

## 4. Report template (`docs/changes/COPILOT-15/h1-report.md`)
```
# COPILOT-15 — H-1 report
Date: … · Commit: … · App version: … · Machine: … (chip) · Provider worked: yes/no

## Preparation and settings
| # | Result | Observed |
(0.1–0.7, 1.1–1.7)

## Part A
| # | Result (PASS/FAIL/NOT RUN) | Observed (numbers, short reason) |
(A.1–A.5)
metrics.py table for Part A (pasted)
Per-question word errors (A.2.3): uk1 …, uk2 …, … (counts only)

## Part B
| Q | Understood line | One turn | Language uk | Terms ok |
(1–10, spares if used)
Total "yes": N / 10 → AC-10 PASS/FAIL
Fallback B: owner decision "on"/"off"; reason in one line
Owner answers (B.3): N answers, N owner_final lines, redecoded=true N
Rehearsal (B.4): …
Thresholds feel (B.5): …
metrics.py table for Part B (pasted)

## Problems found (for P-13)
- … (what, where seen, how to reproduce; no personal text)

## Not run
- … (why)
```
Then add one line to `handoff.md` → Progress table: `| H-1 | done (agent + owner) | <commit> | see h1-report.md |`,
and under "Next": the owner's B decision.
