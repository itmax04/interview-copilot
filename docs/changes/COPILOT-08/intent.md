# COPILOT-08: Intent — profiles: résumé, instructions, materials, questions with answers

ID: COPILOT-08-intent · Status: **accepted** (H-0 2026-10-24: "start stage 1") · Version: 1 · Date: 2026-10-24 · Owner: itmax04
Links: [spec.md](spec.md), [plan.md](plan.md)

## Problem
The owner's details live in text files of the profile folder (`resume.md`, `stories.md`, `questions.yaml`) that
have to be edited by hand; PDF and Word are not read. There is one profile, and the owner's is a made-up example. There is no way to tell the model *how*
to answer: everything in the profile is data, not instructions. There is nowhere to attach materials (notes, documentation).
A bank card is shown verbatim, not adapted to the wording of the question.

## Desired outcome
The owner creates profiles for vacancies, uploads a résumé, a job description, materials (PDF, Word, text), writes their own
instructions (general and per profile) and a list of sample questions (as a free-form file or in a table), optionally with
answers. The app prepares draft answers and wordings in three languages in advance. In the interview the model recognizes a similar
question, relies on the owner's answer and the materials, adapts the answer to the exact wording and follows the instructions.

## Owner decisions (brainstorm 2026-10-24)
| # | Question | Decision |
|---|---|---|
| Q1 | Formats | PDF, Word (.docx), text (.txt, .md, .rtf). Scans/OCR — no |
| Q2 | Where to upload | The "Profile" window (drag or "Upload…"), next to it — the extracted text, which can be edited |
| Q3 | Profiles | Several (per vacancy): its own résumé, vacancy, instructions, materials, questions; switching in the Profile menu |
| Q4 | "Additional hints" | Everything at once: own instructions (style, emphasis, directions — add, change, extend), facts about oneself, the vacancy, topic materials. The model takes everything into account |
| Q5 | Questions | A free-form file + a table in the profile window (add, fix, delete) |
| Q6 | A similar question with the owner's answer | The model adapts the owner's answer to the wording and language (~1 s) |
| Q7 | A question without an answer | A draft in advance: the model prepares answers, the owner reviews, edits, confirms |
| Q8 | Answer logic | If it is in the materials — rely on them, adapting; if not — improvise freely, with own knowledge and context; technical questions — as now |
| Q9 | No fact about experience | **Improvise freely** (including experience and numbers), without contradicting the materials |
| Q10 | Materials volume | Tens to hundreds of pages: the résumé and instructions — in every request, from the materials — 3–5 similar fragments (local bge-m3 search) |
| Q11 | Instructions vs. built-in rules | The owner's instructions win (style, length, format, emphasis, language); only the reliability rules stay: "do not confirm what was not said", "—" for a non-question |
| Q12 | The current example profile | Delete it, start empty |
| Q13 | Parsing the questions file | Local rules first ("?", numbering, Q:/A:, "Вопрос/Ответ"), if that fails — with the model; the result goes to the table for review |
| Q14 | Wordings | Yes: the model adds 3–5 uk/ru/en wordings to each question (once), they are visible and editable |
| Q15 | Instructions | General (everywhere, including "No profile") + per profile; in a conflict the profile wins |
| Q16 | Preparation model | The chain from the settings (free), in batches with pauses because of limits |

## Scope
In: profiles, text extraction, the "Profile" window, instructions, materials with search, questions (import, table,
wordings, drafts), answer adaptation, removing the example, tests, evals, a live run. Out: OCR of scans,
syncing between Macs, new dependencies (PDF — PDFKit, Word/RTF — AppKit, all system frameworks).
