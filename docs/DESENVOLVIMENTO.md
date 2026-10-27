# Desenvolvimento

## Compilar

Precisa só das Command Line Tools (`xcode-select --install`); não precisa do Xcode.

```sh
scripts/setup-signing.sh          # (uma vez) certificado local "NeyZap Local Signing"
scripts/install.sh                # versão final → /Applications/NeyZap.app (e abre)
scripts/install.sh --no-restart   # instala sem fechar o app aberto
scripts/restart.sh                # fecha o app do jeito normal (como ⌘Q) e abre de novo
scripts/build.sh [debug] [--run]  # só compila em build/NeyZap.app
swift scripts/make-icon.swift     # gera Resources/AppIcon.icns de design/icon-source.png
```

Assinar sempre com o mesmo certificado faz o macOS reconhecer as builds como o
mesmo app; sem o certificado, o `build.sh` para (use `ALLOW_ADHOC=1` para assinar
ad-hoc assim mesmo). A assinatura usa o runtime reforçado, com câmera e microfone
liberados em `Resources/NeyZap.entitlements`. Nunca abra duas cópias do app ao mesmo
tempo (o app recusa, e os scripts usam `open` sem `-n`): elas dividiriam os mesmos
dados das guias. A chave mestra do WebCrypto (que protege as chaves do WhatsApp no
IndexedDB) é entregue pelo próprio app ao WebKit e fica em
`~/Library/Application Support/NeyZap/webcrypto.key`, então o Chaveiro não pede
senha a cada build.

## Prints do README

`scripts/readme-prints.sh` gera `docs/window.png` e `docs/compact.png` a partir de
`design/readme-ui.html`, uma réplica da janela com contatos e mensagens inventados
(precisa do Google Chrome). Nunca use capturas da janela de verdade: elas mostram
conversas reais. Se a UI mudar, ajuste a réplica e rode o script de novo.

## Publicar uma versão

1. Suba `CFBundleShortVersionString` **e** `CFBundleVersion` em `Resources/Info.plist`.
2. `scripts/build.sh`, confira a assinatura (`codesign -dvv build/NeyZap.app` deve
   mostrar `Authority=NeyZap Local Signing`) e
   `ditto -c -k --keepParent build/NeyZap.app NeyZap-X.Y.Z.zip`.
3. `.dmg` para quem baixa na mão (janela de arrastar para Aplicativos):
   `S=$(mktemp -d) && ditto build/NeyZap.app "$S/NeyZap.app" && ln -s /Applications "$S/Aplicativos"
   && hdiutil create -volname NeyZap -srcfolder "$S" -format UDZO NeyZap-X.Y.Z.dmg`.
4. `gh release create vX.Y.Z NeyZap-X.Y.Z.zip NeyZap-X.Y.Z.dmg` — quem estiver numa versão anterior
   recebe sozinho: o app baixa o zip, só aceita um NeyZap da versão do release
   assinado com o mesmo certificado (requisito de assinatura do app aberto), troca o
   bundle e reinicia (ou instala ao fechar). O zip precisa conter `NeyZap.app` na raiz;
   o atualizador usa só ele, o `.dmg` é para a primeira instalação.

## Tema

O CSS do usuário fica em `~/Library/Application Support/NeyZap/user.css`
(menu NeyZap → Editar tema, ⌘,). Salvar o arquivo aplica na hora, sem reiniciar.

As classes do WhatsApp Web são ofuscadas e mudam com frequência. Por isso o
`inject.js` marca as colunas com atributos próprios, e é neles que o CSS deve se
apoiar:

