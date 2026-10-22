#!/bin/zsh
# Envia um comando de depuração ao NeyZap aberto. Precisa do canal ligado
# (defaults write local.neyzap debugBridge -bool true + reabrir o app), que cria a
# senha em ~/Library/Application Support/NeyZap/debug/token (nova a cada abertura).
# O comando vai num arquivo só do usuário; a notificação que avisa o app vai vazia
# (a senha nunca aparece na lista de processos nem no canal de notificações).
# Uso: scripts/debug.sh dump | snap | size 420x700 | front | reload | select <guia> | eval <expr> | evalin <guia> <expr> | ...
set -euo pipefail
DIR="$HOME/Library/Application Support/NeyZap/debug"
[[ -r "$DIR/token" ]] || { echo "canal de depuração desligado (sem $DIR/token)" >&2; exit 1; }
umask 077
printf '%s %s' "$(<"$DIR/token")" "$*" > "$DIR/.command.tmp"
mv "$DIR/.command.tmp" "$DIR/command"
swift - <<'SWIFT'
import Foundation
DistributedNotificationCenter.default().postNotificationName(
    .init("local.neyzap.debug"), object: nil, userInfo: nil, deliverImmediately: true)
SWIFT
