# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [0.3.1] - 2026-10-23

### Adicionado
- Desativar guias: clique direito na guia → **Desativar guia**. Ela para de carregar (zero RAM e CPU), mas continua logada; **Ativar** volta de onde estava.
- Uma guia de WhatsApp desativada há 7 dias conecta escondida por 15 min, para o aparelho não ser desconectado por inatividade.

### Corrigido
- O menu de clique direito das guias (Renomear, Limpar sessão, Desativar, Fechar) não abria.

## [0.3.0] - 2026-10-23

### Adicionado
- Instagram numa guia: no **+** escolha **Instagram** (ou `⇧⌘T`) para abrir o site oficial, com login próprio. `⌘[` volta uma página.
- O vídeo do Instagram pausa ao trocar de guia, fechar a janela ou esconder o app.
- A guia do Instagram não entra no contador de não lidas nem nas notificações.

## [0.2.6] - 2026-10-23

### Corrigido
- O botão ✓ de marcar como lida não abre mais a última conversa aberta quando a janela está estreita.

### Alterado
- O release passa a incluir um `.dmg` para instalar arrastando.

## [0.2.5] - 2026-10-23

### Adicionado
- RAM sob controle: uma guia escondida que passa de 1,5× o tamanho de recém-aberta (mínimo 1 GB) é recarregada sozinha. Guia em chamada não é tocada.

### Corrigido
- O X dos **Dados da mensagem** volta a fechar o painel com a janela estreita.

## [0.2.4] - 2026-10-22

### Adicionado
- Atualização automática: o NeyZap baixa o zip da versão nova, confere a assinatura e pergunta se você quer reiniciar agora ou depois.

### Corrigido
- Duplo clique na guia para renomear não dá mais zoom na janela.

## [0.2.2] - 2026-10-22

### Adicionado
- Marcar como lida num clique: o ✓ à esquerda da foto marca a conversa como lida sem abrir (inclusive nas Arquivadas).
- Clique direito como no navegador: o menu do WhatsApp (Reagir, Responder, Copiar…) em qualquer parte da mensagem.

### Corrigido
- As sessões não são apagadas se a lista de guias se perder: voltam como guia "Recuperada".
- A sincronização em segundo plano funciona com a janela estreita e roda no máximo uma vez por dia.
- Notificações: uma foto que demora a baixar não traz de volta um balão antigo. Se o macOS negar as notificações do sistema, o app volta para os balões próprios e avisa.
- Abrir o NeyZap quando ele já está aberto mostra a janela.

## [0.2.1] - 2026-10-22

### Segurança
- Canal de depuração protegido por senha e desligado por padrão.
- Arquivos baixados das conversas ganham a marca de "baixado da internet".
- Links externos sempre abrem no navegador; câmera e microfone só para o WhatsApp Web.
- App assinado com runtime reforçado.

### Corrigido
- Fechar uma guia não troca mais a seleção para outra conta, e clique direito numa guia não a abre mais.
- Depois de renomear, o foco volta para o WhatsApp.

## [0.2.0] - 2026-10-22

### Adicionado
- Guias no estilo navegador: cada número é uma guia com inicial colorida e selos de não lidas e arquivadas.
- **+** (`⌘T`) abre uma guia nova para conectar outro número; duplo clique renomeia; **×** fecha, com confirmação.
- Clique direito na guia: renomear, limpar sessão, fechar.

## [0.1.9] - 2026-10-22

### Alterado
- Sincronização em segundo plano ligada por padrão: uma vez por dia, com a conta fora da tela, o NeyZap confere a opção em Configurações → Notificações e liga se estiver desligada.
- Conta que abre escondida recebe os ajustes de layout desde o início.

## [0.1.8] - 2026-10-22

### Alterado
- Contas independentes de fato: a conta fora da tela fica numa janela invisível e sem foco, não lê mais as mensagens sozinha e continua notificando. O selo de não lidas fica até você abrir a conversa.

## [0.1.7] - 2026-10-22

### Corrigido
- Volta o selo cinza de conversas arquivadas não lidas nas abas (tinha parado na 0.1.3).
- Volta a troca do título para NeyZap quando o WhatsApp usa texto em vez do logotipo.
- Uma falha em uma das tarefas do app não derruba mais as outras.

## [0.1.6] - 2026-10-22

### Corrigido
- A conta fora da tela não marca mais mensagens como lidas quando elas chegam na conversa que estava aberta nela.
- Menos consumo: a conta escondida volta ao modo econômico, mas continua recebendo e notificando.

## [0.1.5] - 2026-10-22

### Alterado
- Contas independentes: a conta que não está na tela (ou com a janela fechada) continua recebendo e notificando na hora.

## [0.1.4] - 2026-10-22

### Adicionado
- As notificações do WhatsApp se ativam sozinhas: quando aparece o aviso de notificações desativadas, o NeyZap clica em **Ativar**.

## [0.1.3] - 2026-10-22

### Alterado
- Volta a mostrar o aviso de notificações desativadas, que é por onde o WhatsApp volta a notificar depois de logar de novo uma conta.

## [0.1.2] - 2026-10-22

### Adicionado
- Selo cinza com ícone de arquivo nas abas para conversas arquivadas não lidas; o menu do Dock mostra as duas contagens.

## [0.1.1] - 2026-10-22

### Alterado
- Título NeyZap no topo da lista de conversas e sem o aviso de notificações desativadas.

## [0.1.0] - 2026-10-22

### Adicionado
- Primeira versão: várias contas do WhatsApp em abas (com selo de não lidas) ou lado a lado.
- Layout responsivo: abaixo de 760 px vira uma coluna por vez, como no celular.
- Notificações com a foto do contato e a conta em cima do nome.
- Sem Meta AI, sem propaganda do app oficial e sem barras de rolagem.
- Menu do Dock para trocar de conta e conectar outro número.
- Verificação de atualizações e log de depuração.
