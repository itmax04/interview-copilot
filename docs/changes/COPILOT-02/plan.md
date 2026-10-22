# COPILOT-02: Технический план

ID: COPILOT-02-plan · Статус: **draft** · Версия: 1 · Дата: 2026-10-22 · Владелец: itmax04
Предусловие: [intent.md](intent.md) и [spec.md](spec.md) приняты владельцем при H-0. Требования здесь не повторяются —
только ссылки на R-/AC-номера из spec.md (прошлая задача — с префиксом «01/»).
Исполнитель: Claude Code, `claude-opus-5-5`, effort high (Q5). Промпт — [executor-prompt.md](executor-prompt.md).

## Предусловия и состояние
- Репозиторий: `~/Desktop/1/interview-copilot`, приватный `itmax04/interview-copilot`.
- База: ветка `feat/copilot-01` @ `3b690fc` (v0.1.2 build 3), в `main` не слита.
  Перед работой сверить локальную копию с `origin/feat/copilot-01`: на 2026-10-22 локальная копия владельца отставала
  на 2 коммита (`7acd4cd`, `3b690fc`) — обновить только fast-forward, без перезаписи изменений владельца.
- Рабочая ветка: `feat/copilot-02` от `feat/copilot-01` (Q4). CLAUDE.md проекта говорит работать в `feat/copilot-01` —
  на P-00 исправить его на текущую задачу (отдельный коммит).
- Модели: Parakeet v3 (`scripts/fetch-parakeet.py`), Whisper turbo/medium (`scripts/fetch-models.sh`), bge-m3 —
  установлены у владельца в `~/Library/Application Support/InterviewCopilot/models/`. Опыты с порчей установки (AC-06)
  — только на копии через `INTERVIEWCOPILOT_MODELS_DIR`.
- Команды `swift build`, `swift test`, `scripts/run-evals.sh`, `scripts/secret-scan.sh`, `scripts/build-app.sh`,
  `scripts/eval-local-stt.py`, `scripts/metrics.py`, `scripts/footprint-monitor.sh`, `copilot-eval stt|stt-parakeet|stt-stream`
  уже существуют. Новые: скрипт фикстур (P-01), eval `vocab` (P-03).

## Точки владельца (H)
Исполнитель доходит до точки, останавливается, даёт пошаговую инструкцию на русском и ждёт «готово».
Других вопросов не задаёт.

| H | Когда | Действие владельца |
|---|---|---|
| H-0 | До P-00 | Принять intent/spec/plan (статусы → accepted), ответить на Q1–Q6 в intent.md |
| H-1 | P-01, только если пороги AC-02/AC-04/AC-05 по baseline недостижимы или тривиальны | Выбрать предложенный исполнителем порог |
| H-2 | P-10 (Q6) | Живая проверка: Meet в Chrome на Mac + телефон, 3 длинных вопроса и 5 вопросов с терминами по `evals/live-script-02.md`; оценить «понятно / непонятно» по каждому |
| H-3 | P-11 | Приёмка по report.md COPILOT-02 |

## Шаги
Каждый шаг: реализация → проверки шага → обновление handoff.md → коммит `P-xx: <кратко>` → `git push origin feat/copilot-02`.
Порядок — по приоритету ревью: стыки → словарь → шум и надёжность → язык → усиление и тесты.

**P-00. Baseline**
- Записать в handoff.md: `git status`, `git log -1`, версия Xcode/Swift, установленные модели (имена и размеры, без путей владельца в Git).
- `swift build`, `swift test` (ожидается 157 PASS), `scripts/run-evals.sh`, `scripts/secret-scan.sh`, `scripts/build-app.sh`.
- Тестовый звонок v0.1.2 (15 фраз, Parakeet, Auto) — baseline текущей сборки рядом с цифрами report.md v0.1.2.
- Обновить CLAUDE.md проекта: текущая задача COPILOT-02, ветка `feat/copilot-02`.

**P-01. Длинные фразы и замер стыков** — R-01, AC-01, AC-02
- `scripts/make-test-call-fixtures.sh`: генерация всех фикстур тестового звонка (существующих 15 и новых длинных)
  голосами `say` + варианты «тихий» и «сжатый» через `afconvert`; результат в `evals/audio/test-call/`.
  Перегенерация существующих 15 не должна менять их эталонный текст; если длительности расходятся с текущими файлами —
  старые файлы не заменять, расхождение записать в handoff.
- ≥ 9 длинных фраз (3 на язык), эталоны в `Resources/TestCall/clips.json` и в манифесте `evals/stt/long.json`
  (формат `scripts/eval-local-stt.py`: id/language/condition/path/expected).
