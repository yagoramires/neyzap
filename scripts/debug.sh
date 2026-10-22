#!/bin/zsh
# Envia um comando de depuração ao NeyZap aberto (precisa de debugBridge ligado).
# Uso: scripts/debug.sh dump | snap | size 420x700 | front | reload
set -euo pipefail
swift - "$*" <<'EOF'
import Foundation
DistributedNotificationCenter.default().postNotificationName(
    .init("local.neyzap.debug"), object: CommandLine.arguments[1], userInfo: nil, deliverImmediately: true)
EOF
