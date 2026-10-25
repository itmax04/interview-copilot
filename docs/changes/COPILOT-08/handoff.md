# COPILOT-08 handoff

ID: COPILOT-08-handoff · Status: **stages 1–3 done (0.6.0, build 26) — H-2: the owner's self-check with their own profile** · Updated: 2026-10-24
Branch: `feat/copilot-08-profiles` (from `feat/copilot-07-hardening` @ `ab4b53f`)
Links: [intent.md](intent.md), [spec.md](spec.md), [plan.md](plan.md)

## Done
- 2026-10-24: a brainstorm (Q1–Q16 in intent.md), intent/spec/plan; H-0 — "start stage 1".
- Stage 1 (P-01, P-02), version 0.5.0:
  - `ProfileLibrary` (CopilotCore/Profiles): profiles `profiles/<id>/` (700/600), creating, renaming, deleting,
    uploading a file into a section with a copy of the source in `sources/`, general instructions `instructions.md`; moving the old
    `profile/` folder — an unchanged copy of the example is deleted (Q12), a changed one is moved as a whole.
  - `DocumentText`: PDF (PDFKit), .docx and .rtf (AppKit), .txt and .md; a scan without text, an unknown format and a broken file —
    clear errors. No new dependencies.
  - Prompt: an `<owner_instructions>` block (general + profile) at the end of the system part — more important than the style/length/format/language rules,
    except the reliability rules; the PII filter applies to instructions too; with instructions the hint's `max_tokens` is 800 and a line
    "the language from the instructions wins". No fact — free improvisation (Q9) without contradicting the profile; a base card —
    "your prepared answer, keep the facts, adapt the wording".
  - The "Profile" window (the menu "Profile: résumé, instructions…", Profile → "Profiles…", launch with `--profile`): choosing, "New…" (⌘N),
    "Rename…", "Delete…" with confirmation; the "Résumé", "Facts about me", "Vacancy" tabs — "Upload file…" (⌘O),
    dragging, editing text with autosave; "Instructions" — profile and general; a character counter per request
    with a warning after 12,000.
  - The Profile menu: the list of profiles, "No profile", "Profiles…"; the active profile is saved (`activeProfileID`).
  - `--smoke-memory`: +4 COPILOT-08 scenarios (no lists per the instruction, "do not mention Kafka", a fact from the résumé, the language from the instructions).
  - The `slowButStartedStreamIsNotTimedOut` test is no longer flaky: a time margin (0.4 s with a 1 s timeout instead of 0.15/0.3).

- Stage 2 (P-03), version 0.5.1 — materials:
  - `Materials.swift`: `MaterialChunker` (a paragraph = a fragment, short pieces are glued up to ~200 characters, a limit of 800; a long
    paragraph — by sentences), `MaterialIndex` (up to 4 fragments, similarity ≥ 0.47, ≤ 3,200 characters), `MaterialIndexBuilder`
    (batches of 8 with progress and cancellation, a vector cache — a binary plist in the profile, 600, cleaned of deleted fragments).
  - `ProfileLibrary`: materials in `materials/<file>.md`, sources in `materials/sources/`; add, delete, read.
  - `BankController.lookup`: one question embedding — both for the bank and the materials; the index is rebuilt in the background on adding,
    deleting, a profile change and a model change. The prompt gets a `<materials>` block (data, the PII filter) and the rule "use if on topic".
    The strong-model answer (⌃⌥C) gets the same fragments; "No profile" — no materials.
  - The "Profile" window → "Materials": "Add files…" (several at once, ⌘O), dragging, viewing the extracted text,
    "Delete…" with confirmation, the indexing status.
  - The `materials` eval (in the default run): 23/24 found, 2/8 extra — PASS. `--smoke-memory`: +2 scenarios (a fact from
    notes, an unrelated fragment is ignored); `INTERVIEWCOPILOT_SMOKE_ONLY`, `INTERVIEWCOPILOT_SMOKE_FULL` for analysis.

- Stage 3 (P-04), version 0.6.0 — questions:
  - `BankCard.status` (`none` / `own` / `draft` / `approved`) and `prepared`; a question without an answer is a valid card that does not go
    into search. `QuestionBankWriter` — writing `questions.yaml` (the same format, answers as a `|` block), old files are readable.
  - `QuestionImport`: rules — Q/A labels, "Вопрос/Ответ", "П/В" (uk), a text table (Tab, " | ", ";"), a numbered
    list, Markdown headings, lines with "?"; if none fit — the model in parts of ≤ 6,000 characters; duplicates are skipped.
  - `QuestionPreparation`: uk/ru/en wordings in batches of 8, drafts in batches of 4 (profile, instructions, up to 4 material
    fragments per question); the result goes by id into the current bank, the owner's answer and edits during preparation are not touched.
  - `AnswerRouter`: "Bank + hint" — the owner's answer that was found goes to the model as the basis ("keep the facts, adapt the
    wording and language"); without models — verbatim; "Question bank only" — verbatim.
  - The "Profile" window → "Questions": a list with statuses and the number of wordings, editing the question/answer/wordings with
    autosave (editing a draft makes it "yours"), "Import file…" (⌘I) with a review of what was found, "Add question",
    "Prepare" with progress and "Stop", "Approve drafts", a warning about unprepared ones.
  - `--smoke-prepare` (wordings, drafts, keeping the answer, bge-m3 search in other languages), an adaptation scenario in
    `--smoke-memory`; `copilot-eval bank --first-only`.

