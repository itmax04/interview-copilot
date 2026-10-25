# COPILOT-09: Plan

ID: COPILOT-09-plan · Status: **accepted** (2026-10-24) · Date: 2026-10-24
Links: [intent.md](intent.md) · [spec.md](spec.md)

| Step | What | Requirements | Check |
|---|---|---|---|
| H-0 | The owner confirms intent/spec | — | the owner's answer |
| P-01 | Stage 1. Sessions: the session model and states, the wizard, Start/End, a timer with a plan, a pre-start check, importing a vacancy from a link, call auto-detection, the Interview/Regular/Mock types | R-01…R-06 | `swift test`, build; H-1 — the owner creates a session |
| P-02 | Stage 2. The live overlay: layout, states, answer history, Chat, ⌘ keys in a session, menu, scale, another display, Private with a check | R-07…R-11, R-17 | `swift test`, `--smoke`; H-2 — the owner on a call |
| P-03 | Stage 3. Answer settings with a live preview | R-12 | `swift test`, `--smoke-memory` |
| P-04 | Stage 4. Review after End: comments, a summary, "Ask AI", a transcript by speaker | R-13, R-14 | `swift test`, `--smoke` |
| P-05 | Stage 5. Screenshot tasks and context, Clear | R-15, R-16 | `swift test`, `--smoke` |
| P-06 | Full check, version, handoff; H-3 — the owner: a session from the wizard to the review | all | the full CLAUDE.md check, AC-11 |

Risks: ⌘↩ in a session intercepts "send" in the Zoom/Meet/Telegram chats (the owner's decision Q10; ⌃⌥ stay);
`sharingType` does not affect ScreenCaptureKit capture in some macOS versions — hence a check, not a promise;
the review and the preview spend free limits — in the background, in batches.
