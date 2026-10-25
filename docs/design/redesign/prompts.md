# ImageGen prompts — Interview Copilot redesign (2026-10-24)

Order: P00 (style guide) first, then the others — attaching the P00 image and the phrase "Use the attached style guide exactly (colors, typography, radii, glass material)". Research and screenshots — research.pdf and `../audit-2026-10-24/`.

The prompts ask for a Russian UI on purpose (the app's primary language), so the quoted labels inside them stay in Russian.

## P00 · Style guide (reference image)
Size: 1536×1024

```
Design system sheet for a macOS app called "Interview Copilot" (a real-time interview assistant that listens to a call and shows suggested answers). macOS 15 Sequoia, Apple HIG, SF Pro typography, 8-pt grid. Show on one canvas: color palette swatches (indigo accent #4C6EF5, green #2FB344 "Слушаю", amber #F59F00 "Проверяю / Черновик", red #E03131 "Ошибка / Завершить", graphite neutrals); type scale (Title 22, Headline 15 semibold, Body 14, Caption 11) with Russian sample text; buttons (primary indigo, secondary bordered, destructive red, keycap hint chips like "⌘↩", "⌘⇧↩"); status pills with colored dots; a dark translucent glass card (#16181D 82% + blur, white text) next to a light window card; toggles, segmented control, text field, progress bar, list row with status capsule; icons in SF Symbols style. Clean, calm, premium, generous whitespace. Russian labels, crisp correctly spelled Cyrillic, no lorem ipsum, no watermark.
```

## P01 · Overlay: listening, question detected, answer appearing
Size: 1024×1536

```
macOS floating overlay window (dark translucent glass, #16181D 82%, background blur of a Google Meet call visible behind), width ~460 px, rounded 16 px, floating at the top-right of the screen. Layout top to bottom: (1) Action toolbar: two tiny live indicators (microphone with green level bars, call audio with green level bars), buttons "Ответ ⌘↩", "Скриншот ⌘⇧↩", "Чат ⌘⇧Space" as dark pill buttons with keycap hints, then icons move ✥ and collapse, a timer "12:47", a "⋮" menu and a red "Завершить" button. (2) Transcript strip: one line "Расскажите, как вы организовали тестирование в последнем проекте?" with a small "Interviewer" label, a "Очистить ⌘⇧⌫" chip and an expand icon. (3) Status chip "● Вопрос найден" in green. (4) Answer card: header "Вопрос: Тестирование в последнем проекте", nav arrows "‹ 3 / 7 ›", copy icon; body: first line bold and large "Строили пирамиду тестов: 70% unit, snapshot на ключевые экраны, e2e на оплату."; three short bullets; the last bullet is still streaming with a blinking caret. Footer of the card: "Groq · 1,1 с" and quick action chips "Короче", "Подробнее", "Пример". Russian UI, white text, high contrast, pixel-perfect product mockup.
```

## P02 · Overlay: states (a strip of 6 mini overlays)
Size: 1536×1024

```
One canvas showing six small versions of the same dark-glass macOS overlay (from P01) side by side, each labeled below: (1) "Проверяю…" — transcript line visible, amber spinner chip "Проверяю…"; (2) "Вопрос найден" — green chip; (3) "Не вопрос" — grey chip "Не вопрос · ответить вручную ⌘↩"; (4) "Готовлю ответ…" — new header "Вопрос: Почему вы уходите?" with a thin indigo progress line, the previous answer below is dimmed to 40% with a small label "предыдущий ответ"; (5) "Нет сигнала звонка 8 с" — call-audio indicator red, banner "Не слышу звонок · проверьте вкладку Meet" with button "Выбрать источник"; (6) "Ошибка" — red banner "Модели недоступны: лимит запросов" with buttons "Повторить" and "Сменить модель". Consistent spacing, Russian text, crisp typography.
```

## P03 · Overlay: chat and answer refinement
Size: 1024×1536

```
The dark-glass macOS overlay from P01 with the chat field open at the bottom: a rounded input "Спросите или уточните ответ…" with a send arrow and hint "↩ отправить · Esc закрыть". Above it, the answer card shows version tabs "Версия 1 · Версия 2 (короче)". A small indigo session-instruction badge under the toolbar: "На всю сессию: отвечать по-английски ✕". Quick chips above the input: "Короче", "Подробнее", "Пример кода", "Без жаргона". Russian UI, white text, pixel-perfect.
```

## P04 · Overlay: ⋮ menu and visibility check
Size: 1024×1536

```
The dark-glass overlay with its "⋮" menu open as a dark popover: rows "Автоответ" (toggle on), "Язык звонка: Українська ▾", "Масштаб − 100% + ↺", "На другой экран →", "Скрывать при демонстрации экрана" (toggle) with a secondary button "Проверить видимость", a result line "Проверено 24.10, macOS 15.7: в захвате экрана не видно ✓", divider, "Завершить сессию" in red. Rows have SF Symbol icons and keyboard hints. Russian UI, crisp text, premium macOS feel.
```

## P05 · Overlay: screenshot task with code
Size: 1024×1536

```
The dark-glass overlay answering a coding task captured by screenshot. Under the toolbar: an "Активная задача" bar with two small screenshot thumbnails (+ "Добавить снимок ⌘⇧↩") and a title "Two Sum — найти пару с суммой target". Answer card sections with small headers: "Задача", "Подход" (2 bullets), "Код" — a syntax-highlighted Swift code block in a darker inset with a "Копировать код" button, "Сложность: O(n) по времени, O(n) по памяти", "Проверки" (3 test cases). The transcript strip shows "А какая сложность по памяти?" with chip "уточнение к задаче". Russian UI, monospaced code, pixel-perfect.
```

## P06 · Collapsed overlay and menu bar
Size: 1536×1024

```
Left half: the overlay collapsed into a single compact dark-glass toolbar bar (indicators, "Ответ ⌘↩", "Скриншот", "Чат", timer "08:15", expand icon, red "Завершить"), floating over a Zoom call. Right half: the macOS menu bar dropdown of the app (parrot icon in menu bar), light vibrancy menu: header row "● Сессия идёт · Senior iOS — ФинБанк · 08:15", items "Показать оверлей ⌃⌥H", "Ответить сейчас ⌘↩", "Сделать скриншот ⌘⇧↩", "Завершить сессию", divider, "Создать сессию… ⌃⌥N", "Профили…", "История сессий…", divider, "Сегодня: 42 запроса · $0,00", "Настройки… ⌘,", "Выйти ⌘Q". Russian text, native macOS menu styling.
```

## P07 · "New session" wizard — step 1 "Details"
Size: 1536×1024

```
macOS sheet/modal window "Создать сессию", light theme, two-column layout. Left narrow column: title "Создать сессию", subtitle "Детали и настройки звонка", vertical stepper "1 Детали" (active, indigo), "2 Настройки", "3 Проверка", and at the bottom secondary buttons "Пробный звонок" and "Как это работает". Right column: segmented control "Собеседование | Обычный звонок | ИИ-собеседование" (first selected); field "Профиль" dropdown "Senior iOS — ФинБанк" with small chips "резюме ✓ · 3 материала · 24 вопроса"; button with sparkle icon "Вставить ссылку на вакансию"; fields "Компания" ("ФинБанк"), "Описание вакансии" (multiline, filled with a short realistic description); bottom right buttons "Отмена" and primary indigo "Далее". Clean, spacious, Russian UI, pixel-perfect.
```

## P08 · Wizard — step 2 "Settings"
Size: 1536×1024

```
Same "Создать сессию" window, step 2 active. Right column grouped list with icons: "Язык звонка" → dropdown "Авто (UK / RU / EN)"; "Модель" → dropdown "Groq · gpt-oss-120b (бесплатно)"; "Стиль ответа" → "Сценарий + пункты · Сбалансированный · Нейтральный" with button "Настроить"; "Указания на сессию" → button "+ Добавить"; section "Дополнительно": toggles "Автоответ на вопросы (рекомендуется)", "Сохранять расшифровку", "Разбор после завершения"; "План длительности" stepper "60 мин". Caption under toggles in small grey: "Расшифровка хранится только на этом Mac 30 дней". Buttons "Назад" and primary "Далее: проверка". Russian UI, light theme.
```

## P09 · Wizard — step 3 "Pre-start check"
Size: 1536×1024

```
Same window, step 3 "Проверка". A checklist with live results: "Микрофон — MacBook Pro" green check and a small live level meter; "Звук звонка — Google Chrome (Meet)" amber warning "нет сигнала 5 с · включите звук вкладки" with button "Выбрать источник"; "Распознавание — Parakeet v3, локально" green; "Модели — Groq, Gemini" green with "ключи проверены"; "Скриншоты — разрешение есть" green; "Профиль — резюме, 3 материала, 24 вопроса (подготовлено 20)" green. Big primary indigo button "Начать сессию" and secondary "Начать всё равно". Russian UI, clean light theme, pixel-perfect.
```

## P10 · "Start a session?" notification
Size: 1536×1024

```
macOS desktop with a Zoom meeting window, and a native macOS notification banner in the top-right corner from "Interview Copilot" (parrot app icon): title "Звонок в Zoom", text "Начать сессию с профилем «Senior iOS — ФинБанк»?", action buttons "Начать" and "Настроить…". Realistic macOS Sequoia look, Russian text.
```

## P11 · Answer settings with a live preview
Size: 1536×1024

```
macOS modal "Стиль ответа", light theme, two panes. Left: three rows with icons and chevrons — "Формат: Сценарий + пункты", "Длина: Сбалансированный", "Тон: Нейтральный"; one row is expanded showing a segmented control "Короткий | Сбалансированный | Подробный". Bottom buttons "По умолчанию" and primary "Сохранить для сессии". Right pane: dropdown "Тип вопроса: Поведенческий"; label "Предпросмотр · по вашему профилю"; a preview card with "Вопрос: Расскажите о конфликте в команде" and an answer — bold first line, 3 bullets — rendered like the overlay answer; a tiny "обновлено 1,2 с назад" caption. Russian UI, crisp text.
```

## P12 · Main window: "Today" (new home screen)
Size: 1536×1024

```
macOS main window "Interview Copilot", light theme, left sidebar with sections: "Сегодня" (selected), "Сессии", "Профили", "ИИ-собеседование", "Настройки", and at the bottom a status "● Готов к звонку". Main area: large greeting card "Готов к собеседованию" with primary indigo button "Создать сессию ⌃⌥N" and secondary "Пробный звонок"; a readiness row of four small cards ("Микрофон ✓", "Распознавание ✓ Parakeet", "Модели ✓ Groq", "Профиль ✓ Senior iOS — ФинБанк"); "Последние сессии" list with 3 rows (date, company, type chip "Собеседование", duration, score dot); a card "Подготовка" with progress "Вопросы подготовлены 20 / 24" and button "Подготовить". Calm, premium, spacious, Russian UI, pixel-perfect.
```

## P13 · Main window: Profile — résumé
Size: 1536×1024

```
Same main window, sidebar "Профили" selected with a secondary list of profiles ("Senior iOS — ФинБанк" selected, "Backend — стартап", "+ Новый профиль"). Content header: profile name, chips "резюме ✓", "3 материала", "24 вопроса", buttons "Переименовать", "⋯". Horizontal tabs: "Резюме" (selected), "Факты о себе", "Вакансия", "Инструкции", "Материалы", "Вопросы". Resume tab: a drop zone card "Перетащите PDF, Word или текст · или Загрузить файл ⌘O" collapsed to a slim bar with "cv-2026.pdf · прочитано 3 862 символа · заменить"; below, a two-pane view: left editable text, right a formatted preview of the resume (name, headings "Опыт", "Навыки", bullets). Footer hint: "В каждый запрос: 4 120 символов". Russian, light theme.
```

## P14 · Profile — materials and questions
Size: 1536×1024

```
Same main window, profile "Вопросы" tab. Toolbar: "Импорт файла ⌘I", "Добавить вопрос", primary "Подготовить (4)" and a progress capsule "Готовлю формулировки… 2 из 4". Left: table of questions with columns "Вопрос", "Ответ", "Формулировки", status capsules with legend ("ваш" green, "черновик" amber, "подтверждён" indigo, "нет ответа" grey). Right: detail editor for the selected question — question field, answer editor with status "черновик" and button "Подтвердить", list of phrasings grouped by language flags UK / RU / EN. A small inset in the corner shows the "Материалы" tab state: three files with per-file states "готов ✓", "индексирую 60%", "скан — нет текста ⚠". Russian UI, light theme.
```

## P15 · Session review — "Summary"
Size: 1536×1024

```
macOS window "Сессия · ФинБанк · 24 октября, 14:00 · 48 мин", light theme. Tabs: "Сводка" (selected), "Расшифровка", "Спросить ИИ". Top: summary card "Общее впечатление" with 3 strengths and 2 improvements, "Следующие шаги" (e.g. "Тех. интервью в четверг"). Below: list of question cards — each shows question title, "Вы ответили:" quote in regular text, "Подсказка на экране" collapsed chip, and an AI comment block with a small sparkle icon: "Хорошо: конкретные цифры. Не хватило: результата для бизнеса. Лучше сказать: …". A small progress line at the top "Разбор готов". Russian, pixel-perfect.
```

## P16 · Review — transcript and "Ask AI"
Size: 1536×1024

```
Same session window split view. Left: tab "Расшифровка" — chat-like transcript with speaker labels and timestamps: "Интервьюер 14:02" (grey bubble), "Вы 14:02" (indigo-tinted bubble), and between them a dashed small card "Подсказка показана" (collapsed). Right: tab "Спросить ИИ" — a chat pane with suggested prompts chips ("Какие вопросы были про архитектуру?", "Напиши письмо-благодарность", "Что подтянуть к следующему этапу?") and one answered message. Russian UI, light theme, clean.
```

## P17 · Settings (new)
Size: 1536×1024

```
macOS Settings window in System Settings style: left sidebar with icons "Основное", "Модели и ключи", "Звук и распознавание", "Ваш голос", "Ответы", "Горячие клавиши", "Приватность", "Бюджет". Selected "Модели и ключи": a top card "Для старта достаточно одного бесплатного ключа Groq" with status "Groq ✓ проверен"; a reorderable list "Порядок моделей" with drag handles (Groq, Cerebras, Gemini, DeepSeek, Claude, Свой API) each with status dot and "бесплатно"/"платно" tag; collapsed section "Дополнительно" (ID моделей, параллельный запрос, таймаут). Russian UI, light theme, pixel-perfect.
```

## P18 · First launch
Size: 1536×1024

```
macOS onboarding window, light theme, 4 steps shown as a horizontal progress at the top: "Разрешения ✓", "Бесплатный ключ" (active), "Модели", "Профиль". Active step content: big title "Подключите бесплатную модель", text "Groq отвечает за ~1 с и бесплатен", a secure field "Ключ Groq" with button "Проверить", link "Получить ключ на console.groq.com", a secondary option "Добавить другие модели позже". Illustration: small parrot mascot icon. Buttons "Назад" and primary "Далее". Russian, friendly, clean.
```

## P19 · AI interview (in the app style)
Size: 1536×1024

```
Main window section "ИИ-собеседование", light theme matching the app: left — setup card (language "Русский", "Вопросов: 6", "Профиль: Senior iOS — ФинБанк", "Длительность 30 мин", primary "Начать собеседование"); right — live area with a large round speaking indicator for the AI interviewer (indigo waveform), the current question in big text "Как вы бы спроектировали офлайн-режим?", below "Вы отвечаете…" with a green microphone level and the live transcript of the candidate; a timeline of 6 question dots (2 done). Russian UI, calm and focused.
```
