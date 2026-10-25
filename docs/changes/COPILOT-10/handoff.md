# COPILOT-10 handoff

ID: COPILOT-10-handoff · Status: **stages 1–2 done (0.14.0, build 35) — H-1: the owner's live check** · Updated: 2026-10-25
Branch: `feat/copilot-10-theme-language` (from `feat/copilot-09-parakeet-parity` @ `e1b0bad`)
Links: [intent.md](intent.md), [spec.md](spec.md), [plan.md](plan.md)

## Done
- 2026-10-25: a brainstorm (Q1–Q4 in intent.md), the owner chose the recommended options.
- Stage 1 (P-01), commit `42a7f10` — theme:
  - `AppSettings.theme` / `interfaceLanguage` (the default is "as in the system", old settings are readable).
  - The `IC` tokens are dynamic (`Color.dynamic(light:dark:)`); white backgrounds and hex colors in windows were replaced with tokens.
  - "Settings → General" (the first tab): theme and language. `NSApp.appearance` — right away; the overlay is pinned to `.darkAqua`.
  - `dark-*` snapshots.
- Stage 2 (P-02), commit `a62efcd` — language:
  - `CopilotCore/Localization/L10n`: the key is the Russian string, English — `Resources/en.lproj/Localizable.strings`
    (786 strings); `L10n.t` / `L10n.f`; `Scope` (`@TaskLocal`) — the language within a task for parallel tests.
  - The app: `UILanguage` (an immediate change, retranslating the titles of open windows), `.localizedRoot()` on the root of each window
    (`\.locale` + a redraw), `L(…)`, overloads of `Text(String)`, `Button`, `Label`, `Toggle`, `Picker`, `Section`,
    `.help`, `.accessibilityLabel/Hint` — strings from variables are translated in the same place.
  - The status bar menu: all items — in Russian (it was partly in English) and in English in the English interface;
    the source, models, profile submenus; the usage line.
  - The core: provider, key, capture, model download, file and question bank errors, the pre-start check,
    type and mode names; dates and plural forms (1 question / 5 questions) — in the interface language.
  - The review after a call and "Ask AI" — in the interface language (`L10n.aiLanguageName`, the `[number]`… placeholders);
    hints on a call did not change.
  - Onboarding: the theme and language choice at the bottom of the screen, on all steps.
  - The AI interview and test call pages: script strings — through `T('…')`, markup — as whole fragments;
    the app's server serves the English page from the `en.json` next to it (`PageLocalization`).
  - `scripts/check-localization.sh` (+ `scripts/l10n-keys.py`, `scripts/l10n-ignore.txt`): keys — from the compiler
    (`-emit-localized-strings`), from `L(…)`/`L10n`, from window strings; a report on keys without a translation and format mismatches.
    Added to the full check (CLAUDE.md, README, ARCHITECTURE).
  - `LocalizationTests` (6): the table and formats, the menu and the usage line, core type names, the review language,
    pages without Russian in the English interface.
  - `en-*` snapshots (18) from the `.app` binary; selected ones — `docs/design/copilot-10/`.
  - Version 0.14.0 (build 35).
- A final touch (after the owner's sample of 2026-10-25): at the bottom of the main window's sidebar — a language menu (a globe, the name,
  an arrow) and a "Light / Dark / Auto" theme switch with icons; the `ICLanguageMenu`, `ICThemeSwitch` components
  (`DesignSystem.swift`), the same setting as in "Settings → General". Language names in the menu — in their own language.

## Executor decisions
- The key is the Russian string, not an identifier: the code reads as before, the Russian interface needs no table, a missing translation
  shows Russian text rather than a key. An empty `ru.lproj` is needed so that with an English system SwiftUI literals in the Russian
  interface are not taken from `en.lproj`.
- An immediate change — by redrawing the window root (`.id(language)`): screen state lives in models; the local state of
  views (a search field, expanded blocks) is reset on a language change. The settings tab is remembered (`lastTab`).
- Glued strings (`"…" + "…"`) in the settings and profile hints were merged into one: otherwise they cannot be translated.
- "Готово" in the pre-start check was replaced with "В порядке" (English "OK"): the same "Готово" meant both the
  "Done" button and the status.
- The overlay hint referred to the "Listening" menu — now "the Interview Copilot menu in the menu bar".
- The answer source labels (`generated`, `strong`, `screenshot`) — as they were, internal, not translated.
- The invisible main menu (Edit: Undo/Copy/…) was not translated: an agent app does not show it.
- Numbers in the Russian interface use a comma (`$0,03`, the threshold `0,62`): the format follows the interface locale.

## Checks (2026-10-25)
| Command | Result |
|---|---|
| `swift test` | PASS — 337 tests in 51 suites |
| `scripts/run-evals.sh` | PASS — bank, filter-text, memory, materials (5 PASS, 0 FAIL) |
| `scripts/secret-scan.sh` | PASS — 0 findings |
| `scripts/check-localization.sh` | PASS — 789 keys, 789 translations, 0 without a translation, 0 format mismatches |
| `scripts/build-app.sh` | PASS — `dist/InterviewCopilot.app` is signed |
| `--ui-snapshots` from the `.app` | 93 PNGs; Russian and English screens reviewed |

## Acceptance
| AC | Evidence | Status |
|---|---|---|
| AC-01 | `dark-*` snapshots, the `.darkAqua` overlay in `PanelController` | snapshots PASS; a live change — H-1 |
| AC-02 | `UILanguage.apply` from `settingsChanged`, `localizedRoot` on all windows | NOT RUN live — H-1 |
| AC-03 | `check-localization.sh`, the pages test, `en-*` snapshots | PASS (except user data and language names) |
| AC-04 | menu tests on Russian strings, the `workspace-today`, `panel-answer` snapshots | PASS |
| AC-05 | the `reviewForTheOwnerIsWrittenInTheInterfaceLanguage` test | PASS; a live review in English — H-1 |
| AC-06 | the full check above | PASS |

## Not verified
- A live change of the theme and language in the running app (H-1), the review and "Ask AI" in English with a real model.
- VoiceOver labels in English — only from the code.

## Next step
H-1: the owner launches 0.14.0, switches "Settings → General" (theme, language) with the windows and the overlay open,
opens the test call in English. Then — the decision on merging COPILOT-09/10 into `main`.
