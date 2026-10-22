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
uma janela de verdade: abas para cada número, notificações com a foto do contato,
layout que se adapta a qualquer tamanho de janela e integração com o Mac
(Dock, atalhos, login automático).

Nada de cliente pirata nem automação: cada conta é o WhatsApp Web da própria
Meta, então o risco para o seu número é o mesmo de usar o site no Safari.

<div align="center">
<img src="docs/notification.png" width="396" alt="Notificação do NeyZap com a foto do contato">
</div>

## ✨ Recursos

- **Vários números ao mesmo tempo** — uma aba por conta (⌘1, ⌘2…), com selo
  vermelho de não lidas, ou todas **lado a lado** (⌘\\). Conecte outro número pelo
  menu do ícone no Dock.
- **Janela de qualquer tamanho** — abaixo de 760 px vira uma coluna por vez, como
  no celular, com botão de voltar (⌘[). Painéis, emojis, fotos e prévias de envio
  se ajustam à largura.
- **Notificações com a foto do contato** — mostram a conta (ex.: *Pessoal*) em cima
  do nome, abrem a conversa no clique e não somem com o mouse em cima.
- **Mais limpo** — título NeyZap, sem Meta AI, sem propaganda do app oficial, sem aviso de
  notificações e sem barras de rolagem.
- **Integração com o Mac** — contador no Dock, atalho global **⌃⌥Z** para
  mostrar/esconder, *Sempre na frente* (⌥⌘T), abrir ao iniciar sessão, downloads
  em `~/Downloads`. Fechar a janela (⌘W) não desliga: as mensagens continuam
  chegando.
- **Sessões que ficam** — feche e abra o app à vontade, as contas continuam logadas.
- **Atualizações** — o app avisa quando sai versão nova aqui no GitHub.
- **Tema próprio** — `NeyZap → Editar tema` abre um CSS que aplica ao salvar.

## 📦 Instalação

1. Baixe o `.zip` da [última versão](https://github.com/yagoramires/neyzap/releases/latest)
   e arraste o **NeyZap.app** para **Aplicativos**.
2. Na primeira vez, clique com o botão direito no app → **Abrir** (o app não é
   assinado por uma conta de desenvolvedor da Apple, então o macOS pede essa
   confirmação uma vez). Se ele disser que o app está danificado, rode:
   ```sh
   xattr -dr com.apple.quarantine /Applications/NeyZap.app
   ```
3. Leia o QR code com o celular (**Aparelhos conectados → Conectar aparelho**).

Para compilar a partir do código, veja [docs/DESENVOLVIMENTO.md](docs/DESENVOLVIMENTO.md).

## ⌨️ Atalhos

| Atalho | Ação |
| --- | --- |
| ⌃⌥Z | Mostrar/esconder o NeyZap de qualquer lugar |
| ⌘1 … ⌘9 | Trocar de conta |
| ⌘\\ | Contas lado a lado |
| ⌘[ | Voltar para a lista (janela estreita) |
| ⌥⌘T | Sempre na frente |
| ⌘⇧N | Conectar outro número |
| ⌘+ / ⌘− / ⌘0 | Zoom |
| ⌘W / ⌘Q | Esconder janela / encerrar |

## 🔒 Privacidade e segurança

- O código injetado no WhatsApp Web **só mexe na aparência** e lê a tela para
  notificações e contadores. Ele nunca envia mensagens, nunca automatiza ações e
  nunca acessa os módulos internos do WhatsApp.
- Tudo fica no seu Mac: sessões em armazenamentos separados por conta, nada é
  enviado para servidores além do próprio WhatsApp. A verificação de atualização
  só consulta a lista de versões deste repositório.
- O log de depuração (`NeyZap → Logs de depuração`) registra eventos do app,
  nunca o conteúdo das conversas.

## ⚠️ Limitações

- Chamadas de voz e vídeo seguem o que o WhatsApp Web oferece.
- As notificações com foto são desenhadas pelo próprio app (o macOS só permite
  trocar o ícone pela foto em apps de desenvolvedor pago), então não ficam na
  Central de Notificações nem respeitam o modo Foco. Prefere as do sistema?
  `NeyZap → Usar notificações do sistema`.

---

<sub>Projeto pessoal, sem vínculo com o WhatsApp ou a Meta. WhatsApp é marca registrada da Meta Platforms, Inc.</sub>
