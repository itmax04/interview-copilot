#!/usr/bin/env bash
# Скачивание моделей в ~/Library/Application Support/InterviewCopilot/models/ с проверкой SHA256 (R-22).
#   scripts/fetch-models.sh            — все модели из models.sha256
#   scripts/fetch-models.sh <файл>...  — только указанные
# При несовпадении суммы файл удаляется, код возврата 1.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${INTERVIEWCOPILOT_MODELS_DIR:-$HOME/Library/Application Support/InterviewCopilot/models}"
mkdir -p "$DEST"

want=("$@")
failed=0
while read -r sha file size url; do
  [[ -z "${sha:-}" || "$sha" == \#* ]] && continue
  if [ ${#want[@]} -gt 0 ] && [[ ! " ${want[*]} " == *" $file "* ]]; then continue; fi
  target="$DEST/$file"
  if [ -f "$target" ] && [ "$(shasum -a 256 "$target" | cut -d' ' -f1)" = "$sha" ]; then
    echo "OK (уже есть): $file"
    continue
  fi
  echo "==> $file ($((size / 1024 / 1024)) МБ)"
  curl -fL --retry 3 --progress-bar -o "$target.part" "$url"
  actual="$(shasum -a 256 "$target.part" | cut -d' ' -f1)"
  if [ "$actual" != "$sha" ]; then
    echo "ОШИБКА: SHA256 не совпадает для $file (ожидалось $sha, получено $actual). Файл удалён." >&2
    rm -f "$target.part"
    failed=1
    continue
  fi
  mv "$target.part" "$target"
  echo "OK: $file, SHA256 совпадает"
done < "$ROOT/models.sha256"
exit $failed
