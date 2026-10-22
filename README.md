<div align="center">

<img src="docs/icon.png" width="128" alt="Ícone do NeyZap">

# NeyZap

**WhatsApp do seu jeito no Mac — nativo, leve e com várias contas.**

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-AppKit%20%2B%20WebKit-F05138?logo=swift&logoColor=white)
![Licença MIT](https://img.shields.io/badge/licen%C3%A7a-MIT-F5B000)

</div>

---

O NeyZap é um app nativo de macOS que roda o **WhatsApp Web oficial** dentro de
uma janela de verdade: uma guia para cada número, notificações com a foto do contato,
layout que se adapta a qualquer tamanho de janela e integração com o Mac
(Dock, atalhos, login automático).

Nada de cliente pirata nem automação: cada conta é o WhatsApp Web da própria
Meta, então o risco para o seu número é o mesmo de usar o site no Safari.

<div align="center">
<img src="docs/notification.png" width="396" alt="Notificação do NeyZap com a foto do contato">
</div>

## ✨ Recursos

- **Guias como num navegador** — cada guia é um número de WhatsApp, com inicial
  colorida, selo vermelho de não lidas e cinza de arquivadas. **+** (⌘T) abre outra
  guia e mostra o QR para conectar mais um número; duplo clique renomeia; o **×**
  fecha. As guias funcionam de forma independente: a que está fora da tela continua
  recebendo e notificando, sem marcar nada como lido. Também dá para ver todas
  **lado a lado** (⌘\\).
- **Janela de qualquer tamanho** — abaixo de 760 px vira uma coluna por vez, como
  no celular, com botão de voltar (⌘[). Painéis, emojis, fotos e prévias de envio
  se ajustam à largura.
- **Marcar como lida num clique** — nas conversas não lidas (inclusive nas
  Arquivadas) aparece um ✓ à esquerda da foto: marca como lida sem abrir a conversa.
- **Clique direito como no navegador** — abre o menu do WhatsApp (Reagir, Responder,
  Copiar…) em qualquer parte da mensagem, inclusive em cima do texto.
- **Notificações com a foto do contato** — mostram o nome da guia em cima
  do nome, abrem a conversa no clique e não somem com o mouse em cima.
- **Mais limpo** — título NeyZap, sem Meta AI, sem propaganda do app oficial e sem barras
  de rolagem.
- **Integração com o Mac** — contador no Dock, atalho global **⌃⌥Z** para
  mostrar/esconder, *Sempre na frente* (⌥⌘T), abrir ao iniciar sessão, downloads
  em `~/Downloads`. Fechar a janela (⌘W) não desliga: as mensagens continuam
  chegando.
- **Sessões que ficam** — feche e abra o app à vontade, as contas continuam logadas.
- **Atualizações automáticas** — quando sai versão nova aqui no GitHub, o app baixa,
  confere a assinatura e se instala; é só escolher reiniciar agora ou depois.
- **Tema próprio** — `NeyZap → Editar tema` abre um CSS que aplica ao salvar.

## 📦 Instalação

1. Baixe o `.zip` da [última versão](https://github.com/yagoramires/neyzap/releases/latest)
   e arraste o **NeyZap.app** para **Aplicativos**.
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
| ⌘\\ | Guias lado a lado |
| ⌘[ | Voltar para a lista (janela estreita) |
| ⌥⌘T | Sempre na frente |
| ⌘T | Nova guia (conectar outro número) |
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
- Tudo fica no seu Mac: sessões em armazenamentos separados por conta, nada é
  enviado para servidores além do próprio WhatsApp. A verificação de atualização
  só consulta a lista de versões deste repositório e baixa o zip publicado aqui.
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
  usuário lê
  (veja [docs/DESENVOLVIMENTO.md](docs/DESENVOLVIMENTO.md)).

## ⚠️ Limitações

- Chamadas de voz e vídeo seguem o que o WhatsApp Web oferece.
- As notificações com foto são desenhadas pelo próprio app (o macOS só permite
  trocar o ícone pela foto em apps de desenvolvedor pago), então não ficam na
  Central de Notificações nem respeitam o modo Foco. Prefere as do sistema?
  `NeyZap → Usar notificações do sistema`.

---

<sub>Projeto pessoal, sem vínculo com o WhatsApp ou a Meta. WhatsApp e o logotipo do WhatsApp são marcas registradas da Meta Platforms, Inc. O ícone do app (`Resources/AppIcon.icns`, `design/`, `docs/icon.png`) é derivado desse logotipo e **não** faz parte da licença MIT do código.</sub>
