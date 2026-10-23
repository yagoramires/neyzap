<div align="center">

<img src="docs/icon.png" width="128" alt="Ícone do NeyZap">

# NeyZap

**WhatsApp com uma UI decente no Mac — várias contas e o Instagram junto.**

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-AppKit%20%2B%20WebKit-F05138?logo=swift&logoColor=white)
![Licença MIT](https://img.shields.io/badge/licen%C3%A7a-MIT-F5B000)

[**⬇️ Baixar a última versão**](https://github.com/yagoramires/neyzap/releases/latest)

</div>

---

O NeyZap é uma alternativa ao app nativo de merda da Meta: um WhatsApp com uma UI
decente, **várias contas** na mesma janela e **conexão com o Instagram**.

Por baixo é o **WhatsApp Web oficial** numa janela de verdade do Mac — nada de cliente
pirata nem automação. O risco para o seu número é o mesmo de usar o site no Safari.

<div align="center">
<img src="docs/notification.png" width="396" alt="Notificação do NeyZap com a foto do contato">
</div>

## ✨ Recursos

### 👥 Várias contas

- **Guias como num navegador** — uma guia por número, com inicial colorida, selo
  vermelho de não lidas e cinza de arquivadas. **+** (⌘T) conecta outro número pelo
  QR; duplo clique renomeia; **×** fecha.
- **Contas independentes** — a guia fora da tela continua recebendo e notificando,
  sem marcar nada como lido.
- **Lado a lado** (⌘\\) — todas as contas visíveis ao mesmo tempo.
- **Desativar guias** — clique direito na guia → *Desativar guia*: ela para de
  carregar (zero RAM e CPU), mas continua logada; *Ativar* volta de onde estava.
  Perfeito para o WhatsApp do trabalho no fim de semana.

### 📸 Instagram

- **Instagram numa guia** — no **+** escolha *Instagram* (ou ⇧⌘T): o site oficial,
  com login próprio, ao lado das guias do WhatsApp. ⌘[ volta uma página.
- **Sem vídeo tocando escondido** — pausa ao trocar de guia, fechar a janela ou
  esconder o app.

### 💬 Um WhatsApp melhor

- **Janela de qualquer tamanho** — abaixo de 760 px vira uma coluna por vez, como no
  celular, com botão de voltar (⌘[). Painéis, emojis, fotos e prévias se ajustam.
- **Marcar como lida num clique** — o ✓ à esquerda da foto marca a conversa como lida
  sem abrir (inclusive nas Arquivadas).
- **Clique direito como no navegador** — o menu do WhatsApp (Reagir, Responder,
  Copiar…) em qualquer parte da mensagem, inclusive em cima do texto.
- **Notificações com a foto do contato** — com o nome da guia, abrem a conversa no
  clique e não somem com o mouse em cima.
- **Mais limpo** — sem Meta AI, sem propaganda do app oficial, sem barras de rolagem.
- **Tema próprio** — `NeyZap → Editar tema` abre um CSS que aplica ao salvar.

### 🍎 Feito para o Mac

- **Integração** — contador no Dock, atalho global **⌃⌥Z**, *Sempre na frente*,
  abrir ao iniciar sessão, downloads em `~/Downloads`. Fechar a janela (⌘W) não
  desliga: as mensagens continuam chegando.
- **RAM sob controle** — guia escondida que passa de 1,5× o tamanho de recém-aberta
  (mínimo 1 GB) é recarregada sozinha. Guia em chamada não é tocada.
- **Sessões que ficam** — feche e abra o app à vontade, as contas continuam logadas.
  Uma guia de WhatsApp desativada há 7 dias conecta escondida por 15 min, para o
  aparelho não ser desconectado por inatividade.
- **Atualizações automáticas** — o app baixa a versão nova daqui do GitHub, confere a
  assinatura e se instala; é só escolher reiniciar agora ou depois.

## 📦 Instalação

1. Baixe o `.dmg` da [última versão](https://github.com/yagoramires/neyzap/releases/latest),
   abra e arraste o **NeyZap** para **Aplicativos**.
2. Na primeira vez o macOS bloqueia o app, porque ele não é assinado por uma conta
   de desenvolvedor da Apple. Abra **Ajustes do Sistema → Privacidade e Segurança**,
   role até o aviso sobre o NeyZap e clique em **Abrir Mesmo Assim**. Se o macOS
   disser que o app está danificado, rode no Terminal:
   ```sh
   xattr -dr com.apple.quarantine /Applications/NeyZap.app
   ```
3. Leia o QR code com o celular (**Aparelhos conectados → Conectar aparelho**).

Para compilar a partir do código, veja [docs/DESENVOLVIMENTO.md](docs/DESENVOLVIMENTO.md).

## ⌨️ Atalhos

| Atalho | Ação |
| --- | --- |
| ⌃⌥Z | Mostrar/esconder o NeyZap de qualquer lugar |
| ⌘1 … ⌘9 | Trocar de guia |
| ⌘T | Nova guia de WhatsApp (conectar outro número) |
| ⇧⌘T | Nova guia do Instagram |
| ⌘\\ | Guias lado a lado |
| ⌘[ | Voltar (lista de conversas / página anterior no Instagram) |
| ⌥⌘T | Sempre na frente |
| ⌘+ / ⌘− / ⌘0 | Zoom |
| ⌘R | Recarregar a guia |
| ⌘, | Editar tema (CSS) |
| ⌘W / ⌘Q | Esconder janela / encerrar |

## 🔒 Privacidade e segurança

- O código injetado no WhatsApp Web **só mexe na aparência** e lê a tela para
  notificações e contadores. Ele nunca envia mensagens, nunca automatiza ações e
  nunca acessa os módulos internos do WhatsApp. As únicas ações automáticas são
  clicar em **Ativar** no aviso "notificações desativadas" e ligar a
  **Sincronização em segundo plano** nas configurações (com a conta fora da tela) —
  preferências locais deste Mac. O ✓ de marcar como lida só age quando você clica
  nele, escolhendo "Marcar como lida" no menu da própria conversa.
- As guias do Instagram são o site puro: nada é injetado nelas.
- Tudo fica no seu Mac: sessões em armazenamentos separados por conta, nada é
  enviado para servidores além do próprio WhatsApp/Instagram. A verificação de
  atualização só consulta a lista de versões deste repositório e baixa o zip
  publicado aqui.
- A chave que protege as sessões fica num arquivo que só o seu usuário lê
  (`~/Library/Application Support/NeyZap/webcrypto.key`), e não no Chaveiro: sem
  conta de desenvolvedor da Apple, o Chaveiro pediria a senha a cada atualização do
  app. Quem tem acesso ao seu usuário do Mac consegue ler esse arquivo, como
  acontece com os dados de qualquer navegador.
- O log de depuração (`NeyZap → Logs de depuração`) registra eventos do app,
  nunca o conteúdo das conversas.
- Arquivos baixados das conversas ganham a marca de "baixado da internet", então o
  macOS avisa antes de abrir instaladores e apps. Links externos abrem no navegador.
- Para desenvolvimento existe um canal de depuração pelo terminal capaz de rodar
  código nas guias abertas. Ele vem **desligado** e, mesmo ligado, só aceita
  comandos com uma senha nova a cada abertura, guardada num arquivo que só o seu
  usuário lê (veja [docs/DESENVOLVIMENTO.md](docs/DESENVOLVIMENTO.md)).

## ⚠️ Limitações

- Chamadas de voz e vídeo seguem o que o WhatsApp Web oferece.
- O Instagram não notifica nem entra no contador do Dock.
- As notificações com foto são desenhadas pelo próprio app (o macOS só permite
  trocar o ícone pela foto em apps de desenvolvedor pago), então não ficam na
  Central de Notificações nem respeitam o modo Foco. Prefere as do sistema?
  `NeyZap → Usar notificações do sistema`.

---

<sub>Projeto pessoal, sem vínculo com o WhatsApp, o Instagram ou a Meta. WhatsApp, Instagram e seus logotipos são marcas registradas da Meta Platforms, Inc. O ícone do app (`Resources/AppIcon.icns`, `design/`, `docs/icon.png`) é derivado do logotipo do WhatsApp e **não** faz parte da licença MIT do código.</sub>
