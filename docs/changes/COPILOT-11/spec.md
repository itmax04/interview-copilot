# COPILOT-11: Spec

ID: COPILOT-11-spec · Status: **accepted** · Version: 1 · Date: 2026-10-25
Links: [intent.md](intent.md), [plan.md](plan.md)

## Requirements
| ID | Requirement |
|---|---|
| R-01 | When all chain attempts have failed, it does not give up: a "last resort" waits for the nearest key's limit reset (≤ 25 s) and tries slow models with a patient timeout (≥ 12 s); a daily limit (hours) is not waited for. It also works in the parallel mode |
| R-02 | A parallel request (hedge) goes to another provider, not to a second key of the same one: a second key is not faster but spends its own per-minute token limit |
| R-03 | A request with a screenshot is not sent to providers without images (Groq, Cerebras, a custom API) |
| R-04 | Gemini models have a first-token timeout floor of 7 s (measured: the answer arrives in 2.4–3.8 s) |
| R-05 | A prompt rule: to "have you worked with X?" — an affirmative detailed answer (4–6 sentences), relying on the profile, without invented employers, dates and numbers |
| R-07 | The interviewer talking about themselves, the company, the team, the role or the process without a question or a request is not a question: the answer is "—" (previously the model answered "Дякую за представлення, я Олексій…"). If the monologue ends with a question — answer only that |
| R-08 | "Profile → Questions → Delete all…" deletes all the profile's questions after a confirmation; the résumé, instructions and materials stay |
| R-06 | The overlay can be dragged by all sides and corners with the mouse; the cursor changes; a grip icon in the bottom-right corner; the width 280–1000 is remembered and is not reset by the slider |

## Acceptance criteria
| ID | Criterion | How to check |
|---|---|---|
| AC-01 | All keys rate-limited + Gemini did not fit into 4 s → the answer arrives without manual intervention | `ChainResilienceTests`, the test call log (the case at 07:23:28 UTC) |
| AC-02 | A daily limit does not make it wait | `dailyLimitIsNotWaitedFor` |
| AC-03 | A screenshot does not spend attempts on Groq | `screenshotSkipsProvidersWithoutImages` |
| AC-04 | "Have you worked with X?" — "Так…", without a refusal and invented numbers | `--smoke-memory` scenario "experience with a tool" (5/5), `ExperienceRuleTests` |
| AC-05 | Resize strips exist on all sides and corners of the window | `--smoke-panel-resize`, `PanelResizingTests` |
| AC-07 | An interviewer monologue → "—"; a monologue with a question at the end → an answer to the question | `--smoke-memory` scenarios "interviewer…" (12/12) |
| AC-08 | "Delete all…" clears the questions, the file reads as empty | `EmptyQuestionBankTests`, a snapshot of the tab |
| AC-06 | The full CLAUDE.md check passes | command output in the handoff |
