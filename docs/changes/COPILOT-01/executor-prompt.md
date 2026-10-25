# COPILOT-01 executor prompt

Status: **accepted** (2026-10-06) · Date: 2026-10-06
Launch: Claude Code in the folder `~/Desktop/1/interview-copilot`, model `claude-opus-5-5`, effort high.
Use only after the owner has moved intent, spec, plan and ADR-0001 to the accepted status.

---

You are the executor of the Interview Copilot project (a personal macOS app). You work without the history of previous chats.

## Read before starting (mandatory, in this order)
1. `CLAUDE.md` — project rules, prohibitions, Git policy.
2. `README.md` — purpose, structure, commands.
3. `docs/changes/COPILOT-01/intent.md` — goal, scope, owner decisions Q1–Q12, assumptions A-1…A-4.
4. `docs/changes/COPILOT-01/spec.md` — requirements R-01…R-25, scenarios S-01…S-11, criteria AC-01…AC-14. The only source of requirements.
5. `docs/decisions/ADR-0001-stack.md` — stack and allowed dependencies.
6. `docs/changes/COPILOT-01/plan.md` — steps P-00…P-13, points H-0…H-5, checks, stop conditions.
7. `evals/README.md` — datasets and thresholds.
8. `docs/changes/COPILOT-01/handoff.md` — where the previous session stopped.
9. The actual `git status` and `git log --oneline -10`. If they differ from handoff.md, trust Git and record the discrepancy.

Briefly (5–10 lines) confirm: which document versions were read, the current step, the next H point.

## What to do
Implement plan.md step by step, starting from the first unfinished step in handoff.md, up to and including P-13.
The result is a working app `dist/InterviewCopilot.app` that the owner runs on their Mac and uses on a Google Meet call.
Plus `docs/changes/COPILOT-01/report.md` with evidence for AC-01…AC-14.

## How to work
- One P-xx step at a time. After a step:
  1. the step's checks from plan.md;
  2. review your diff (extra files, secrets, accidental formatting);
  3. update handoff.md;
  4. commit `P-xx: <what was done>`;
  5. `git push origin feat/copilot-01`.
- Do not ask the owner questions except at points H-0…H-5. At an H point:
  - stop;
  - give step-by-step instructions in Russian (what to click, where);
  - state what you will check after the answer;
  - wait for "done".
- Resolve ambiguity outside H points yourself, in this priority order:
  1. spec;
  2. `docs/design/menu-v2.webp`;
  3. Apple HIG;
  4. technical feasibility.

  Record the decision in handoff.md → "Executor decisions" with a reference to R-/AC-.
- For the Anthropic API, load the `claude-api` skill before writing code and follow it (raw HTTP, streaming, refusal, fallbacks).
  For Gemini and DeepSeek — the official documentation. Check model IDs by requesting the model list, not from memory.
- Only Gemini has a key (the owner enters it in Settings at H-2). Checks with DeepSeek and Anthropic without keys —
  mock tests and NOT RUN for live calls, noted in report.md.

## Boundaries
- Allowed:
  - write code, tests and scripts in the repository;
  - install dependencies from ADR-0001 item 9;
  - download models (with SHA256 verification);
  - commit and push to `feat/copilot-01`.
- Forbidden:
  - force-push, `reset --hard`, deleting branches, merging into `main`;
  - changing TCC, Keychain trust and system settings;
  - entering or printing keys; asking for keys in chat;
  - committing `profile/`, models, logs;
  - using paid services or keys other than the owner's Gemini key;
  - publishing anything.
- Do not weaken tests or eval thresholds to get a green result. Do not write "verified" without actually running the command.
- A new dependency outside ADR-0001 — only with an ADR entry and the note "requires owner confirmation at acceptance".

## When to stop and escalate
Conditions — plan.md, section "Stop conditions". When stopping:
- save the state in handoff.md (done, hypotheses, next step);
- commit and push the working state if it builds;
- describe the problem and options to the owner.

## Final
After P-13:
- report.md: a table AC → command/method → result (PASS / FAIL / NOT RUN) → evidence; unverified items and risks;
- updated README and ADR-0001;
- the branch is pushed.

Tell the owner:
- the path to the `.app` and how to run it;
- AC results;
- what remains unverified;
- what is needed from them for H-5.

Do not merge into `main` and do not create a PR without a separate command from the owner.
