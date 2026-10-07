# Interview Copilot

## Назначение
Личное приложение для macOS (строка меню + плавающая панель), которое слушает собеседника
в Google Meet / Zoom / Telegram, локально расшифровывает речь (украинский, русский, английский),
находит вопрос в заранее подготовленной базе ответов владельца и показывает ответ.
Если вопроса нет в базе, по выбранному режиму генерирует подсказку через Gemini
с переходом на DeepSeek или Claude. По горячей клавише отправляет скриншот задачи в сильную модель.
Пользователь один — владелец; распространение не планируется.

Статус: **v1 готова к приёмке** — [docs/changes/COPILOT-01/report.md](docs/changes/COPILOT-01/report.md).

## Требования к среде
- Mac на Apple Silicon, macOS 15+ (проверено на M1 8 ГБ, macOS 15.7.2).
- Xcode 26+ (без Xcode не работают тесты — решение P-00): `sudo xcode-select -s /Applications/Xcode.app`.
- Сертификат подписи кода «InterviewCopilot» или «InterviewCopilot Dev» в Связке ключей (самоподписанный, «Подписание кода»).
- Свободно ≥ 3 ГБ на модели.
- Ключ Gemini API (бесплатный тариф). DeepSeek и Anthropic — по желанию.
- Память во время созвона: приложение ≈ 1,1–1,2 ГБ.

## Быстрый запуск
```bash
scripts/fetch-models.sh        # модели whisper и эмбеддингов, проверка SHA256 (или мастер первого запуска)
scripts/build-app.sh           # сборка и подпись dist/InterviewCopilot.app
open dist/InterviewCopilot.app # попугай в строке меню; панель — ⌃⌥H
```
Первый запуск: мастер «Разрешения → ключ Gemini → модели». Разрешения «Запись экрана и системного звука»
и «Микрофон» выдаются в Системных настройках вручную. После пересборки macOS один раз спрашивает доступ к ключу
в Связке ключей — «Разрешать всегда».

## Как пользоваться
- **Listening — <app>**: источник звука (Auto: Zoom → Chrome → Telegram, конкретное приложение или весь системный звук).
- **Mode**: Question bank only / Bank + hint / Generate every answer.
- **Language**: Auto (UK/RU/EN) или конкретный язык — если язык собеседования известен, выберите его: точнее и быстрее.
- **Question bank…** — `~/Library/Application Support/InterviewCopilot/profile/questions.yaml`
  (формат — spec R-06; по 2+ формулировки на язык для каждой карточки). **Edit resume & stories…** — папка профиля.
- Горячие клавиши (переназначаются в Settings → Hotkeys): ⌃⌥↩ ответить сейчас, ⌃⌥S скриншот, ⌃⌥H панель,
  ⌃⌥P пауза, ⌃⌥C сильная модель.
- **Settings… (⌘,)**: ключи, ID моделей и запасная модель Gemini, порог паузы, порог базы, фильтр личных данных,
  срок истории, вид панели, бюджет на платных провайдеров.

## Проверка
- Быстрая: `swift build && swift test` (143 теста).
- Полная: `swift test && scripts/run-evals.sh && scripts/secret-scan.sh && scripts/build-app.sh`.
- Evals: `scripts/run-evals.sh [bank|turn]` — пороги и baseline в [evals/README.md](evals/README.md).
- Метрики созвона: `scripts/metrics.py --last 30m` (AC-01…AC-03), память: `scripts/footprint-monitor.sh 10` (AC-05).
- Живые проверки из приложения: `dist/InterviewCopilot.app/Contents/MacOS/InterviewCopilot --smoke-llm`
  и `--smoke-screenshot evals/fixtures/two-sum.png` (тратят квоту Gemini).
- CLI: `swift run -c release copilot-eval <stt|stt-stream|turn|bank|exit-check>`.
- Что и как тестировать дальше — [docs/changes/COPILOT-01/test-plan.md](docs/changes/COPILOT-01/test-plan.md).

## Структура
- `Sources/CopilotCore/` — логика: `Audio/` (захват ScreenCaptureKit, VAD, буфер), `STT/` (whisper), `Turns/` (конец вопроса),
  `Bank/` (база, поиск, профиль), `LLM/` (провайдеры, цепочка, промпт), `Answer/`, `Privacy/`, `Capture/` (скриншот),
  `Storage/` (история), `Usage/` (расход), `Hotkeys/`, `Menu/`, `Models/` (загрузка моделей), `Settings/`, `Logging/`.
- `Sources/CopilotEmbeddings/` — эмбеддинги на llama.cpp (отдельно от whisper из-за заголовков ggml).
- `Sources/InterviewCopilot/` — приложение: меню, панель, настройки, мастер, история.
- `Sources/copilot-eval/` — CLI для evals и замеров.
- `Tests/CopilotCoreTests/` — тесты и фикстуры потоков провайдеров.
- `scripts/` — сборка, модели, evals, секреты, метрики, память, фикстуры.
- `profile.example/` — пример профиля вымышленного кандидата (копируется при первом запуске).
- `evals/` — наборы bank/turn, аудио- и скриншот-фикстуры, сценарий созвона.
- `docs/` — дизайн, ADR, комплект COPILOT-01 (intent, spec, plan, handoff, report, test-plan).

## Ограничения и безопасность
- API-ключи — только в Связке ключей macOS. Не в коде, не в логах, не в чате, не в Git (`scripts/secret-scan.sh`).
- Личный профиль и история сессий — в `~/Library/Application Support/InterviewCopilot/`, в Git не попадают.
- Аудио на диск не записывается (буфер ≤ 30 с в памяти); сохраняется только текст сессий (срок хранения настраивается).
- В логах только события и задержки, без текста реплик и ответов.
- Точность расшифровки зависит от звука: сжатый звук Meet с телефона распознаётся хуже (см. report.md, AC-10).
- Репозиторий приватный: `itmax04/interview-copilot`.