## Executor decisions
- Preparation is by a button, not automatic after the import: the owner chose "a draft in advance, I review and confirm" (Q7), and requests
  spend free limits. Instead of an automatic start — a visible warning: the eval showed that without wordings the search is twice as weak.
- The "Bank + hint" and "Generate every answer" modes now answer the same way when models are available (both adapt); the difference
  remains without models. The mode was not removed: the owner's old settings are read without a reset.
- The `errorStartsNextImmediately` test: the threshold 1 → 3 s (the point is "do not wait for hedgeAfter = 5 s"); under load it was 1.1 s.
- Chunking "a paragraph = a fragment": gluing up to 800 mixed the topics of neighboring paragraphs (eval: 8 fragments, 22/24 → 16 and 24/24 at 0.45).
- The 0.47 threshold (not 0.45): extra fragments for off-topic questions 4/8 → 2/8 at the cost of one miss (a rare ru↔uk term).
- Embedding batches of 8: a question in an interview waits for the indexing no longer than one batch (~0.4 s) — the model lock is shared.
- Indexing speed ~55 ms per fragment (M1): 300 pages (~1,900 fragments) — about 2 minutes in the background, once; then — the cache.
- "Facts about me" = the former `stories.md` (the `<stories>` tag in the prompt): compatibility with COPILOT-01 profiles.
- Instructions are at the end of the system part (last, after the profile): the 07 live run showed that the model follows instructions
  closer to the end more reliably.
- The last profile is not deleted "into nothing": an empty "My profile" is created instead.
- The bank index of the previous profile is reset on switching and is not applied if the profile changed during the rebuild.
- The answer check "1,2 млн" in the scenario also accepts "мільйона": the first run 27/30 — all three FAILs were check errors.

## Checks
| Step | Command | Result |
|---|---|---|
| P-01/P-02 | `swift test` ×3 | 255 tests PASS (+10: profiles, moving the example, PDF/Word/RTF/TXT/MD, scan, import, instructions, settings) |
| P-01 | `scripts/run-evals.sh` | turn 0%/0% · bank 94.9%/0% · filter-text 214/214 · memory 8/8, 0/2 — PASS |
| P-01 | `scripts/secret-scan.sh` | 0 findings |
| P-01 | `--smoke-memory 3` → `2` | 27/30 (3 — check errors) → **20/20** after fixing the check |
| P-02 | `scripts/build-app.sh` | OK |
| P-02 | the "Profile" window live | NOT RUN — H-1, owner |
| P-03 | `swift test` | 260 tests PASS (+5: chunking, index and cache, fragment budget, materials in the profile, the block in the prompt) |
| P-03 | `scripts/run-evals.sh` | turn, bank, filter-text, memory unchanged; **materials 23/24, 2/8 — PASS** |
| P-03 | `--smoke-memory 2` | 21/24 → 24/24: 2 FAILs — check errors ("трьох" ≠ "три"), 1 — Groq/Gemini limits |
| P-03 | `scripts/secret-scan.sh` | 0 findings |
| P-04 | `swift test` ×3 | 268 tests PASS (+8: format and statuses, 7 import formats, parsing with the model, merging, wordings, drafts, request, ChainText) |
| P-04 | `copilot-eval bank --first-only` | one wording per card — top-1 **48.7%** (threshold 0.74; 79.5% at 0.65) versus **94.9%** with wordings in three languages |
| P-04 | `--smoke-prepare` | 7/7: uk/ru/en wordings, drafts without lists per the instruction, your answer intact, en/ru/en search → the right card (0.97 / 0.81 / 0.80) |
| P-04 | `--smoke-memory 2` | **26/26** (including adapting the owner's answer to another language with the numbers kept, 4/4) |
| P-04 | `scripts/run-evals.sh`, `secret-scan.sh` | all PASS, 0 findings |

## Next step
H-2 (AC-08): in 0.6.0 the owner uploads a résumé, instructions, materials and 10 questions (as a file), "Prepare", reviews
the drafts, then a self-check in "Mac microphone". After acceptance — P-05 (the final check, merging per the owner's decision).
