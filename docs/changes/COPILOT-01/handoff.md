# Передача COPILOT-01

Статус: in progress (P-04 завершён, далее P-05) · Обновлено: 2026-10-06 · Ветка: `feat/copilot-01` · Commit: см. `git log -1`
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

- 2026-10-06, H-1 пройдена: сертификат подписи создан (имя в Связке ключей — «InterviewCopilot», без « Dev»;
  `security find-identity -p codesigning` → 1 identity, CSSMERR_TP_NOT_TRUSTED — нормально для самоподписанного, trust не трогаю).
  `scripts/build-app.sh` собирает и подписывает `dist/InterviewCopilot.app`, приложение запускается.

- 2026-10-06, P-02 (код): `AppSettings`/`SettingsStore` (JSON в UserDefaults, значения по умолчанию из spec, ограничение диапазонов),
  `KeychainStore` (generic password, service `com.itmax04.interviewcopilot`), `ProviderEndpoints` + `KeyVerifier`
  («Проверить» = запрос списка моделей), `HTTPTransport` с mock для тестов, `AppModel`, вкладки настроек
  Keys/Models/Audio/Bank/Privacy/Panel/Hotkeys/Budget. Перед кодом Anthropic прочитан skill `claude-api` (curl/examples.md);
  эндпоинты Gemini и DeepSeek сверены с ai.google.dev/api/models и api-docs.deepseek.com/api/list-models.

- 2026-10-06, H-2 пройдена: владелец сохранил ключ Gemini и нажал «Проверить» → «OK · моделей: 62» (скриншот владельца).
  `security find-generic-password -s com.itmax04.interviewcopilot -a gemini` (без `-w`) — запись есть; значение не читалось.
- 2026-10-06, P-03 (код): `AudioSourceResolver` (Auto: Zoom → Chrome → Telegram, помощники приложения по префиксу bundle ID),
  `SystemAudioCapture` (SCStream только аудио, 16 кГц моно, `excludesCurrentProcessAudio`, смена источника через
  `updateContentFilter`), `PCMConverter`, `AudioRingBuffer` (≤ 30 с), `EnergyVAD`, `MicActivityDetector` (AVAudioEngine),
  `Permissions`, `Log` (os_log), `ListeningController`, окно разрешений с индикатором уровня, подменю «Listening» со списком
  запущенных приложений, пауза из меню.

- 2026-10-06, H-3 пройдена: владелец выдал «Запись экрана и системного звука» и «Микрофон». Скриншоты владельца:
  окно разрешений с двумя зелёными галочками, «Слушаю: Chrome»; меню с зелёной точкой «Listening — Chrome»
  (вырезка — `evidence/menu-2026-10-06-owner.png`, для AC-11). Видео YouTube в Chrome: в логе `capture stats … rate=16000 ch=1`
  (~16 000 сэмплов/с) и `level_db` −31…−14 dB во время воспроизведения, −120 dB в тишине.
  AC-13 (вид без разрешения): по логу `no screen capture permission`, процесс не упал, окно разрешений открылось само;
  визуальное подтверждение владельца до выдачи разрешений не получено — повторная проверка при H-5.
- Известная проблема (P-03 → P-05): без наушников микрофон слышит динамики, и `owner_speaking=true` во время речи собеседника.
  Это заблокирует автоответ (R-05, S-07). План: включить голосовую обработку AVAudioEngine (`setVoiceProcessingEnabled`,
  эхоподавление) и/или считать владельца говорящим, только когда микрофон громче эха системного звука. Делается на P-05.

- 2026-10-06, P-04: whisper.cpp `b5454` как `binaryTarget` (URL + checksum), `scripts/fetch-models.sh` + `models.sha256`
  (turbo q5_0 и small q5_1, SHA256 из Hugging Face LFS), `scripts/make-audio-fixtures.sh` → `evals/audio/*.wav`
  (Lesya, Milena, Samantha — все голоса есть), `WhisperEngine`, `StreamingTranscriber` (VAD-сегментация, частичный
  и итоговый текст, язык), `AppPaths`, `copilot-eval stt` / `stt-stream`, подключение к приложению.
  Решение turbo/small — small (таблица замеров в ADR-0001 «Итоговые решения»).

