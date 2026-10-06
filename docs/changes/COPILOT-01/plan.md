# COPILOT-01: Технический план v1

ID: COPILOT-01-plan · Статус: **proposed** · Версия: 1 · Дата: 2026-10-06 · Владелец: itmax04
Предусловие: spec.md v1 и ADR-0001 приняты владельцем. Требования здесь не повторяются — только ссылки на R-/AC-номера из [spec.md](spec.md).
Исполнитель: Claude Code, `claude-opus-5-5`, effort high (Q8).

## Предусловия и состояние
- Репозиторий: `~/Desktop/1/interview-copilot`, приватный `itmax04/interview-copilot`.
- Ветки: `main` содержит только начальный коммит; вся работа идёт в `feat/copilot-01`.
- Baseline: на момент создания плана кода нет. Фактические SHA и результаты проверок исполнитель записывает в handoff.md на P-00.
- Все команды ниже **новые**: их создают шаги этого плана. До создания команды её результат — NOT RUN.

## Точки ручных действий (H)
Исполнитель доходит до точки, ставит паузу, даёт владельцу пошаговую инструкцию и ждёт ответа «готово». Других вопросов не задаёт (Q9).

| H | Когда | Действие владельца |
|---|---|---|
| H-0 | P-00, если `swift test` не работает без Xcode, или если для whisper/llama XCFramework нужен Xcode | Установить Xcode из App Store, один раз запустить, `sudo xcode-select -s /Applications/Xcode.app` |
| H-1 | P-01 | Создать сертификат подписи кода «InterviewCopilot Dev» в «Связке ключей → Ассистент сертификации» (самоподписанный, тип «Подписание кода») |
| H-2 | P-02 | Ввести ключ Gemini в Settings → Keys (не в чат) и нажать «Проверить» |
| H-3 | P-03 | Сначала запустить приложение без разрешений (проверка AC-13), затем выдать «Запись экрана и системного звука» и «Микрофон» |
| H-4 | P-12 | Тестовый созвон: Meet в Chrome на Mac + телефон, прочитать `evals/live-script.md` (≈10 мин); оценить AC-10 и AC-11 |
| H-5 | P-13 | Приёмка результата по report.md |

## Файлы и порядок
Каждый шаг: реализация → проверки шага → обновление handoff.md → коммит `P-xx: <кратко>` → `git push`.

**P-00. Обследование и baseline**
- Записать в handoff.md: `git status`, `swift --version`, `xcode-select -p`, свободное место.
- Минимальный пакет во временной папке scratchpad: проверить `swift test` (Swift Testing и XCTest) на CLT.
- Проверить, доступны ли XCFramework в релизах whisper.cpp и llama.cpp (URL, версия, SHA).
- Решение «нужен ли Xcode» записать в handoff. Нужен → H-0.

**P-01. Каркас приложения** — R-15 (статичное меню), R-18 (пустое окно настроек)
- `Package.swift`: цели `InterviewCopilot`, `CopilotCore`, `copilot-eval`, `CopilotCoreTests`; зависимость Yams.
- `Sources/InterviewCopilot/App.swift`, `MenuBarController.swift`, `SettingsWindow.swift`.
- `Resources/Info.plist`: `LSUIElement`, `NSMicrophoneUsageDescription`, bundle ID из ADR-0001; иконка-шаблон попугая.
- `scripts/build-app.sh`: сборка release, упаковка в `dist/InterviewCopilot.app`, подпись «InterviewCopilot Dev» (H-1).
  Без сертификата скрипт падает с понятной ошибкой.
- `scripts/secret-scan.sh` (AC-06): паттерны ключей Gemini (`AIza…`), Anthropic (`sk-ant-…`), DeepSeek (`sk-…`),
  email и телефоны вне `profile.example/`, файлы из `.gitignore`, попавшие в индекс. Запускать перед каждым push, начиная с этого шага.
- Проверки: `swift build`, `scripts/build-app.sh`, `scripts/secret-scan.sh`, запуск — иконка и меню видны (скриншот).

**P-02. Настройки и ключи** — R-18, R-23
- `CopilotCore/Settings/SettingsStore.swift` (UserDefaults + JSON), `CopilotCore/Secrets/KeychainStore.swift`.
- `Sources/InterviewCopilot/Settings/*View.swift` — вкладки Keys, Models, Audio, Bank, Privacy, Panel, Hotkeys, Budget.
- «Проверить ключ» — запрос списка моделей провайдера. Ответ: OK или текст ошибки, без вывода ключа.
- Тесты: `KeychainStoreTests` (отдельный тестовый service и очистка после теста), `SettingsStoreTests`.
- H-2.

