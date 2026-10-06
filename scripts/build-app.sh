#!/usr/bin/env bash
# Сборка dist/InterviewCopilot.app (ADR-0001 п. 2–3, plan.md P-01).
# Подпись — постоянным локальным сертификатом «InterviewCopilot Dev» (точка H-1),
# чтобы разрешения macOS не сбрасывались при пересборке.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="InterviewCopilot"
# Имя по ADR-0001 — «InterviewCopilot Dev»; при H-1 сертификат был создан как «InterviewCopilot» — принимаются оба.
if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  CANDIDATES=("$CODESIGN_IDENTITY")
else
  CANDIDATES=("InterviewCopilot Dev" "InterviewCopilot")
fi
IDENTITY=""
for c in "${CANDIDATES[@]}"; do
  if security find-identity -p codesigning | grep -q "\"$c\""; then IDENTITY="$c"; break; fi
done
DIST="$ROOT/dist"
FINAL_APP="$DIST/$APP_NAME.app"
# Бандл собирается и подписывается во временной папке вне iCloud Drive: если «Рабочий стол» синхронизируется,
# File Provider добавляет расширенные атрибуты, и codesign падает («detritus not allowed»).
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/interviewcopilot-build.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/$APP_NAME.app"

if [ -z "$IDENTITY" ]; then
  IDENTITY="${CANDIDATES[0]}"
  cat >&2 <<MSG
error: сертификат подписи «$IDENTITY» не найден в Связке ключей.
Создайте его по инструкции точки H-1 (docs/changes/COPILOT-01/plan.md):
«Связка ключей» → меню «Связка ключей» → «Ассистент сертификации» → «Создать сертификат…»,
имя «$IDENTITY», тип удостоверения «Самоподписанный корневой», тип сертификата «Подписание кода».
MSG
  exit 1
fi

echo "==> swift build -c release"
swift build -c release --product "$APP_NAME"
BIN="$(swift build -c release --show-bin-path)/$APP_NAME"

echo "==> упаковка"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Ресурсы приложения (pricing.json и т.п.) и пример профиля для первого запуска (R-21).
find "$ROOT/Resources" -maxdepth 1 -type f ! -name Info.plist -exec cp {} "$APP/Contents/Resources/" \;
cp -R "$ROOT/profile.example" "$APP/Contents/Resources/profile.example"
cp "$ROOT/models.sha256" "$APP/Contents/Resources/models.sha256"

# Иконка рисуется самим приложением (ParrotIcon), затем iconutil собирает .icns.
"$BIN" --export-iconset "$STAGE/AppIcon.iconset"
iconutil -c icns "$STAGE/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

# Нативные библиотеки (whisper/llama XCFramework), если есть, кладутся в Frameworks.
BIN_DIR="$(dirname "$BIN")"
if compgen -G "$BIN_DIR/*.framework" > /dev/null; then
  mkdir -p "$APP/Contents/Frameworks"
  cp -R "$BIN_DIR"/*.framework "$APP/Contents/Frameworks/"
fi

echo "==> подпись «$IDENTITY»"
xattr -cr "$APP"
if [ -d "$APP/Contents/Frameworks" ]; then
  find "$APP/Contents/Frameworks" -maxdepth 1 -name "*.framework" -exec \
    codesign --force --sign "$IDENTITY" --timestamp=none {} \;
fi
codesign --force --sign "$IDENTITY" --timestamp=none \
  --identifier com.itmax04.interviewcopilot "$APP"
codesign --verify --strict "$APP"

mkdir -p "$DIST"
rm -rf "$FINAL_APP"
ditto --noextattr --noqtn "$APP" "$FINAL_APP"
# Без --strict: iCloud Drive может снова повесить com.apple.FinderInfo на бандл в dist/, подпись при этом цела.
codesign --verify "$FINAL_APP"
codesign -dvv "$FINAL_APP" 2>&1 | grep -E "^Identifier|^Authority" || true

echo "OK: $FINAL_APP"
