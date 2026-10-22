# Desenvolvimento

## Compilar

Precisa só das Command Line Tools (`xcode-select --install`); não precisa do Xcode.

```sh
scripts/setup-signing.sh          # (uma vez) certificado local "NeyZap Local Signing"
scripts/install.sh                # versão final → /Applications/NeyZap.app (e abre)
scripts/install.sh --no-restart   # instala sem fechar o app aberto
scripts/build.sh [debug] [--run]  # só compila em build/NeyZap.app
swift scripts/make-icon.swift     # gera Resources/AppIcon.icns de design/icon-source.png
```

Assinar sempre com o mesmo certificado faz o macOS reconhecer as builds como o
mesmo app. A chave mestra do WebCrypto (que protege as chaves do WhatsApp no
IndexedDB) é entregue pelo próprio app ao WebKit e fica em
`~/Library/Application Support/NeyZap/webcrypto.key`, então o Chaveiro não pede
senha a cada build.

## Publicar uma versão

1. Suba `CFBundleShortVersionString` em `Resources/Info.plist`.
2. `scripts/build.sh` e `ditto -c -k --keepParent build/NeyZap.app NeyZap-X.Y.Z.zip`.
3. `gh release create vX.Y.Z NeyZap-X.Y.Z.zip` — o app avisa quem estiver numa versão anterior.

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

Desligada por padrão. Com `defaults write local.neyzap debugBridge -bool true`,
o `scripts/debug.sh` manda comandos para o app aberto (saída em `debug/`):

| Comando | Efeito |
| --- | --- |
| `dump` / `snap` | estrutura da página / captura de cada conta visível |
| `size 420x700`, `front`, `side on\|off`, `select <conta>` | janela e contas |
| `hot <pasta>` | recarrega `layout.css` e `inject.js` da pasta, sem recompilar |
| `eval <expr>` | avalia uma expressão de leitura na conta selecionada |
| `click X Y`, `esc`, `reload`, `reset <conta>` | interação e sessão |

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
  MainWindowController.swift  janela, abas de conta com selo, lado a lado, fixar
  AccountSession.swift        WKWebView por conta, downloads, notificações, permissões
  NotificationBanner.swift    notificações com a foto do contato
  Notifier.swift              Central de Notificações (modo "notificações do sistema")
  UpdateChecker.swift         procura versões novas nos releases do GitHub
  Log.swift                   log de depuração (~/Library/Logs/NeyZap)
  WebCryptoKey.swift          chave mestra do WebCrypto fora do Chaveiro
  DebugBridge.swift           comandos de depuração vindos do terminal
  Accounts.swift · UserStyle.swift · HotKey.swift · Support.swift
Resources/
  inject.js                   roda dentro do WhatsApp Web (notificações, layout, filtros)
  layout.css                  CSS do layout responsivo
```