**P-03. Захват звука и разрешения** — R-01, R-02, R-04, S-09 (часть «разрешения»), AC-13
- `CopilotCore/Audio/SystemAudioCapture.swift` (SCStream, фильтр по приложению, 16 кГц моно Float32).
- `CopilotCore/Audio/MicActivityDetector.swift` (AVAudioEngine + энергетический VAD).
- `CopilotCore/Audio/AudioSourceResolver.swift` (Auto: zoom.us → Chrome → Telegram).
- `Sources/InterviewCopilot/Onboarding/PermissionsView.swift`.
- Тесты: `AudioSourceResolverTests`; захват — вручную: уровень сигнала в debug-панели при воспроизведении видео в Chrome.
- H-3.

**P-04. Распознавание** — R-03, R-22
- `scripts/fetch-models.sh` + `models.sha256`: whisper `large-v3-turbo-q5_0` и `small-q5_1`.
- `CopilotCore/STT/WhisperEngine.swift`: обёртка C API; потоковое окно; VAD-сегментация; частичный и итоговый текст; язык.
- `Package.swift`: `binaryTarget` whisper.cpp (URL + checksum).
- Замер: задержка конца фразы → текст и память на записи из `evals/audio/` (синтетика, озвучка через `say`:
  uk — голос Lesya, ru — Milena, en — Samantha). Нужного голоса нет → записать в handoff, заменить доступным.
- Решение turbo/small — по AC-01 и AC-05, записать в ADR-0001.
- Тесты: `WhisperEngineTests` на коротком файле из `evals/audio/` (проверка «текст не пуст, язык верный»).

**P-05. Ходы и панель (базовая)** — R-05, R-16 (шапка, Interviewer, состояния idle/listening/paused), S-07, S-08
- `CopilotCore/Turns/TurnDetector.swift` (порог T, ≥ 3 слов, речь владельца, принудительный ход).
- `Sources/InterviewCopilot/Panel/PanelController.swift` (NSPanel nonactivating), `PanelView.swift`, `TranscriptView.swift`.
- `CopilotCore/Hotkeys/HotkeyCenter.swift` (Carbon), ⌃⌥P / ⌃⌥H / ⌃⌥↩ — R-17.
- Eval `turn` (evals/README.md) и `copilot-eval turn`.
- Тесты: `TurnDetectorTests`.

**P-06. База вопросов** — R-06, R-07, S-10, AC-04
- `profile.example/`: `profile.yaml`, `resume.md`, `job.md`, `stories.md` (вымышленный кандидат),
  `questions.yaml` (≥ 15 карточек uk/ru/en, часть с тегом STAR).
- `CopilotCore/Bank/QuestionBank.swift` (Yams, валидация, наблюдение за файлом), `EmbeddingEngine.swift` (llama.cpp),
  `BankMatcher.swift`, кэш эмбеддингов.
- Eval `bank`: `evals/bank/cases.jsonl`. Кандидаты моделей — ADR-0001 п. 6; выбор и порог записать в ADR-0001 и evals/README.
- Тесты: `QuestionBankTests` (валидация, ошибки разбора), `BankMatcherTests` (детерминированный stub-эмбеддер).

**P-07. Провайдеры и маршрутизатор** — R-09…R-13, AC-07, AC-08
- Перед кодом Anthropic прочитать skill `claude-api` (curl/examples.md, streaming, refusal/fallbacks);
  для Gemini и DeepSeek — их официальную документацию по стримингу. ID моделей проверить списком моделей.
- `CopilotCore/LLM/LLMProvider.swift` (протокол), `SSEClient.swift`, `GeminiProvider.swift`, `DeepSeekProvider.swift`,
  `AnthropicProvider.swift`, `MockProvider.swift`.
- `CopilotCore/LLM/ProviderChain.swift` (триггеры перехода, таймаут первого токена 4 с, отмена).
- `CopilotCore/LLM/PromptBuilder.swift` (R-11), `CopilotCore/Privacy/PIIFilter.swift` (R-12).
- `CopilotCore/Answer/AnswerRouter.swift` (режимы R-08).
- Тесты: `ProviderChainTests`, `AnswerRouterTests`, `PromptBuilderTests`, `PIIFilterTests`, `SSEClientTests`
  (фикстуры потоков в `Tests/Fixtures/`).
- Живой smoke только с Gemini (ключ H-2); DeepSeek и Anthropic без ключей — NOT RUN с пометкой.

**P-08. Карточка ответа и режимы в UI** — R-08, R-16 (answer / no-match / thinking / error), R-15 (Mode, Models, Language), S-01…S-05, S-11
- `Sources/InterviewCopilot/Panel/AnswerCardView.swift` (Markdown, чипы STAR, Copy, ↑ Claude), состояния панели.
- Подменю меню подключить к SettingsStore.

**P-09. Скриншот** — R-14, S-06
- `CopilotCore/Capture/ScreenshotService.swift` (SCScreenshotManager, исключение панели, сжатие), ⌃⌥S, ⌃⌥C.
- Живая проверка — на Gemini (без ключа Anthropic) с картинкой задачи `evals/fixtures/two-sum.png`
  (создать: скриншот синтетического условия задачи, открытого в Chrome).