## Следующий шаг
P-05: определение хода, панель (базовая), горячие клавиши; там же эхо микрофона (см. «Известная проблема»).

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
| H-1 | `scripts/build-app.sh` | P-01 fix | PASS: `dist/InterviewCopilot.app`, `codesign -dvv` → `Identifier=com.itmax04.interviewcopilot`, `Authority=InterviewCopilot`; `codesign --verify` → valid on disk, satisfies DR |
| H-1 | `open dist/InterviewCopilot.app` | P-01 fix | PASS: процесс запущен (pgrep); видимость иконки — подтверждение владельца |
| P-02 | `swift build` | P-02 | PASS |
| P-02 | `swift test` | P-02 | PASS: 22 теста в 4 наборах (MenuLayout, SettingsStore, KeychainStore — настоящая Связка ключей, тестовый service, KeyVerifier — mock) |
| P-02 | `scripts/build-app.sh` | P-02 | PASS, `Authority=InterviewCopilot` |
| P-02 | `scripts/secret-scan.sh` | P-02 | PASS: «0 findings» |
| P-03 | `swift test` | P-03 | PASS: 36 тестов в 7 наборах (+AudioSourceResolver, AudioRingBuffer, EnergyVAD) |
| P-03 | `scripts/build-app.sh` | P-03 | PASS |
| P-03 | Запуск без разрешения | P-03 | PASS (лог): `no screen capture permission`, процесс жив, открыто окно разрешений; визуально — не подтверждено владельцем (AC-13 → H-5) |
| H-3 | Захват звука Chrome (YouTube) | P-03 | PASS: `level_db` −31…−14 dB при воспроизведении, ~16 000 сэмплов/с, 16 кГц моно |
| H-3 | Микрофон (VAD) | P-03 | PASS частично: речь владельца детектируется; без наушников ложные срабатывания от динамиков → P-05 |
| P-04 | `scripts/fetch-models.sh` | P-04 | PASS: оба файла скачаны, «SHA256 совпадает» |
| P-04 | `copilot-eval stt` (замеры turbo/small) | P-04 | см. ADR-0001: small 0,16–0,27 с на фразу, turbo 2,1–4,7 с |
| P-04 | `copilot-eval stt-stream` small, 6 фраз | P-04 | PASS: медиана конец фразы → текст 524 мс, макс. 583 мс, языки 6/6 |
| P-04 | Приложение, весь системный звук + `afplay` фикстур | P-04 | PASS: `transcript_final` 503–759 мс (медиана ~590), языки 6/6; `footprint` 453 МБ |
| P-04 | `swift test` | P-04 | PASS: 49 тестов в 9 наборах (+StreamingTranscriber с фейковым распознавателем, WhisperEngine на реальной модели) |
| P-01 | Запуск, иконка и меню видны (скриншот) | P-01 | Запуск debug-бинаря: процесс стартует без ошибок. Скриншот NOT RUN: у процесса исполнителя нет разрешения «Запись экрана» (`screencapture` даёт только обои), TCC не трогаю. Скриншот меню — на H-3/P-11 |

## Решения исполнителя
_(исполнитель дописывает: дата, шаг, решение, причина, ссылка на R-/AC-)_

