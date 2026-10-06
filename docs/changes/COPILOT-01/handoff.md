# Передача COPILOT-01

Статус: in progress (P-00 сделан, ожидание H-0) · Обновлено: 2026-10-06 · Ветка: `feat/copilot-01` · Commit: см. `git log -1`
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

## Следующий шаг
H-0: владелец ставит Xcode. После «готово» исполнитель проверяет `xcode-select -p`, `xcodebuild -version`,
повторяет `swift test` на минимальном пакете (XCTest + Swift Testing) и переходит к P-01 (там же H-1).

## Проверки
| Шаг | Команда | Commit | Результат |
|---|---|---|---|
| P-00 | `swift test` (минимальный пакет, CLT) | — | FAIL: нет модулей XCTest/Testing без Xcode → H-0 |
| P-00 | `swift build` / `scripts/secret-scan.sh` | — | NOT RUN (кода и скрипта ещё нет) |

## Решения исполнителя
_(исполнитель дописывает: дата, шаг, решение, причина, ссылка на R-/AC-)_

- 2026-10-06, P-00: тесты пишутся на XCTest и/или Swift Testing после установки Xcode; флаги-обходы для CLT не используются (Q10, AC-14).
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
