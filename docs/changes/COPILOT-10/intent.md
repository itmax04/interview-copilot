# COPILOT-10: Intent — light and dark theme, the interface in Russian and English

ID: COPILOT-10-intent · Status: **accepted** (2026-10-25: the owner chose the brainstorm options) · Version: 1 · Date: 2026-10-25 · Owner: itmax04
Links: [spec.md](spec.md), [plan.md](plan.md)

## Problem
The app windows are always light: in the evening and in the macOS dark theme they are glaring and stand out from the system. The interface is only
in Russian (and the status bar menu is partly in English), so showing the app to an English-speaking
user or using it in an English-speaking environment is inconvenient.

## Desired outcome
The owner chooses the window theme (as in the system, light, dark) and the interface language (as in the system, Russian, English).
A change applies right away, without a restart. The call overlay stays dark. AI texts for the owner (the review after
a call, "Ask AI") are in the interface language; hints on a call are still in the interviewer's language.

## Owner decisions (brainstorm 2026-10-25)
| # | Question | Decision |
|---|---|---|
| Q1 | Theme options | "As in the system / Light / Dark"; the default — as in the system. Windows follow the theme, the call overlay is always dark |
| Q2 | When the language applies | Right away, without a restart |
| Q3 | The language of AI texts for the owner | The review and "Ask AI" — in the interface language; hints on a call — in the interviewer's language |
| Q4 | Defaults and where to choose | The system language and the system theme; the choice — in onboarding and in "Settings → General" |

## Out of scope
Other interface languages (including Ukrainian), translating content (the résumé, questions, answers), English voices and phrases
of the test call (it already has three languages).