| Seletor | O que é |
| --- | --- |
| `html[data-nz-compact]` | janela estreita (uma coluna por vez) |
| `html[data-nz-view="list"\|"chat"]` | coluna visível no modo compacto |
| `[data-nz="left"]` | trilho de navegação à esquerda |
| `[data-nz="side"]` | lista de conversas |
| `[data-nz="main"]` | conversa aberta |
| `[data-nz="drawer"]` | painel da direita (dados do contato, busca…) |
| `html[data-nz-drawer]` | painel da direita aberto |
| `[data-nz="overlay"]` | camadas absolutas (popups, avisos, painéis) |
| `[data-nz-sub="side"\|"rest"]` | colunas da camada dos painéis da esquerda |
| `#side`, `#main` | ids estáveis do próprio WhatsApp |

**Visualizar → Exportar estrutura da página** (⌥⇧⌘D) salva a árvore da página,
sem textos nem nomes, em `~/Library/Application Support/NeyZap/debug/`. Serve
para ajustar o layout quando o WhatsApp muda.

### Depuração pelo terminal

Desligada por padrão. **Ligada, ela permite rodar qualquer JavaScript nas guias
logadas** (ler conversas, agir na tela) — use só enquanto desenvolve e desligue
depois (`defaults write local.neyzap debugBridge -bool false`).

Com `defaults write local.neyzap debugBridge -bool true` e o app reaberto, ele cria
uma senha nova em `~/Library/Application Support/NeyZap/debug/token` (pasta 0700,
arquivo 0600; apagada ao encerrar ou com o canal desligado) e só aceita comandos que
começam com ela. O `scripts/debug.sh` grava senha + comando em `debug/command` e
avisa o app com uma notificação vazia — a senha não aparece na lista de processos
nem no canal de notificações, que outros programas podem escutar. Saída em `debug/`
(arquivos 0600; capturas e `eval.txt` são apagados quando o canal é desligado):

| Comando | Efeito |
| --- | --- |
| `dump` / `snap` | estrutura da página / captura das guias na tela |
| `size 420x700`, `front`, `side on\|off`, `select <guia>` | janela e guias |
| `hot <pasta>` | recarrega `layout.css` e `inject.js` da pasta, sem recompilar |
| `eval <expr>` / `evalin <guia> <expr>` | roda uma expressão JS na guia selecionada / numa guia específica |
| `click X Y`, `esc`, `reload`, `reset <guia>` | interação e sessão |

Nomes de guia podem ter espaços (`evalin WhatsApp 2 document.title`).

## Regras do `inject.js`

Para a conta não correr risco, o script injetado só mexe em apresentação e lê a
tela. Nunca envia mensagens, nunca automatiza ações e nunca acessa os módulos
internos do WhatsApp (`window.Store` e afins).

Única exceção: quando aparece o aviso "As notificações de mensagens estão
desativadas", o script clica no **Ativar** dele. Isso só liga a preferência local
de notificações do WhatsApp Web neste Mac (nada vai para o servidor) e fica
registrado no log de depuração. Do mesmo jeito, uma vez por dia e só com a conta
fora da tela, ele abre Configurações → Notificações e liga a **Sincronização em
segundo plano** se estiver desligada, voltando em seguida às conversas.

## Estrutura

```
Sources/NeyZap/
  AppDelegate.swift           menus (app e Dock), atalho global, badge, atualizações
  MainWindowController.swift  janela, guias (criar, renomear, fechar), lado a lado, fixar
  TabBar.swift                barra de guias no estilo navegador
  AccountSession.swift        WKWebView por conta, downloads, notificações, permissões
  NotificationBanner.swift    notificações com a foto do contato
  Notifier.swift              Central de Notificações (modo "notificações do sistema")
  UpdateChecker.swift         baixa, confere e instala versões novas dos releases
  Log.swift                   log de depuração (~/Library/Logs/NeyZap)
  WebCryptoKey.swift          chave mestra do WebCrypto fora do Chaveiro
  DebugBridge.swift           comandos de depuração vindos do terminal
  Accounts.swift · UserStyle.swift · HotKey.swift · Support.swift
Resources/
  inject.js                   roda dentro do WhatsApp Web (notificações, layout, filtros)
  layout.css                  CSS do layout responsivo
```
