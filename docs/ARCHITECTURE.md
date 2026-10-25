# Interview Copilot — устройство приложения

Документ для нового разработчика или агента: что делает приложение, как идут данные, где что лежит, как менять
и проверять. Начните отсюда, затем — `CLAUDE.md` (правила работы) и комплект последней задачи в `docs/changes/`.

## 1. Что это
Личное приложение macOS (Swift 6, SwiftUI + AppKit, SwiftPM, без .xcodeproj): попугай в строке меню и плавающая панель.
Во время созвона (Google Meet в браузере, Zoom, Telegram) приложение:
1. слушает звук собеседника (ScreenCaptureKit, звук одного приложения) и, отдельно, микрофон владельца;
2. **локально** расшифровывает речь (Parakeet v3 через FluidAudio; Whisper через whisper.cpp — запасной и для уточнения);
3. отсеивает шум, чужую речь и чужие голоса;
4. определяет конец вопроса (ход);
5. показывает ответ: карточку из базы владельца или подсказку языковой модели (Groq → Cerebras → Gemini → DeepSeek →
   Claude → свой API), со стримингом, первые слова — около 1 с после конца вопроса;
6. помнит интервью целиком: вопросы, ответы владельца, показанные подсказки.

Языки: украинский, русский, английский. Пользователь один — владелец. Звук на диск не пишется.

## 2. Поток данных
```
звук приложения звонка ─► SystemAudioCapture ─► AudioRingBuffer (30 с) ─► StreamingTranscriber ─┐
микрофон владельца ─► MicActivityDetector (говорит ли владелец) ─► TurnDetector                    │
                    └► второй StreamingTranscriber (ответы владельца) ─► InterviewMemory.addAnswer   │
                                                                                                    ▼
StreamingTranscriber: EnergyVAD режет фразы → [LocalVQE, выкл.] → Silero «есть ли речь» →
  Parakeet (итог ~0,1 с) → HallucinationFilter → отпечаток голоса CAM++ (режим микрофона) →
  события .partial / .final / .revised (уточнение Whisper turbo, ~3 с) / .foreignVoice / .discarded
                                                                                                    │
ListeningController.handle: фильтр языка (LanguageGate + словарь терминов) → строка в панели или серая строка
                                                                                                    ▼
TurnController → TurnDetector: пауза T (700 мс, после «?» — 350 мс), речь владельца, эхо → Turn
  + опережающий запрос (draft) на законченную фразу до истечения паузы
                                                                                                    ▼
AppDelegate.turnCompleted → InterviewMemory.addQuestion(turnID) → AnswerController.handle(turn)
  AnswerController: BankController.lookup (один эмбеддинг bge-m3: карточки базы + фрагменты материалов) →
  AnswerRouter (режим) → карточка | PromptBuilder (профиль, инструкции, <materials>, история) → ProviderChain
  (стриминг SSE, параллельный запуск через 1,5 с молчания, автопереход при ошибках) → AnswerHistory (вопрос → версии;
  каждый запрос пишет только в свою версию) → PanelModel → PanelView (оверлей: Toolbar, TranscriptStrip, AnswerCard, ChatField)
                                                                                                    ▼
подсказка → InterviewMemory.setHint(turnID); всё — SessionController → SessionStore (JSON, срок хранения)
```
Главный поток (`@MainActor`) — UI и контроллеры. Распознавание, эмбеддинги, Связка ключей и сеть — в фоне
(`Task.detached`, очереди транскрайбера). Между потоками — маленькие `…Box` с `NSLock` (`TranscriberBox`, `VoiceGateBox`,
`EnhancerBox`, `AudioRouteBox`).