**P-10. История, расход, бюджет** — R-18 (Budget), R-19, R-20, строка статуса R-15
- `CopilotCore/Storage/SessionStore.swift`, `CopilotCore/Usage/UsageMeter.swift`, `Resources/pricing.json`.
- `Sources/InterviewCopilot/History/SessionHistoryWindow.swift`.
- Тесты: `SessionStoreTests` (сохранение, удаление, срок — AC-12), `UsageMeterTests` (цены, пиковые часы DeepSeek, лимит).

**P-11. Первый запуск, полировка, ресурсы** — S-09 целиком, R-16 (доступность, Reduce Motion), R-24, R-25, AC-09, AC-11
- Мастер: разрешения → ключ → модели.
- Сверка меню с `docs/design/menu-v2.webp`: скриншот рядом с картинкой → `docs/changes/COPILOT-01/evidence/`.
- Замер памяти (`footprint`), профилирование при превышении.
- `scripts/metrics.py`; `scripts/run-evals.sh` объединяет `copilot-eval bank` и `copilot-eval turn`
  (при необходимости создаётся раньше, на P-05/P-06).

**P-12. Тестовый созвон** — AC-01…AC-03, AC-05, AC-10
- Подготовить `evals/live-script.md` (15 вопросов: 5 uk, 5 ru, 5 en; часть из базы в перефразировке, часть вне базы).
- H-4. После созвона: `scripts/metrics.py` по логам → таблица медиан в report.md.

**P-13. Независимая проверка и отчёт**
- Ревью свежим контекстом: новая сессия Claude Code (Opus 5.5, high) или `/code-review high` по ветке `feat/copilot-01`
  против spec.md и CLAUDE.md. Находки P0/P1 исправить, остальные перечислить.
- `docs/changes/COPILOT-01/report.md`: трассировка AC → свидетельство → PASS/FAIL/NOT RUN, непроверенное, известные ограничения.
- Обновить README (фактические команды), ADR-0001 (итоговые решения). H-5.

## Зависимости
Только из ADR-0001 п. 9. Любые другие — запись в ADR-0001 + пометка в handoff («требует подтверждения владельца при приёмке»).

## Проверки
| Команда (новая) | Шаги | Ожидаемое свидетельство |
|---|---|---|
| `swift build` | все | Сборка без ошибок |
| `swift test` | P-02+ | Все тесты зелёные; число тестов в handoff |
| `scripts/build-app.sh` | P-01+ | `dist/InterviewCopilot.app`; `codesign -dv` показывает «InterviewCopilot Dev» |
| `scripts/fetch-models.sh` | P-04+ | Файлы моделей, SHA256 совпадают |
| `scripts/run-evals.sh bank` | P-06+ | Точность ≥ 85%, ложные совпадения ≤ 10% (AC-04) |
| `scripts/run-evals.sh turn` | P-05+ | Метрики из evals/README |
| `scripts/secret-scan.sh` | P-01+, перед каждым push | «0 findings» (AC-06) |
| `scripts/metrics.py <log>` | P-12 | Медианы AC-01…AC-03 |
| `footprint -p $(pgrep InterviewCopilot)` | P-11, P-12 | Пик ≤ 1,5 ГБ (AC-05) |

Тест нельзя ослаблять ради зелёного результата. Если тест требует сетевого ключа, которого нет, — помечать NOT RUN, а не удалять тест.

## Риски и откат
| Риск | Признак | Действие |
|---|---|---|
| Не хватает памяти или whisper turbo медленный | AC-01/AC-05 не выполняются | Модель small; затем уменьшить окно; если и это не помогает — стоп и эскалация владельцу |
| Эмбеддинги < 85% | eval bank | Второй кандидат (ADR-0001); затем гибрид с лексическим поиском (BM25) — с записью в ADR |
| Конфликт символов whisper.cpp и llama.cpp | Ошибки линковки | Эмбеддинги через CoreML или другой кандидат; запись в ADR |
| Лимиты Gemini Free | 429 на тестах | Пауза и повтор; на созвоне сработает цепочка; в отчёте отметить |
| Разрешения macOS сбрасываются | Повторные запросы TCC | Проверить подпись (H-1); не трогать TCC самому |

Откат: каждый шаг — отдельный коммит в `feat/copilot-01`; при провале шага — `git revert` своего коммита.
`main` не меняется. Деструктивные git-команды запрещены (CLAUDE.md).

## Условия остановки (эскалация владельцу)
- Нужна зависимость, сервис или платный ключ вне ADR-0001 и intent.
- Требование spec невыполнимо без изменения границ (например, AC-05 недостижим ни на одной модели).
- Найден секрет или личные данные в истории Git.
- Три попытки подряд по одной проблеме без прогресса: сохранить состояние в handoff, описать гипотезы.
- Любое действие из списка «Запрещено» в CLAUDE.md.

## Готово, когда
AC-01…AC-14 имеют свидетельство в report.md (PASS, либо NOT RUN с причиной, принятой владельцем),
ревью P-13 без открытых P0/P1, ветка `feat/copilot-01` запушена, handoff.md актуален, владелец подтвердил H-5.
