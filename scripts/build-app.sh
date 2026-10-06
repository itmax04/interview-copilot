#!/usr/bin/env bash
# Сборка dist/InterviewCopilot.app (ADR-0001 п. 2–3, plan.md P-01).
# Подпись — постоянным локальным сертификатом «InterviewCopilot Dev» (точка H-1),
# чтобы разрешения macOS не сбрасывались при пересборке.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="InterviewCopilot"
IDENTITY="${CODESIGN_IDENTITY:-InterviewCopilot Dev}"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

if ! security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
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

echo "==> упаковка $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Ресурсы приложения (pricing.json и т.п.) появляются на следующих шагах.
find "$ROOT/Resources" -maxdepth 1 -type f ! -name Info.plist -exec cp {} "$APP/Contents/Resources/" \;

# Иконка рисуется самим приложением (ParrotIcon), затем iconutil собирает .icns.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
"$BIN" --export-iconset "$TMP/AppIcon.iconset"
iconutil -c icns "$TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

# Нативные библиотеки (whisper/llama XCFramework), если есть, кладутся в Frameworks.
BIN_DIR="$(dirname "$BIN")"
if compgen -G "$BIN_DIR/*.framework" > /dev/null; then
  mkdir -p "$APP/Contents/Frameworks"
  cp -R "$BIN_DIR"/*.framework "$APP/Contents/Frameworks/"
fi

echo "==> подпись «$IDENTITY»"
if [ -d "$APP/Contents/Frameworks" ]; then
  find "$APP/Contents/Frameworks" -maxdepth 1 -name "*.framework" -exec \
    codesign --force --sign "$IDENTITY" --timestamp=none {} \;
fi
codesign --force --sign "$IDENTITY" --timestamp=none \
  --identifier com.itmax04.interviewcopilot "$APP"
codesign --verify --strict "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Authority|Signature" || true

echo "OK: $APP"
