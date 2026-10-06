# Передача COPILOT-01

Статус: in progress (P-01: код готов, ожидание H-1) · Обновлено: 2026-10-06 · Ветка: `feat/copilot-01` · Commit: см. `git log -1`
Цель и границы: [intent.md](intent.md), требования: [spec.md](spec.md), шаги: [plan.md](plan.md).

## Сделано
- Созданы документы SDLC (intent, spec, plan, ADR-0001, evals/README, CLAUDE.md, README, executor-prompt). Код не писался.

- 2026-10-06: владелец принял комплект v1 (статусы → accepted, запись в intent.md).

- 2026-10-06, P-00: обследование среды и baseline (ниже). Вывод: нужен Xcode → точка H-0.

### Baseline P-00
- Git до шага: ветка `feat/copilot-01`, рабочее дерево чистое, HEAD `a0a566f`, совпадает с `origin/feat/copilot-01`.
  Ветки: `main`, `feat/copilot-01`. Расхождений с handoff нет.
- `swift --version`: Apple Swift 6.0 (swiftlang-6.0.0.9.10), target arm64-apple-macosx15.0.
- `xcode-select -p`: `/Library/Developer/CommandLineTools`; Xcode в `/Applications` не установлен.
- Среда: macOS 15.7.2 (24G325), Apple M1, 8 ГБ; свободно 46 ГБ на томе данных. Есть Homebrew, gh, cmake, python3.
- Минимальный пакет (scratchpad), `swift test` на CLT:
  - XCTest: FAIL — `error: no such module 'XCTest'`;
  - Swift Testing: FAIL — `error: no such module 'Testing'`. Запускается только с ручными флагами
    `-F …/CommandLineTools/Library/Developer/Frameworks` + rpath, после чего падает на
    `XCTest not available … unable to lookup item 'PlatformPath'`. Это обходной путь, по Q10 не используется.
- XCFramework (GitHub Releases, проверено `gh api` 2026-10-06):
  - whisper.cpp: `whisper-b5454-xcframework.zip` (тег `b5454`, 65 816 082 байт,
    sha256 `e57f8c48933000acabc13bb913fbe82805d483a2deff692cc6738836bd92393b`). В последнем стабильном теге `v1.9.5` ассетов нет,
    XCFramework публикуется в сборочных тегах `bNNNN`.
  - llama.cpp: `llama-b11446-xcframework.zip` (тег `b11446`, 61 978 829 байт,
    sha256 `da7edb84bd4990680cd6bb475468cc3f78b28cc0062fabebeae40218d228966b`).
  - Оба подходят для `binaryTarget`; checksum SwiftPM будет посчитан `swift package compute-checksum` на P-04/P-06.
- Решение: Xcode нужен (тесты не работают на CLT) → H-0.

- 2026-10-06, H-0 пройдена: `xcode-select -p` → `/Applications/Xcode.app/Contents/Developer`, Xcode 26.3 (17C529),
  Swift 6.2.4. Минимальный пакет: `swift test` — XCTest 1/1 и Swift Testing 1/1 PASS.
- 2026-10-06, P-01 (код): `Package.swift` (цели InterviewCopilot, CopilotCore, copilot-eval, CopilotCoreTests; Yams 6.2.2),
  меню по R-15 (модель `CopilotCore/Menu/MenuLayout.swift` + `MenuBarController`), пустое окно настроек с вкладками R-18,
  иконка-попугай (рисуется кодом: шаблон для строки меню, цветная для .app), `Resources/Info.plist`,
  `scripts/build-app.sh`, `scripts/secret-scan.sh`, заглушка `copilot-eval`.

## Следующий шаг
H-1: владелец создаёт сертификат «InterviewCopilot Dev». После «готово»: `security find-identity -p codesigning`,
`scripts/build-app.sh`, `codesign -dv dist/InterviewCopilot.app`, запуск `.app`; затем P-02.

## Проверки
| Шаг | Команда | Commit | Результат |
|---|---|---|---|
| P-00 | `swift test` (минимальный пакет, CLT) | — | FAIL: нет модулей XCTest/Testing без Xcode → H-0 |
| P-00 | `swift build` / `scripts/secret-scan.sh` | — | NOT RUN (кода и скрипта ещё нет) |
| H-0 | `swift test` (минимальный пакет, Xcode 26.3) | — | PASS: XCTest 1/1, Swift Testing 1/1 |
| P-01 | `swift build` | P-01 | PASS |
| P-01 | `swift test` | P-01 | PASS: 4 теста (MenuLayoutTests) |
| P-01 | `scripts/secret-scan.sh` (дерево + индекс + история) | P-01 | PASS: «0 findings»; самопроверка на фейковых ключах/email/телефоне — 5 находок из 5 |
| P-01 | `scripts/build-app.sh` | P-01 | FAIL ожидаемо: нет сертификата → понятная ошибка; повтор после H-1 |
| P-01 | Запуск, иконка и меню видны (скриншот) | P-01 | Запуск debug-бинаря: процесс стартует без ошибок. Скриншот NOT RUN: у процесса исполнителя нет разрешения «Запись экрана» (`screencapture` даёт только обои), TCC не трогаю. Скриншот меню — на H-3/P-11 |

## Решения исполнителя
_(исполнитель дописывает: дата, шаг, решение, причина, ссылка на R-/AC-)_

- 2026-10-06, P-00: тесты пишутся на XCTest и/или Swift Testing после установки Xcode; флаги-обходы для CLT не используются (Q10, AC-14).
- 2026-10-06, P-01: структура меню вынесена в `CopilotCore` (`MenuLayout`) и покрыта тестами — проверяемая часть AC-11; AppKit только отрисовывает. Иконки пунктов — SF Symbols, близкие к картинке (HIG).
- 2026-10-06, P-01: иконка-попугай рисуется кодом (`ParrotIcon`), .icns собирается `iconutil` в build-app.sh — без бинарных ассетов в Git (R-15).
- 2026-10-06, P-01: в меню первой строкой для паузы — «Paused — <app>» и пункт «Resume listening» (R-15 говорит только о цвете точки; так понятнее, HIG).
- 2026-10-06, P-01: `secret-scan.sh` не проверяет email/телефоны в `profile.example/` и `evals/` (синтетика, AC-06); разрешены адреса `example.*`, `users.noreply.github.com`, `anthropic.com`.
- 2026-10-06, P-00: whisper.cpp и llama.cpp берутся из сборочных тегов `bNNNN` (там лежат XCFramework), версия фиксируется URL + checksum (ADR-0001 п. 5, 9).

## Открытые вопросы
Блокеров нет. Неблокирующие вопросы — intent.md, раздел «Открытые вопросы».

## Права
- Разрешено:
  - код, тесты и скрипты в репозитории;
  - коммиты и `git push` в `feat/copilot-01`;
  - загрузка моделей и зависимостей из ADR-0001;
  - живые запросы к Gemini с ключом владельца.
- Не разрешено:
  - force-push, `reset --hard`, удаление веток, merge в `main`;
  - изменение TCC и Keychain trust;
  - платные сервисы и зависимости вне ADR-0001;
  - публикация.

## Риски и откат
Точка возврата: начальный коммит `main`. Откат шага — `git revert` его коммита.
