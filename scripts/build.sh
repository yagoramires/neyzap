#!/bin/zsh
# Compila e empacota o NeyZap.app em build/ (sem precisar do Xcode).
# Uso: scripts/build.sh [release|debug] [--run]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
RUN=0
for arg in "$@"; do
  case $arg in
    debug|release) CONFIG=$arg ;;
    --run) RUN=1 ;;
  esac
done

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/NeyZap"

APP=build/NeyZap.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NeyZap"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/inject.js Resources/layout.css "$APP/Contents/Resources/"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# Assina com o certificado local se existir (scripts/setup-signing.sh); senão, ad-hoc.
IDENTITY="NeyZap Local Signing"
security find-certificate -c "$IDENTITY" >/dev/null 2>&1 || IDENTITY="-"
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
echo "✓ $APP"

if (( RUN )); then
  pkill -x NeyZap 2>/dev/null || true
  while pgrep -x NeyZap >/dev/null; do sleep 0.2; done
  open -n "$APP"
fi
