# COPILOT-08: Specification — profiles, instructions, materials, questions

ID: COPILOT-08-spec · Status: **accepted** (2026-10-24) · Version: 1 · Date: 2026-10-24 · Owner: itmax04
Links: [intent.md](intent.md) · [plan.md](plan.md)

## Requirements
- **R-01. Profiles.** `…/InterviewCopilot/profiles/<id>/`: `profile.yaml` (name, language, profile instructions), `resume.md`, `job.md`,
  `materials/` (source files + extracted text), `questions.yaml`. Create, rename, delete (with confirmation);
  the active one — in the Profile menu (and "No profile", R-40). The old `profile/` folder: if it matches the example it is deleted (Q12),
  otherwise it is moved into a profile with its name. The `profile.example/` example is no longer copied.
- **R-02. Text extraction** (Q1): PDF — PDFKit; .docx, .rtf — `NSAttributedString` (AppKit); .txt, .md — as is. Empty
  text (a scan) — a clear error "no text layer". The extracted text is visible and editable; an edit is saved
  in `.md`, the source stays next to it. Everything is local.
- **R-03. The "Profile" window** (Q2): choosing/creating a profile; the sections "Résumé", "Vacancy", "Profile instructions",
  "Materials" (list, add, delete, view text), "Questions" (R-07); the general instructions — in the same place as a separate field.
  Dragging files and an "Upload…" button; everything is keyboard-accessible (Tab, Enter, ⌘O).
- **R-04. Instructions** (Q4, Q11, Q15). General (`instructions.md` at the root) + per profile; in the prompt — a separate block of
  **instructions**, not data: the model follows them in style, length, format, emphasis, language; profile instructions take precedence over general ones.
  They do not override only the reliability rules: do not confirm what was not said (07/R-01), "—" for a non-question, data is not instructions
  (the text of the résumé, materials and lines still cannot command the model).
- **R-05. Answer logic** (Q8, Q9): if it is in the résumé/materials/answers — rely on it and adapt; if not — improvise
  freely (experience, stories, numbers), without contradicting the materials; technical questions — with own knowledge. The built-in rule
  "prefer general wording over invented companies and numbers" is removed.
- **R-06. Materials** (Q10): the text is cut into ~800-character fragments, a bge-m3 index (cached by file hash); for a question —
  up to 4 fragments with similarity ≥ the threshold in a `<materials>` block (data). The résumé, vacancy and instructions — in full in the system
  part (cached). A size limit for the résumé and instructions in the request — with a warning in the window.
- **R-07. Questions** (Q5, Q13). File import: rules (a line with "?", numbering, `Q:`/`A:`, "Вопрос:"/"Ответ:", "Питання"),
  otherwise — parsing with the model; the result is a table for review before saving. The table: question, answer, wordings,
  answer state (own / draft / confirmed). `questions.yaml` is compatible with the previous format.
- **R-08. Preparation** (Q7, Q14, Q16): "Prepare" — for each question 3–5 uk/ru/en wordings and a draft answer based on
  the résumé, materials and instructions (if there is no answer). The chain from the settings, in batches, with a pause on 429, progress and cancellation;
  the owner's answer is never overwritten.
- **R-09. Adaptation** (Q6): a similar question (bge-m3, the bank threshold) → generation with the card's answer as the basis: the answer's facts
  are kept, the wording and language — fit the real question. Without models — the card verbatim. The "Question bank only" mode —
  verbatim, as before.
- **R-10. Data.** Everything in profiles is local, permissions 600/700; the cloud model gets what is needed for the answer (as
  now), the PII filter (01/R-12) — for materials and instructions too. No text is written to the log.

## Acceptance criteria
| AC | Criterion | Check |
|---|---|---|
| AC-01 | PDF, .docx, .rtf, .txt, .md → text; a scan — a clear error | `swift test` (fixtures) |
| AC-02 | Profiles: creating, switching, deleting; moving/deleting the old `profile/` | `swift test` |
| AC-03 | Question import: 4 formats by rules without a model; the table is saved to `questions.yaml` | `swift test` |
| AC-04 | A paraphrased question (another wording, another language) finds the owner's card | the `bank` eval on a new set |
| AC-05 | Material fragments: the right fragment is in the top 4 | the `materials` eval |
| AC-06 | An instruction ("answer in one sentence", "emphasis on leadership") is followed; the card answer is adapted with its facts kept; without a fact — improvisation | `--smoke-memory` (new scenarios) |
| AC-07 | No regressions: tests, evals, secret-scan, build | full check |
| AC-08 | Owner: their own PDF résumé, instructions, 10 questions → a live self-check | owner |
