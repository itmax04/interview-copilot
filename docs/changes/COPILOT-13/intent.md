# COPILOT-13 — technical audit and fixes

## Problem
The owner asked for a full technical audit and code review of the project: find and fix bugs and technical problems,
and improve performance, stability, reliability and code quality.

## Scope of this task
- Read the code module by module, starting with the parts where a defect costs the most during a live call:
  audio capture, speech recognition, turn detection, the provider chain, storage, secrets, the loopback server.
- Fix what is found, with a test for every fix that can be tested without hardware.
- Keep behaviour and tuned thresholds as they are unless a defect is proven.

## Owner decisions
- Work goes to branch `feat/copilot-13-audit-fixes` (created from `main` = COPILOT-12).
- No push without the owner's permission.

## Out of scope
- New features, redesign, prompt changes, dependency updates.
