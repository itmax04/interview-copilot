#!/usr/bin/env bash
# Проверка английской таблицы интерфейса (COPILOT-10): у каждой строки интерфейса есть перевод, форматы (%@, %lld, %.1f)
# совпадают. Ключи строк SwiftUI дает компилятор (-emit-localized-strings), остальные — scripts/l10n-keys.py.
#   scripts/check-localization.sh            — проверка (код возврата 1, если есть ключи без перевода)
#   scripts/check-localization.sh --unused   — плюс переводы, ключей которых больше нет в коде
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="$ROOT/.build/l10n/strings"
mkdir -p "$OUT"
# Отдельная папка сборки: флаги не пересобирают обычную .build/debug.
swift build --build-path .build/l10n/build \
  -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$OUT" >/dev/null
plutil -lint -s Resources/en.lproj/Localizable.strings
python3 scripts/l10n-keys.py "$OUT" --missing "$@"
