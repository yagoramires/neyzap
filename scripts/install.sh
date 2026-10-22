#!/bin/zsh
# Compila a versão final e instala em /Applications/NeyZap.app (substitui a anterior).
# Uso: scripts/install.sh [--no-restart]   (--no-restart: o app aberto continua; a
# versão nova entra na próxima vez que ele abrir)
set -euo pipefail
RESTART=1
[[ "${1:-}" == "--no-restart" ]] && RESTART=0
cd "$(dirname "$0")/.."
scripts/build.sh release
if (( RESTART )); then
  pkill -x NeyZap 2>/dev/null || true
  while pgrep -x NeyZap >/dev/null; do sleep 0.2; done
fi
rm -rf /Applications/NeyZap.app
cp -R build/NeyZap.app /Applications/
(( RESTART )) && open -n /Applications/NeyZap.app
echo "✓ instalado em /Applications/NeyZap.app"
