#!/bin/zsh
# Gera os prints do README (docs/<tela>.png) a partir de
# design/readme-ui.html, uma réplica da janela com dados inventados: nunca use
# capturas da janela de verdade, que mostram conversas reais.
set -euo pipefail
cd "${0:A:h}/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
shot() { # view largura altura saída (largura/altura = janela + 2×28 px de margem)
  "$CHROME" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
    --default-background-color=00000000 --window-size="$2,$3" \
    --screenshot="$PWD/$4" "file://$PWD/design/readme-ui.html?view=$1" 2>/dev/null
  echo "✓ $4"
}
shot wide 1236 816 docs/window.png
shot compact 476 796 docs/compact.png
shot chat 476 796 docs/chat.png
shot split 1236 756 docs/split.png
shot read 516 518 docs/read.png
shot menu 616 306 docs/menu.png
