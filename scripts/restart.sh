#!/bin/zsh
# Fecha o NeyZap aberto do jeito normal (como ⌘Q, dando tempo de salvar tudo) e abre
# o app indicado. Uma instância só: duas cópias mexendo nos mesmos dados podem
# corromper sessões.
# Uso: scripts/restart.sh [caminho do .app]   (padrão: /Applications/NeyZap.app)
set -euo pipefail
APP="${1:-/Applications/NeyZap.app}"
if pgrep -x NeyZap >/dev/null; then
  osascript -e 'quit app "NeyZap"' >/dev/null 2>&1 || true
  for _ in {1..100}; do pgrep -x NeyZap >/dev/null || break; sleep 0.2; done
  sleep 1.5 # o macOS demora um instante para esquecer o processo antigo
fi
open "$APP"