## 3. Модули
| Папка | Что | Ключевые типы |
|---|---|---|
| `Sources/CopilotCore/Audio` | захват, VAD, буфер, разрешения | `SystemAudioCapture`, `MicrophoneCapture`, `EnergyVAD`, `AudioRingBuffer`, `AudioSourceResolver` |
| `…/STT` | распознавание | `StreamingTranscriber` (сегментация, итоги, уточнение), `ParakeetEngine`, `WhisperEngine`, `HybridRecognizer` |
| `…/Filter` | что не распознавать и не показывать | `SileroSpeechGate`, `LanguageGate`, `TermDictionary`/`BuiltinTerms`, `VoicePrint`/`VoiceEmbedder`/`VoiceGateBox`, `SpeechEnhancer`, `HallucinationFilter` |
| `…/Turns` | конец вопроса | `TurnDetector` (чистая логика, вся покрыта тестами), `TurnEval` |
| `…/Profiles` | профили, загрузка файлов, материалы (COPILOT-08) | `ProfileLibrary` (создать, переключить, удалить, перенос старого `profile/`, материалы), `ProfileDocument`, `DocumentText` (PDF — PDFKit, .docx/.rtf — AppKit, .txt/.md), `MaterialChunker`, `MaterialIndex`, `MaterialIndexBuilder` |
| `…/Bank` | профиль и база ответов | `Profile`, `ProfileStore.load`, `QuestionBank` (YAML: `BankCard` со статусом ответа, `QuestionBankWriter`), `QuestionImport` (правила + модель), `QuestionPreparation` (формулировки, черновики), `BankMatcher`, `TextEmbedder` |
| `…/Answer` | выбор: карточка / нет в базе / генерация; история ответов | `AnswerRouter`, `ScreenshotTask`/`ScreenshotTaskTracker` (задача со скриншота, 30 с, `<active_task>`), `FollowUpDetector` (короткие уточнения), `AnswerStyle` (формат, длина, тон → правило промпта; `AnswerShape` — проверка формы), `AnswerHistory` (`AnswerEntry` → `AnswerVersion`: hint / bank / strong / screenshot / refine, статусы, ←/→, «новый ответ») |
| `…/LLM` | провайдеры и промпт | `PromptBuilder` (все правила для модели), `ProviderChain` + `ChainFactory`, `Providers` (Gemini, DeepSeek, Anthropic, OpenAI-совместимые: Groq, Cerebras, свой API), `SSEClient`, `KeyVerifier` |
| `…/Memory` | память интервью | `InterviewMemory`, `SessionExchange`, `MemoryContext`, `ReferenceDetector`, `PromptScenarios` |
| `…/Storage` | история сессий | `SessionRecord` (с `config` сессии, вашими фразами по времени и разбором), `SessionStore` |
| `…/Review` | разбор после End (COPILOT-09) | `SessionReview` (статус, `ReviewComment`, `ReviewSummary`, `ReviewQA`), `ReviewPrompt` (комментарии порциями, сводка, «Спросить ИИ»), `TimelineEntry` / `SessionRecord.timeline` |
| `…/Session` | сессия (COPILOT-09) | `SessionConfig`/`SessionType`/`SessionPhase`/`SessionClock`, `Preflight` (проверка перед стартом), `CallDetection`, `JobImport` |
| `…/Localization` | язык интерфейса (COPILOT-10) | `L10n` (ключ — русская строка, английский — `en.lproj`, `Scope` для тестов), `PageLocalization` (страницы по `en.json`) |
| `…/Settings` | настройки и пути | `AppSettings` (миграции `schemaVersion`), `SettingsStore` (UserDefaults `settings.v1`), `AppPaths` |
| `…/Secrets` | ключи API | `KeychainStore` (service `com.itmax04.interviewcopilot`) |
| `…/Interviewer`, `…/TestCall` | ИИ-собеседование голосом, тестовый звонок в браузере | `InterviewerPrompt`, `SpeechSynth`, `AnswerCapture`, `LocalTestCallServer`, `TranscriptComparison` |
| `…/Hotkeys`, `…/Menu` | глобальные клавиши (Carbon), состав меню | `HotkeyCenter`, `HotkeyAction`, `MenuLayout` (без AppKit — тестируется) |
| `…/Usage`, `…/Privacy`, `…/Models`, `…/Capture`, `…/Logging` | расход и бюджет, фильтр ПД, загрузка моделей с SHA256, скриншот, логи | `UsageMeter`, `PIIFilter`, `ModelDownloader`, `ScreenshotService`, `Log` |
| `Sources/CopilotEmbeddings` | bge-m3 через llama.cpp (отдельно из-за заголовков ggml) | `LlamaEmbedder` |
| `Sources/InterviewCopilot` | приложение: связывает всё | `AppDelegate` (App.swift — вся проводка колбэков), `LiveSessionController` (Start/End, таймер, определение звонка), `Workspace/WorkspaceWindow` (главное окно: «Сегодня», «Сессии», «Профили», «ИИ-собеседование», «Настройки»), `Design/DesignSystem` (IC — динамические цвета светлой и темной темы и компоненты P00, ICDark — оверлей), `Design/Localization` (`UILanguage`, `localizedRoot`, `L(…)`, перегрузки `Text(String)` и др.), `SessionWizard` (мастер), `AnswerStyleEditor`/`StylePreview` (стиль ответа с предпросмотром), `ListeningController` (в т. ч. `standby` без сессии), `TurnController`, `AnswerController`, `SessionController` (история), `ReviewController` (разбор в фоне), `PanelController` (свернуть, следующий экран, фокус чата, проверка видимости)/`PanelView`/`AnswerCardView`, `Theme`, настройки, профиль, история |
| `Sources/copilot-eval` | CLI замеров | см. §6 |

Правило: логика — в `CopilotCore` (тестируется без UI), приложение только связывает и показывает.

