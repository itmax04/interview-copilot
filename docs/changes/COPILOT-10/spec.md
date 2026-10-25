# COPILOT-10: Spec

ID: COPILOT-10-spec · Status: **accepted** · Version: 1 · Date: 2026-10-25
Links: [intent.md](intent.md), [plan.md](plan.md)

## Requirements
| ID | Requirement |
|---|---|
| R-01 | `AppSettings.theme` (`system` / `light` / `dark`) and `interfaceLanguage` (`system` / `ru` / `en`); old settings are read with the defaults (`system`). The system language: ru/uk/be → Russian, otherwise English |
| R-02 | Window colors are dynamic `IC` tokens (a light and a dark variant); there are no hard-coded white backgrounds and hex colors in windows. The theme is applied with `NSApp.appearance` right away; the overlay is pinned dark (`.darkAqua`) |
| R-03 | "Settings → General" (the first tab): theme and language; the same switches — at the bottom of onboarding |
| R-04 | A string key is the Russian text from the code; English — `Resources/en.lproj/Localizable.strings`. SwiftUI literals — by `\.locale`, strings from variables — via `Text(String)` overloads and others, strings in code — `L(…)` / `L10n.t/f` |
| R-05 | A language change is immediate: the root of each window is redrawn (`localizedRoot`), window titles are translated again, the status bar menu is rebuilt when opened |
| R-06 | The status bar menu, errors, statuses, the pre-start check, dates and plural forms — in the interface language |
| R-07 | The review after a call and "Ask AI" — in the interface language (placeholders "[цифра]" → "[number]"); hints on a call do not change |
| R-08 | The AI interview and test call pages — in the interface language (an `en.json` dictionary next to the page) |
| R-09 | `scripts/check-localization.sh` — every interface string has a translation and the formats match; part of the full check |

## Acceptance criteria
| ID | Criterion | How to check |
|---|---|---|
| AC-01 | The theme changes right away in all windows; the overlay is dark in any theme | `dark-*` snapshots, the live check H-1 |
| AC-02 | The language changes right away, without a restart; the settings tab is not reset | the live check H-1 |
| AC-03 | The English interface has no Russian interface strings (except language names and user data) | `scripts/check-localization.sh`, `en-*` snapshots, the pages test |
| AC-04 | The Russian interface did not change (except the fixed English menu items) | `swift test`, snapshots |
| AC-05 | The review and "Ask AI" — in the interface language | the `reviewForTheOwnerIsWrittenInTheInterfaceLanguage` test |
| AC-06 | The full CLAUDE.md check passes | command output in the handoff |
