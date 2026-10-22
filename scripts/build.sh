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

# Assina com o certificado local (scripts/setup-signing.sh). Sem ele, a assinatura
# ad-hoc muda a cada build: o macOS volta a pedir permissões (câmera, microfone,
# notificações) e acesso ao Chaveiro. Só segue assim com ALLOW_ADHOC=1.
IDENTITY="NeyZap Local Signing"
if ! security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  if [[ "${ALLOW_ADHOC:-0}" != 1 ]]; then
    echo "✗ certificado \"$IDENTITY\" não encontrado. Rode scripts/setup-signing.sh (ou ALLOW_ADHOC=1 para assinar ad-hoc)." >&2
    exit 1
  fi
  echo "⚠️  assinando ad-hoc (ALLOW_ADHOC=1): permissões e Chaveiro vão ser pedidos de novo" >&2
  IDENTITY="-"
fi
# Runtime reforçado (bloqueia injeção de bibliotecas), com câmera e microfone liberados.
codesign --force --sign "$IDENTITY" --timestamp=none --options runtime \
  --entitlements Resources/NeyZap.entitlements "$APP"
echo "✓ $APP"

if (( RUN )); then
  scripts/restart.sh "$APP"
fi