## 4. Данные на диске
`~/Library/Application Support/InterviewCopilot/` (подменяется `INTERVIEWCOPILOT_HOME`):
- `profiles/<id>/` — `profile.yaml` (имя), `resume.md`, `stories.md` (факты о себе), `job.md`, `instructions.md`
  (инструкции профиля), `questions.yaml`, `sources/` (загруженные исходники), `materials/` (текст `*.md` + `sources/`),
  `materials-index.plist` (векторы фрагментов); права 700/600. Активный — `AppSettings.activeProfileID`;
- `instructions.md` — общие инструкции владельца (для всех профилей и «Без профиля»). Старая папка `profile/` переносится в
  `profiles/` при запуске, неизменённая копия примера удаляется; `profile.example/` — только для тестов и eval;
- `models/` — Whisper, bge-m3, Parakeet, Silero, CAM++, LocalVQE (списки и SHA256: `models.sha256`, `parakeet-models.json`, `filter-models.json`);
- `sessions/*.json` — история (реплики, ходы, обмены с ответами владельца), права 600, удаляется по сроку;
- `voice/owner.json` — отпечаток голоса (192 числа), права 600; `usage.json` — расход.
Настройки — UserDefaults `com.itmax04.interviewcopilot`, ключ `settings.v1`. Ключи API — только Связка ключей.

## 5. Как делать типичные изменения
- **Инструкции владельца** — блок `<owner_instructions>` в конце `PromptBuilder.system`: важнее правил стиля и формата,
  но не правил надёжности; профиль, материалы, реплики — по-прежнему данные.
- **Правило для модели** — `PromptBuilder.system` / `user`; закрепить тестом в `Tests/CopilotCoreTests/` и, если поведение
  модели, — сценарием в `PromptScenarios` + живой прогон `--smoke-memory`.
- **Провайдер LLM** — `ProviderID` + `ProviderEndpoints` + реализация `LLMProvider` (SSE) + `ChainFactory.providers` +
  `AppSettings.chain` (миграция) + `KeyVerifier`; фикстуры потоков — `Tests/CopilotCoreTests/Fixtures/`.
- **Настройка** — поле в `AppSettings` (+ декодирование со значением по умолчанию, `normalized()`), UI в `Settings/`,
  реакция — в `AppDelegate.applySettings`.
- **Горячая клавиша** — новый `HotkeyAction` **только в конец** `allCases` (номер = индекс), умолчание в `HotkeyBinding.defaults`,
  обработка в `AppDelegate.handle(_ action: HotkeyAction)`; подписи в UI — через `hotkey(_:)`, не литералом.
- **Пункт меню** — `MenuAction` + `MenuLayout.sections` + `AppDelegate.handle(_ action: MenuAction)` + тест `MenuLayoutTests`.
- **Текст интерфейса** — русская строка одной строкой: литерал SwiftUI переводится сам, строка из кода — `L("…")`
  (`CopilotCore` — `L10n.t`/`f`); перевод — в `Resources/en.lproj/Localizable.strings`, проверка — `scripts/check-localization.sh`.
  Новое окно — `.localizedRoot()` на корне и `UILanguage.shared.setTitle(_:of:)` для заголовка. Цвета — только токены `IC`.
- **Цепочка моделей** — порядок попыток и отказов в `ProviderChain` (последовательный `run` и параллельный `runHedged`): ключи
  провайдера по очереди → следующий провайдер → `lastResort` (ожидание сброса ключа ≤ 25 с, терпеливый таймаут). Остывание — в
  `ProviderHealth` (429 — ключ, таймаут/5xx — модель целиком). Новая модель с особым таймаутом — `Step.minFirstTokenTimeout`.
- **Размер оверлея** — полосы `PanelResizeHandle` (AppKit) по периметру окна, геометрия — `PanelResizing` в Core (тесты).
- **Новое поле в истории** — опционально или `decodeIfPresent`: старые файлы должны читаться.
- **Новая зависимость или модель** — только через запись в `docs/decisions/ADR-0001-stack.md`; модели — с SHA256.

## 6. Проверки
| Что | Команда |
|---|---|
| Быстро | `swift build && swift test` (337 тестов) |
| Полностью | `swift test && scripts/run-evals.sh && scripts/secret-scan.sh && scripts/check-localization.sh && scripts/build-app.sh` |
| Переводы | `scripts/check-localization.sh [--unused]` — ключи без перевода, несовпадение форматов |
| Звуковые eval | `scripts/run-evals.sh filter voice` (нужны модели Parakeet, Silero, CAM++) |
| CLI | `swift run -c release copilot-eval <stt|stt-parakeet|stt-hybrid|stt-stream|turn|bank|filter-text|filter|voice|voice-enroll|enhance|memory|exit-check>` |
| Живые (тратят бесплатные лимиты) | `dist/InterviewCopilot.app/Contents/MacOS/InterviewCopilot --smoke-llm`, `--smoke-memory 5`, `--smoke-prepare`, `--smoke-session`, `--smoke-review`, `--smoke-task evals/fixtures/two-sum.png`, `--ui-snapshots <папка>` (снимки окон без звука), `--smoke-screenshot evals/fixtures/two-sum.png` |
| Метрики созвона | `scripts/metrics.py --last 30m` (из журнала, только числа) |

