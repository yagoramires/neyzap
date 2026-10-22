#!/bin/zsh
# Envia um comando de depuração ao NeyZap aberto. Precisa do canal ligado
# (defaults write local.neyzap debugBridge -bool true + reabrir o app), que cria a
# senha em ~/Library/Application Support/NeyZap/debug/token.
# Uso: scripts/debug.sh dump | snap | size 420x700 | front | reload | select <guia> | eval <expr> | evalin <guia> <expr> | ...
set -euo pipefail
TOKEN_FILE="$HOME/Library/Application Support/NeyZap/debug/token"
[[ -r "$TOKEN_FILE" ]] || { echo "canal de depuração desligado (sem $TOKEN_FILE)" >&2; exit 1; }
swift - "$(cat "$TOKEN_FILE") $*" <<'EOF'
import Foundation
DistributedNotificationCenter.default().postNotificationName(
    .init("local.neyzap.debug"), object: CommandLine.arguments[1], userInfo: nil, deliverImmediately: true)
EOF
