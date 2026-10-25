# COPILOT-08: Plan

ID: COPILOT-08-plan · Status: **accepted** (2026-10-24) · Date: 2026-10-24
Links: [intent.md](intent.md) · [spec.md](spec.md)

| Step | What | Requirements | Check |
|---|---|---|---|
| H-0 | The owner confirms intent/spec | — | the owner's answer |
| P-01 | Stage 1. Profiles on disk, moving/removing the example, PDF/Word/RTF/text extraction, general and profile instructions in the prompt, the new answer logic | R-01, R-02, R-04, R-05, R-10 | `swift test`, `--smoke-memory` (instructions) |
| P-02 | The "Profile" window: profiles, résumé, vacancy, instructions, uploading and editing text; the Profile menu | R-03 | `swift test`, build; H-1 — the owner uploads their résumé |
| P-03 | Stage 2. Materials: fragments, a bge-m3 index, the `<materials>` block; the `materials` eval | R-06 | eval, `swift test` |
| P-04 | Stage 3. Questions: import (rules + model), table, preparation (wordings, drafts), card adaptation | R-07, R-08, R-09 | the `bank` eval, `swift test`, `--smoke-memory` |
| P-05 | Full check, version, handoff; H-2 — the owner's live self-check with their own profile | all | the full CLAUDE.md check, AC-08 |

Risks: complex PDF layout (columns) gives mixed-up text — it can be fixed in the window; large materials — only
fragments, no full text; Groq limits while preparing hundreds of questions — batches and pauses, drafts can be prepared in parts.