- Прогон напрямую: `scripts/eval-local-stt.py evals/stt/long.json …` (профили parakeet-auto и turbo-full для сравнения).
- Прогон через тестовый звонок; записать `audio_ms` каждого итога (проверка A-5: доходят ли фразы > 15 с до движка).
- Разбор ошибок по месту: на стыке (12–18 с от начала) или нет.
- Если пороги AC-02 по baseline недостижимы или тривиальны — H-1.

**P-02. Защита стыков** — R-02 (только если P-01 нашёл ошибки на стыках)
- Вариант 1: `ASRConfig(dualDecodeArbitration: true)` в `ParakeetEngine.load`.
- Вариант 2: нарезка итога ≤ 15 с по минимуму энергии в окне 10–15 с, распознавание кусков, объединение.
- Сравнить по AC-02 и AC-09, выбрать, записать в ADR-0001. Тесты: нарезка (юнит, без модели), длинный файл (R-12).
- Если стыки чистые — шаг пропускается с записью в handoff и ADR-0001.

**P-03. Словарь терминов и поправка итога** — R-03, R-04, AC-04
- `CopilotCore/Vocabulary/TermDictionary.swift` (сбор из `questions.yaml` + `vocabulary.yaml`, наблюдение за файлами),
  `TermCorrector.swift` (сопоставление, стоп-лист, пороги).
- Подключение: после итога `StreamingTranscriber` → `TermCorrector` → определение хода и поиск (оба движка).
- Settings → Audio: «Исправлять термины по базе» (по умолчанию вкл.); пункт меню ошибок разбора — как 01/S-10.
- `profile.example/vocabulary.yaml`; набор `evals/vocab/`: ≥ 15 фраз с терминами (фикстуры через скрипт P-01) и
  ≥ 30 контрольных фраз без терминов (текстовые, достаточно прогнать поправку по тексту).
- Eval `vocab` в `copilot-eval` и `scripts/run-evals.sh vocab`; порог сходства — в evals/README.
- Тесты: `TermDictionaryTests`, `TermCorrectorTests` (S-02, S-03, кириллица ↔ латиница, числа не трогаются).

**P-04. Исследование CTC-усиления** — R-05 (только если Q3 = да; ограничение по времени — один шаг)
- Манифест модели Parakeet CTC 110M с SHA256 из официального репозитория FluidInference; загрузка в копию папки моделей.
- Замер на наборе `vocab`: кириллические и английские термины отдельно; память и задержка.
- Запись в ADR-0001: принять / отклонить. Код за выключенным флагом или не попадает в ветку, если отклонено.

**P-05. Фильтр шума** — R-06, AC-05
- Набор шума (≥ 20 синтетических записей: клавиатура, музыка без слов, шорох, щелчки) — генерация скриптом
  (`sox`/`afconvert` или синтез в Swift/Python; новые инструменты — только если уже установлены, иначе спросить в H-1).
- Порог C по набору шума и коротким репликам; запись в evals/README.
- Реализация в `StreamingTranscriber.runFinal` (или в адаптере через `noSpeechProbability`, выведенную из `confidence`
  и числа слов — выбрать и обосновать в handoff). Тесты на фейковом распознавателе.

**P-06. Проверка установки и переход на Whisper** — R-07, AC-06
- `ParakeetEngine.isInstalled(at:manifest:)` по `parakeet-models.json` (наличие и размер).
- `ListeningController.loadRecognizer`: при ошибке Parakeet — Whisper, статус S-05; настройка не меняется.
- Тесты: манифест (полный / нет файла / другой размер), выбор движка на фейковых загрузчиках.
- Ручная проверка на копии папки моделей (`INTERVIEWCOPILOT_MODELS_DIR`), не на оригинале владельца.

**P-07. Язык: фильтр, подписи, sticky** — R-08, R-09, R-10, AC-07, AC-08
- `ParakeetEngine.transcribe`: `language: .english` только при явном English.
- Подписи R-09 в меню Language и Settings → Audio; уточнить test-plan.md и report.md COPILOT-01 ссылкой на COPILOT-02.
- `StreamingTranscriber`: sticky-логика только при `!recognizer.nativeMultilingual`.
- Тесты: выбор фильтра, sticky выключен для nativeMultilingual, прежние `StreamingTranscriberTests` без изменения ожиданий.
- Скриншоты → `docs/changes/COPILOT-02/evidence/`.

**P-08. Усиление тихого звука** — R-11
- Прогон `eval-local-stt.py` по тихим и сжатым фразам с усилением и без (временный параметр движка / переменная окружения
  только для eval). Решение и цифры — в ADR-0001.

**P-09. Тесты адаптера** — R-12
- `ParakeetEngineTests` (пропуск без модели). Можно начать раньше, на P-01, если это ускоряет работу.

