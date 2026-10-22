#!/bin/zsh
# Compila a versão final e instala em /Applications/NeyZap.app (substitui a anterior).
# Uso: scripts/install.sh [--no-restart]   (--no-restart: o app aberto continua; a
# versão nova entra na próxima vez que ele abrir)
set -euo pipefail
RESTART=1
[[ "${1:-}" == "--no-restart" ]] && RESTART=0
cd "$(dirname "$0")/.."
scripts/build.sh release
# Troca o app de uma vez: o novo entra com outro nome e só então substitui o antigo,
# que vai para uma pasta temporária (um app aberto continua usando os arquivos dele).
NEW=/Applications/.NeyZap-novo.app
OLD="$(mktemp -d)/NeyZap.app"
rm -rf "$NEW"
cp -R build/NeyZap.app "$NEW"
[[ -d /Applications/NeyZap.app ]] && mv /Applications/NeyZap.app "$OLD"
mv "$NEW" /Applications/NeyZap.app
(( RESTART )) && scripts/restart.sh /Applications/NeyZap.app
echo "✓ instalado em /Applications/NeyZap.app"