- 2026-10-06, P-00: тесты пишутся на XCTest и/или Swift Testing после установки Xcode; флаги-обходы для CLT не используются (Q10, AC-14).
- 2026-10-06, P-01: структура меню вынесена в `CopilotCore` (`MenuLayout`) и покрыта тестами — проверяемая часть AC-11; AppKit только отрисовывает. Иконки пунктов — SF Symbols, близкие к картинке (HIG).
- 2026-10-06, P-01: иконка-попугай рисуется кодом (`ParrotIcon`), .icns собирается `iconutil` в build-app.sh — без бинарных ассетов в Git (R-15).
- 2026-10-06, P-01: в меню первой строкой для паузы — «Paused — <app>» и пункт «Resume listening» (R-15 говорит только о цвете точки; так понятнее, HIG).
- 2026-10-06, P-01: `secret-scan.sh` не проверяет email/телефоны в `profile.example/` и `evals/` (синтетика, AC-06); разрешены адреса `example.*`, `users.noreply.github.com`, `anthropic.com`.
- 2026-10-06, H-1: `build-app.sh` принимает сертификат «InterviewCopilot Dev» (ADR-0001 п. 3) или «InterviewCopilot» (фактическое имя после H-1); переопределение — `CODESIGN_IDENTITY`. Пересоздавать сертификат не просил: на поведение TCC имя не влияет.
- 2026-10-06, H-1: репозиторий лежит на «Рабочем столе» в iCloud Drive; File Provider вешает `com.apple.FinderInfo`, и `codesign` падает. Бандл собирается и подписывается во временной папке вне iCloud, затем `ditto --noextattr` в `dist/`; финальная проверка `codesign --verify` без `--strict` (AC-14).
- 2026-10-06, P-02: тексты окна настроек — по-русски (spec называет кнопки «Проверить», «Удалить», «ключ недействителен»), названия вкладок и меню — по-английски, как в R-15/R-18 и на картинке.
- 2026-10-06, P-02: Gemini авторизуется заголовком `x-goog-api-key`, а не параметром `?key=` из примера документации — R-23 требует ключ только в заголовках.
- 2026-10-06, P-02: «Проверить» при 429 — «лимит запросов», а не «ключ недействителен»; 400/401/403 — «ключ недействителен» (R-09). Текст ошибки провайдера очищается от значения ключа.
- 2026-10-06, P-02: Keychain — классическая (файловая) связка, не data protection keychain: для неё нужен entitlement keychain-access-groups и профиль подписи, которых у локальной подписи нет.
- 2026-10-06, H-2: у приложения-агента нет главного меню, поэтому ⌘V не вставлял ключ в поле. Добавлено невидимое главное меню с пунктами Edit (`MainMenu.swift`).
- 2026-10-06, P-02: вкладка Hotkeys пока показывает сочетания; регистрация, проверка занятости и переназначение — P-05 (R-17).
- 2026-10-06, P-03: Auto учитывает оба клиента Telegram (`ru.keepcoder.Telegram`, `org.telegram.desktop`); звук приложения берётся вместе с его помощниками (`com.google.Chrome.helper…`), иначе вкладки Chrome не слышно (R-01).
- 2026-10-06, P-03: уровень шума в VAD — минимум энергии за 3 с, а не экспоненциальное сглаживание: постоянный фон с первой секунды иначе считался речью (тест `steadyNoiseIsNotSpeech`) (R-02).
- 2026-10-06, P-03: слушание стартует само при запуске, если есть разрешение и найден источник; при отсутствии разрешения сразу открывается окно разрешений, системный запрос — только по кнопке «Запросить» (AC-13, S-09).
- 2026-10-06, P-03: без разрешения пункт «Listening» без подменю — клик открывает окно разрешений (R-15, AC-13).
- 2026-10-06, P-03: в zsh `log` — встроенная команда; для логов приложения использовать `/usr/bin/log show --predicate 'subsystem == "com.itmax04.interviewcopilot"' --info`.
- 2026-10-06, P-04: модель whisper по умолчанию — small q5_1 (AC-01, AC-05), а не turbo; подробности и цифры — ADR-0001 (R-03).
- 2026-10-06, P-04: язык uk/ru выбирается сравнением уверенности распознавания на обоих языках — детектор small ошибается на украинском (S-11, AC-10).
- 2026-10-06, P-04: тишина (< −55 dBFS) в модель не подаётся, длина вывода ограничена, повторы сворачиваются — whisper на тишине выдавал «you», «Повтори!» и зацикленный текст (R-03).
- 2026-10-06, P-04: первый запуск модели в новом бандле занимает ~18 с (компиляция Metal-шейдеров), дальше ~0,5 с. Мастер первого запуска (P-11) должен прогревать модель после загрузки.
- 2026-10-06, P-04: самопроверка конвейера без владельца — источник «All system audio» записывается в настройки приложения (`defaults write com.itmax04.interviewcopilot settings.v1`), фикстуры играются `afplay`; после проверки настройка возвращается (Auto).
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