**P-10. Итоговые замеры и живая проверка** — AC-03, AC-07, AC-09, AC-10
- Полный тестовый звонок (15 + длинные + термины), `scripts/metrics.py`, `scripts/footprint-monitor.sh 10`.
- Подготовить `evals/live-script-02.md` (3 длинных вопроса, 5 вопросов с терминами, по языкам).
- H-2.

**P-11. Ревью и отчёт** — AC-11, AC-12
- Независимое ревью свежим контекстом (`/code-review high` по `feat/copilot-02` против spec.md и CLAUDE.md).
  Находки P0/P1 исправить, остальные перечислить.
- Чистый клон: `swift build`, `swift test`, `scripts/build-app.sh`.
- `docs/changes/COPILOT-02/report.md`: AC → способ → PASS / FAIL / NOT RUN → свидетельство; ADR-0001 и evals/README
  обновлены. H-3.

## Зависимости
Новых пакетов SwiftPM не требуется: FluidAudio 0.17.7 уже содержит `ASRConfig.dualDecodeArbitration`,
`TokenLanguageFilter`, `CustomVocabulary`. Новая модель возможна только на P-04 (Parakeet CTC 110M) — при Q3 = да,
с записью в ADR-0001. Обновление FluidAudio — вне задачи.

## Проверки
| Команда | Шаги | Ожидаемое свидетельство |
|---|---|---|
| `swift build` | все | Сборка без ошибок |
| `swift test` | все | Все тесты зелёные; число тестов ≥ 157 + новые, в handoff |
| `scripts/make-test-call-fixtures.sh` (новая) | P-01+ | Файлы и длительности (AC-01) |
| `scripts/eval-local-stt.py evals/stt/long.json <out>` | P-01, P-02, P-08 | WER по языкам и вариантам (AC-02) |
| `scripts/run-evals.sh` (bank, turn, vocab) | P-03+ | bank/turn — прежние пороги; vocab — AC-04 |
| Тестовый звонок (меню «Тестовый звонок…») | P-00, P-01, P-07, P-10 | JSON-отчёт страницы (AC-03, AC-05, AC-07) |
| `scripts/metrics.py` | P-10 | Медианы задержки итога (AC-09) |
| `scripts/footprint-monitor.sh 10` | P-10 | Пик ≤ 1,5 ГБ (AC-10) |
| `scripts/secret-scan.sh` | перед каждым push | «0 findings» |
| `scripts/build-app.sh` + `codesign --verify --strict` | P-00, P-07, P-10, P-11 | `dist/InterviewCopilot.app` подписан |

Тест и пороги нельзя ослаблять ради зелёного результата. Что не запускалось — NOT RUN с причиной.

## Риски и откат
| Риск | Признак | Действие |
|---|---|---|
| VAD режет синтетические длинные фразы на паузах между предложениями | `audio_ms` итогов < 15 с на тестовом звонке | Прямой прогон в движок остаётся мерилом AC-02; факт записать (A-5) |
| Поправки портят обычные слова | Ложные поправки на контрольном наборе | Ужесточить порог, расширить стоп-лист; при невозможности 0 ложных — только явные варианты из `vocabulary.yaml` |
| `dualDecodeArbitration` удваивает время на длинных фразах | AC-09 > 1,5 с | Вариант 2 (своя нарезка) или защита только для фраз > 15 с |
| CTC-кодировщик не работает на кириллице | P-04 | Отклонить или оставить только для латиницы; запись в ADR |
| Память > 1,5 ГБ | AC-10 | Без CTC; выгрузка словарных структур; эскалация |
| Нет инструмента для генерации шума | P-05 | Синтез в Swift/Python без новых зависимостей; иначе H-1 |

Откат: каждый шаг — отдельный коммит в `feat/copilot-02`; при провале — `git revert` своего коммита.
`feat/copilot-01` и `main` не меняются. Деструктивные git-команды запрещены (CLAUDE.md).

## Условия остановки (эскалация владельцу)
- Нужна зависимость, модель или сервис вне ADR-0001 и intent (кроме CTC 110M при Q3 = да).
- Порог AC недостижим без изменения границ задачи.
- Найдены ключи или личные данные в Git.
- Три попытки подряд по одной проблеме без прогресса — состояние и гипотезы в handoff.md.
- Любое действие из списка «Запрещено» в CLAUDE.md.

## Готово, когда
AC-01…AC-12 имеют свидетельство в report.md (PASS или NOT RUN с причиной, принятой владельцем), ревью P-11 без
открытых P0/P1, ветка `feat/copilot-02` запушена, handoff.md актуален, владелец подтвердил H-3.