Пороги eval — `evals/README.md`. Живые проверки запускаются из подписанного `.app`: только ему Связка ключей отдаёт ключи без запроса.

## 7. Журнал и отладка
`log show --predicate 'subsystem == "com.itmax04.interviewcopilot"' --info --last 30m` (в zsh — `/usr/bin/log`).
Категории: `audio`, `stt`, `turns`, `llm`, `metrics`, `app`. Важные события: `transcript_final`, `transcript_revised`,
`filtered reason=lang|vad|voice|echo|hallucination`, `voice_ok similarity=…`, `turn_end`, `draft_start/used/cancelled`,
`first_token … ms_from_speech_end=…`, `not_a_question`, `owner answering on/off`, `owner_final`, `new interview: …`.
**В журнал не пишутся тексты реплик, ответов и ключи** — только события, числа, ID моделей.

## 8. Правила (кратко, полностью — CLAUDE.md)
- Ключи и личные данные — никогда в код, логи, тесты, коммиты; тестовые данные — синтетические.
- Одна задача — `docs/changes/COPILOT-NN/` (intent → spec → [plan] → handoff) и ветка `feat/copilot-NN-…` от предыдущей;
  после шага — коммит; push и merge в `main` — по решению владельца; без force-push и переписывания истории.
- В handoff — что сделано, коммиты, проверки PASS/FAIL/NOT RUN, решения исполнителя, следующий шаг.

## 9. История задач
| Задача | Что | Ветка |
|---|---|---|
| COPILOT-01 | v1: захват, Whisper, база, Gemini/DeepSeek/Claude, панель, меню, история | `feat/copilot-01` |
| COPILOT-02 | документы по Parakeet v3 (не слита) | `docs/copilot-02` |
| COPILOT-03 | ИИ-собеседование голосом, Parakeet + гибрид с Whisper, режим «Без профиля» | `feat/copilot-03-ai-interviewer` |
| COPILOT-04 | мгновенные ответы: Groq/Cerebras, параллельный запуск, опережающий запрос, свой API | `feat/copilot-04-instant-answers` |
| COPILOT-05 | фильтры: Silero, язык с терминами, отпечаток голоса, LocalVQE, речь владельца на созвоне | `feat/copilot-05-speech-filter` |
| COPILOT-06 | память интервью, «Новое интервью», подсказка вместо незаписанного ответа, ⌃⌥A | `feat/copilot-06-session-memory` |
| COPILOT-07 | аудит и доводка: ловушки «вы упоминали», привязка к ходу, меню «Сейчас отвечаю я», история, `--smoke-memory` | `feat/copilot-07-hardening` |
| COPILOT-08 | профили: окно «Профиль», PDF/Word/RTF/текст, инструкции владельца, материалы, вопросы с ответами (по этапам) | `feat/copilot-08-profiles` |
| COPILOT-11 | правки по тестовому собеседованию: «последний шанс» цепочки (ждет сброс лимита ключа), hedge к другому провайдеру, снимки только провайдерам с изображениями, граница таймаута Gemini 7 с, правило «работали ли вы с X?», размер оверлея мышью (0.15) | `feat/copilot-11-test-call-fixes` |
| COPILOT-10 | светлая и темная тема окон, интерфейс на русском и английском (сразу, без перезапуска), разбор на языке интерфейса (версия 0.14) | `feat/copilot-10-theme-language` |
| COPILOT-09 | уровень ParakeetAI: сессии (мастер, Start/End, проверка, импорт вакансии), живой оверлей, стиль ответа, разбор после End, задачи со скриншотов, редизайн по образцам ImageGen (этапы 1–7, версии 0.7–0.12) | `feat/copilot-09-parakeet-parity` |

Ветки идут цепочкой (каждая от предыдущей); `main` пока содержит только начальный коммит — слияние решает владелец.

## 10. Известные ограничения и куда расти
- Распознавание украинского у Parakeet — главный источник ошибок текста; уточнение Whisper иногда портит фразу.
- Ответы модели вероятностные: правила проверяются `--smoke-memory`, но не гарантированы.
- Бесплатные лимиты Groq/Gemini (≈30 запросов в минуту) при быстрой серии вопросов переключают цепочку на запасные модели.
- Эхоподавления нет: эхо отсекают отпечаток голоса и правило по времени (COPILOT-05 R-04).
- Идеи: «Дополнить образец голоса», слияние веток в `main`, сводка интервью после звонка (решение владельца 06/Q3 — пока нет).
