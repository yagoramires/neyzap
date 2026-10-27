// NeyZap — roda dentro do WhatsApp Web (frame principal, no início do documento).
// Regra de ouro: este script só mexe em apresentação e lê a tela. Nunca envia
// mensagens, nunca automatiza ações e nunca toca nos módulos internos do WhatsApp.
(() => {
  'use strict';
  if (window.__neyzap) return;

  const cfg = window.__neyzapConfig || {};
  try { delete window.__neyzapConfig; } catch (_) {} // não deixa a configuração exposta à página
  const root = document.documentElement;
  const post = (msg) => {
    try { window.webkit.messageHandlers.neyzap.postMessage(msg); } catch (_) {}
  };

  // ---------------------------------------------------------------------------
  // Notificações: troca a API web por notificações nativas do macOS.
  // ---------------------------------------------------------------------------
  const live = new Map();
  let seq = 0;
  // Ids únicos por carga da página: um clique numa notificação antiga não abre outra conversa.
  const loadId = Math.random().toString(36).slice(2, 8);

  function iconToDataURL(url) {
    if (url.startsWith('data:')) return Promise.resolve(url);
    return fetch(url).then((r) => r.blob()).then((blob) => new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result));
      reader.onerror = reject;
      reader.readAsDataURL(blob);
    }));
  }

  class NeyZapNotification extends EventTarget {
    constructor(title, options = {}) {
      super();
      this.id = `${loadId}-${++seq}`;
      this.title = String(title ?? '');
      this.body = options.body ? String(options.body) : '';
      this.tag = options.tag ? String(options.tag) : '';
      this.icon = options.icon || '';
      this.data = options.data ?? null;
      this.silent = !!options.silent;
      this.onclick = this.onclose = this.onshow = this.onerror = null;
      live.set(this.id, this);
      if (live.size > 200) { // as mais antigas saem (e o balão delas também)
        const oldest = live.keys().next().value;
        live.delete(oldest);
        post({ type: 'notifyClose', id: oldest });
      }
      const send = (icon) => post({ type: 'notify', id: this.id, title: this.title, body: this.body, tag: this.tag, silent: this.silent, icon });
      // A foto do contato costuma vir como blob:, que só esta página consegue ler:
      // vira data URL antes de ir para o app. URLs https o app baixa sozinho.
      if (/^(blob|data):/.test(this.icon)) {
        iconToDataURL(this.icon).then(send, () => send(''));
      } else {
        send(String(this.icon || ''));
      }
      setTimeout(() => this._fire('show'), 0);
    }

    close() {
      if (!live.delete(this.id)) return;
      post({ type: 'notifyClose', id: this.id });
      this._fire('close');
    }

    _fire(type) {
      const event = new Event(type);
      const handler = this['on' + type];
      if (typeof handler === 'function') {
        try { handler.call(this, event); } catch (e) { console.error(e); }
      }
      this.dispatchEvent(event);
    }

    static get permission() { return 'granted'; }

    static requestPermission(callback) {
      if (typeof callback === 'function') callback('granted');
      return Promise.resolve('granted');
    }
  }

  try {
    Object.defineProperty(window, 'Notification', { value: NeyZapNotification, configurable: true, writable: true });
  } catch (_) {
    window.Notification = NeyZapNotification;
  }

  if (navigator.permissions && navigator.permissions.query) {
    const query = navigator.permissions.query.bind(navigator.permissions);
    navigator.permissions.query = (desc) => (desc && desc.name === 'notifications')
      ? Promise.resolve({ name: 'notifications', state: 'granted', onchange: null, addEventListener() {}, removeEventListener() {} })
      : query(desc);
  }

  function notificationClicked(id) {
    const n = live.get(id);
    if (!n) return;
    window.focus();
    n._fire('click');
  }

  // ---------------------------------------------------------------------------
  // Sons da interface (notificação etc.): tocados por um <audio>, fazem o macOS
  // tratar o app como "Tocando agora" (controle de mídia na barra de menus). Os
  // sons estáticos do WhatsApp passam a tocar por Web Audio, que não registra
  // isso. Áudios de conversa (blob:/mmg) continuam no <audio> normal.
  // ---------------------------------------------------------------------------
  const UI_SOUND = /^https:\/\/static\.whatsapp\.net\//;
  const nativePlay = HTMLMediaElement.prototype.play;
  const soundBuffers = new Map();
  let audioContext = null;

  HTMLMediaElement.prototype.play = function play(...args) {
    const src = this.currentSrc || this.src || '';
    if (!(this instanceof HTMLAudioElement) || !UI_SOUND.test(src)) return nativePlay.apply(this, args);
    try {
      audioContext = audioContext || new AudioContext();
      let buffer = soundBuffers.get(src);
      if (!buffer) {
        buffer = fetch(src).then((r) => r.arrayBuffer()).then((data) => audioContext.decodeAudioData(data));
        buffer.catch(() => soundBuffers.delete(src));
        soundBuffers.set(src, buffer);
      }
      const volume = this.muted ? 0 : this.volume;
      buffer.then((decoded) => {
        if (audioContext.state === 'suspended') audioContext.resume();
        const source = audioContext.createBufferSource();
        const gain = audioContext.createGain();
        source.buffer = decoded;
        gain.gain.value = volume;
        source.connect(gain).connect(audioContext.destination);
        source.onended = () => this.dispatchEvent(new Event('ended'));
        source.start();
      }).catch(() => nativePlay.apply(this, args));
      this.dispatchEvent(new Event('play'));
      return Promise.resolve();
    } catch (_) {
      return nativePlay.apply(this, args);
    }
  };

  // ---------------------------------------------------------------------------
  // Estilos
  // ---------------------------------------------------------------------------
  function setStyle(id, css) {
    let el = document.getElementById(id);
    if (!el) {
      el = document.createElement('style');
      el.id = id;
      (document.head || root).appendChild(el);
    }
    // Mantém a ordem: base primeiro, CSS do usuário por último.
    if (id === 'nz-base') {
      const user = document.getElementById('nz-user');
      if (user) user.before(el);
    }
    el.textContent = css || '';
  }

  // ---------------------------------------------------------------------------
  // Layout responsivo
  //
  // As classes do WhatsApp Web são ofuscadas e mudam a cada deploy, então o
  // layout se ancora só em #side (lista de conversas) e #main (conversa aberta)
  // e marca as colunas com atributos próprios (data-nz). O CSS mira nesses
  // atributos, nunca nas classes deles.
  // ---------------------------------------------------------------------------
  const compactQuery = window.matchMedia(`(max-width: ${cfg.compactWidth || 760}px)`);
  let panes = null;     // container das colunas
  let sidePane = null;  // coluna que contém #side
  let hadMain = false;

  function setView(view) {
    if (root.dataset.nzView === view) return;
    root.dataset.nzView = view;
    updateBackButton();
  }

  function applyCompact() {
    overlayCache = new WeakMap(); // a posição das camadas muda com a largura
    if (compactQuery.matches) root.dataset.nzCompact = '';
    else delete root.dataset.nzCompact;
    // O painel de emojis foi desenhado para 560 px; abaixo disso ele encolhe inteiro.
    root.style.setProperty('--nz-expr-zoom', String(Math.min(1, (window.innerWidth - 16) / 560)));
    updateBackButton();
  }

  // Acha o container cujas colunas são [trilho?] [lista] [conversa] [painel lateral?].
  function findPanes(side) {
    const main = document.getElementById('main');
    if (main) {
      let a = side;
      while (a.parentElement && !a.parentElement.contains(main)) a = a.parentElement;
      if (a.parentElement) return { container: a.parentElement, side: a };
    }
    // Sem conversa aberta: sobe a partir de #side até achar um irmão grande à
    // direita (o placeholder da conversa). Mede sem o modo compacto ativo.
    const wasCompact = 'nzCompact' in root.dataset;
    if (wasCompact) delete root.dataset.nzCompact;
    try {
      let a = side;
      while (a.parentElement && a.parentElement !== document.body) {
        const r = a.getBoundingClientRect();
        for (const c of a.parentElement.children) {
          if (c === a) continue;
          const cr = c.getBoundingClientRect();
          if (cr.left >= r.right - 2 && cr.width > 200) return { container: a.parentElement, side: a };
        }
        a = a.parentElement;
      }
    } finally {
      if (wasCompact) root.dataset.nzCompact = '';
    }
    return null;
  }

  function tagPanes() {
    const side = document.getElementById('side');
    if (!side) return;
    const main = document.getElementById('main');
    const stale = !panes || !panes.isConnected || !sidePane || !sidePane.contains(side) || (main && !panes.contains(main));
    if (stale) {
      const found = findPanes(side);
      if (!found) return;
      if (panes && panes !== found.container) clearTags();
      panes = found.container;
      sidePane = found.side;
    }

    panes.setAttribute('data-nz', 'panes');
    // Camadas com position absolute/fixed (popups, avisos, painel de tela
    // cheia) ficam fora da classificação; só as colunas do fluxo viram
    // trilho/lista/conversa/painel.
    const kids = [...panes.children];
    const inFlow = kids.filter((c) => c === sidePane || !isOverlay(c));
    const sideIndex = inFlow.indexOf(sidePane);
    const mainPane = inFlow.find((c) => main && c.contains(main)) || inFlow[sideIndex + 1];
    kids.forEach((c) => {
      const i = inFlow.indexOf(c);
      let role = 'overlay';
      if (c === sidePane) role = 'side';
      else if (i < 0) role = 'overlay';
      else if (i < sideIndex) role = 'left';
      else if (c === mainPane) role = 'main';
      else role = 'drawer';
      if (c.getAttribute('data-nz') !== role) c.setAttribute('data-nz', role);
      // Camada dos painéis da esquerda (Configurações, Nova conversa, Perfil…):
      // a 1ª coluna imita a largura da lista; a 2ª é o resto da tela.
      if (role === 'overlay' && isPanelsLayer(c)) {
        [...c.children].forEach((k, j) => {
          const sub = j === 0 ? 'side' : 'rest';
          if (k.getAttribute('data-nz-sub') !== sub) k.setAttribute('data-nz-sub', sub);
        });
      }
    });

    // Painel da direita (dados do contato, busca na conversa…) aberto? Fechado,
    // ele só tem um <span> vazio.
    const drawerOpen = kids.some((c) => c.getAttribute('data-testid') === 'drawer-right' && c.children.length
      && !(c.children.length === 1 && c.firstElementChild.tagName === 'SPAN' && !c.firstElementChild.firstChild));
    if (drawerOpen) root.dataset.nzDrawer = '';
    else delete root.dataset.nzDrawer;

    // Em larguras médias o WhatsApp sobrepõe o painel à conversa, mas deixa uma
    // faixa dela aparecendo; o CSS usa esta posição para cobrir a coluna inteira.
    const openDrawer = drawerOpen && kids.find((c) => c.getAttribute('data-testid') === 'drawer-right');
    const overlaid = !!openDrawer && !('nzCompact' in root.dataset) && getComputedStyle(openDrawer).position === 'absolute';
    if (overlaid) {
      root.dataset.nzDrawerOver = '';
      root.style.setProperty('--nz-main-left', `${Math.round(mainPane.getBoundingClientRect().left)}px`);
    } else {
      delete root.dataset.nzDrawerOver;
    }

    // Coluna da conversa estreita (janela estreita ou lista larga ao lado): o CSS tira
    // o respiro de ~60 px que o WhatsApp deixa de cada lado das mensagens.
    if (mainPane && mainPane.getBoundingClientRect().width < 600) root.dataset.nzNarrowChat = '';
    else delete root.dataset.nzNarrowChat;

    for (let a = panes.parentElement; a && a !== document.body; a = a.parentElement) {
      if (!a.hasAttribute('data-nz-anc')) a.setAttribute('data-nz-anc', '');
    }
  }

  // Decide uma vez por elemento, sem os nossos atributos: o próprio CSS do modo
  // compacto põe colunas em position:fixed, o que não pode virar "camada".
  let overlayCache = new WeakMap();
  // Camada dos painéis da esquerda (Configurações, Nova conversa, prévia de mídia):
  // flex em linha, com a 1ª coluna alinhada à lista. Identificada uma vez e guardada,
  // porque o próprio CSS do modo compacto mexe na geometria dela depois.
  const panelsLayers = new WeakSet();
  function isPanelsLayer(el) {
    if (panelsLayers.has(el)) return true;
    if (el.children.length < 2 || getComputedStyle(el).flexDirection !== 'row' || !sidePane) return false;
    if ('nzCompact' in root.dataset && root.dataset.nzView === 'chat') return false;
    const first = el.children[0].getBoundingClientRect();
    const side = sidePane.getBoundingClientRect();
    if (Math.abs(first.left - side.left) > 4) return false;
    panelsLayers.add(el);
    return true;
  }

  function isOverlay(el) {
    if (!overlayCache.has(el)) {
      const tag = el.getAttribute('data-nz');
      if (tag) el.removeAttribute('data-nz');
      overlayCache.set(el, /^(absolute|fixed)$/.test(getComputedStyle(el).position));
      if (tag) el.setAttribute('data-nz', tag);
    }
    return overlayCache.get(el);
  }

  function clearTags() {
    document.querySelectorAll('[data-nz],[data-nz-anc],[data-nz-sub]').forEach((el) => {
      el.removeAttribute('data-nz');
      el.removeAttribute('data-nz-anc');
      el.removeAttribute('data-nz-sub');
    });
  }

  function tick() {
    tagPanes();
    const hasMain = !!document.getElementById('main');
    if (hasMain && !hadMain) setView('chat');
    if (!hasMain && hadMain) setView('list');
    hadMain = hasMain;
    updateBackButton();
    try { updateReadButtons(); } catch (e) { post({ type: 'log', message: `erro em updateReadButtons: ${e}` }); }
  }

  let scheduled = false;
  function schedule() {
    if (scheduled) return;
    scheduled = true;
    // Página escondida não recebe requestAnimationFrame: usa temporizador.
    const run = () => { scheduled = false; tick(); };
    if (document.visibilityState === 'visible') requestAnimationFrame(run);
    else setTimeout(run, 100);
    schedulePromoScan();
  }

  // ---------------------------------------------------------------------------
  // Propaganda do app para Mac/Windows ("Baixe o WhatsApp para Mac"): aparece de
  // vez em quando acima da lista ou no lugar da conversa. Não tem id estável,
  // então é achada pelo texto e marcada com data-nz-hide (o CSS esconde).
  // Mensagens e prévias de conversa nunca são tocadas.
  // ---------------------------------------------------------------------------
  const PROMO = /(baixe|baixar|download|get)\b.{0,30}whatsapp.{0,20}\b(para|for)\s+(mac|windows)/i;
  // Tela vazia (nenhuma conversa aberta): cartão da App Store e atalho da Meta AI.
  // O texto dos botões vem com o nome do ícone na frente ("wds-ic-logo-meta-ai-colorPerguntar à Meta AI").
  const EMPTY_PROMO = /(app store|meta ai)$/i;
  let promoTimer = 0;

  function schedulePromoScan() {
    if (promoTimer) return;
    promoTimer = setTimeout(() => { promoTimer = 0; housekeeping(); }, 1500);
  }

  // Aviso "As notificações de mensagens estão desativadas": depois de logar de
  // novo, o WhatsApp deixa a preferência local de notificações desligada até
  // alguém clicar em "Ativar". Única ação automática do script: clica nesse
  // botão (só muda essa preferência deste Mac; nada vai para o servidor).
  const NOTIFICATIONS_OFF = /notifica[çc][õo]es de mensagens est[ãa]o desativadas|message notifications are off/i;
  const clickedEnable = new WeakSet();
  function enableNotifications() {
    const bar = document.querySelector('[data-testid="chat-butterbar"]');
    if (!bar) return;
    for (const box of bar.children) {
      if (!NOTIFICATIONS_OFF.test(box.textContent)) continue;
      const label = [...box.querySelectorAll('*')].find((e) => e.childElementCount === 0 && /^(ativar|turn on)$/i.test(e.textContent.trim()));
      const target = label && (label.closest('button, [role="button"], a') || label);
      if (!target || clickedEnable.has(target)) continue;
      clickedEnable.add(target);
      target.click();
      post({ type: 'log', message: 'notificações do WhatsApp estavam desligadas: ativadas automaticamente' });
    }
  }

  // Não lidas arquivadas: o título da página só conta as conversas normais; o
  // número das arquivadas aparece na linha "Arquivadas" da lista (só leitura).
  let lastArchived = -1;
  function reportArchived() {
    const row = document.querySelector('[data-testid="chatlist-panel-archived-button"]');
    let count = 0;
    if (row) {
      const digits = [...row.querySelectorAll('*')].find((e) => e.childElementCount === 0 && /^\d+$/.test(e.textContent.trim()));
      count = digits ? parseInt(digits.textContent.trim(), 10) : 0;
    }
    if (count !== lastArchived) {
      lastArchived = count;
      post({ type: 'archived', count });
    }
  }

  // Título "WhatsApp" no topo da lista vira "NeyZap" quando é texto (quando é o
  // logotipo em SVG, o CSS troca). Contatos e mensagens nunca são tocados.
  function renameTitle() {
    const side = document.querySelector('[data-nz="side"]');
    if (!side) return;
    const top = side.getBoundingClientRect().top;
    const walker = document.createTreeWalker(side, NodeFilter.SHOW_TEXT);
    for (let n = walker.nextNode(); n; n = walker.nextNode()) {
      const text = n.data.trim();
      if (text !== 'WhatsApp' && text !== 'WhatsApp Business') continue;
      const el = n.parentElement;
      if (!el || el.closest('#pane-side') || el.getBoundingClientRect().top - top > 80) continue;
      n.data = n.data.replace(text, 'NeyZap');
    }
  }

  // "Sincronização em segundo plano" (Configurações → Notificações) ligada por
  // padrão: com a conta fora da tela, abre a tela de configurações, liga a opção
  // se estiver desligada e volta às conversas. No máximo uma vez por dia por conta;
  // para na hora se a conta voltar para a tela. Só muda essa preferência local.
  const BG_SYNC = /sincroniza[çc][ãa]o em segundo plano|background sync/i;
  let bgSyncRunning = false;
  let bgSyncLast = cfg.bgSyncCheckedAt || 0; // última tentativa (ms), dando certo ou não
  const bgSyncDue = () => Date.now() - bgSyncLast >= 24 * 3600 * 1000;
  const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const hiddenNow = () => document.visibilityState !== 'visible';
  const railButton = (labels) => [...document.querySelectorAll('header button[aria-label], [data-nz="left"] button')]
    .find((b) => labels.includes(b.getAttribute('aria-label')));
  // Painéis da esquerda (configurações), fora da lista de conversas e da conversa.
  const clickable = (el) => {
    for (let c = el, i = 0; c && i < 8; c = c.parentElement, i++) {
      if (c.tagName === 'BUTTON' || c.getAttribute('role') === 'button' || c.getAttribute('tabindex') === '0') return c;
    }
    return el;
  };
  // Texto visível nos painéis da esquerda (configurações), sem entrar na lista de
  // conversas, na conversa nem no painel da direita (onde nomes de contatos e
  // mensagens poderiam coincidir).
  const PANEL_SKIP = '#pane-side, #main, [data-testid="drawer-right"]';
  function findPanelText(re) {
    const start = document.getElementById('app') || document.body;
    const walker = document.createTreeWalker(start, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, {
      acceptNode: (n) => n.nodeType === Node.ELEMENT_NODE
        ? (n.matches(PANEL_SKIP) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_SKIP)
        : (re.test(n.data.trim()) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP),
    });
    for (let n = walker.nextNode(); n; n = walker.nextNode()) {
      const el = n.parentElement;
      if (el && el.getBoundingClientRect().width > 0) return el;
    }
    return null;
  }

  async function ensureBackgroundSync() {
    if (!bgSyncDue() || bgSyncRunning || !hiddenNow() || !document.getElementById('side')) return;
    bgSyncRunning = true;
    bgSyncLast = Date.now(); // uma tentativa por dia, dando certo ou não (sem loop se a tela mudar)
    let opened = false;
    let enabled = false;
    // No modo compacto com uma conversa aberta, a coluna das configurações tem
    // largura zero e nada nela seria achado: mostra a lista enquanto isso.
    const previousView = root.dataset.nzView;
    setView('list');
    try {
      tick();
      const settings = railButton(['Configurações', 'Settings']) || railButton(['Você', 'You']);
      if (!settings) return;
      settings.click();
      opened = true;
      await wait(1200);
      if (!hiddenNow()) return;
      const item = findPanelText(/^(notificações|notifications)$/i);
      if (!item) return;
      clickable(item).click();
      await wait(1200);
      if (!hiddenNow()) return;
      // O interruptor é o único dentro do menor bloco que contém o texto da opção.
      const label = findPanelText(BG_SYNC);
      let toggle = null;
      // Sobe pouco: num bloco grande demais o interruptor achado seria de outra opção.
      for (let el = label, depth = 0; el && !toggle && depth < 6 && el.textContent.length <= 300; el = el.parentElement, depth++) {
        const switches = el.querySelectorAll('input[role="switch"], input[type="checkbox"]');
        if (switches.length === 1) toggle = switches[0];
        else if (switches.length > 1) break;
      }
      if (!toggle) return;
      if (!toggle.checked) {
        toggle.click();
        await wait(500);
        post({ type: 'log', message: 'sincronização em segundo plano estava desligada: ligada automaticamente' });
      }
      enabled = toggle.checked;
    } finally {
      bgSyncRunning = false;
      post({ type: 'bgsync', ok: enabled });
      if (opened) railButton(['Conversas', 'Chats'])?.click(); // volta às conversas só se abriu as configurações
      if (previousView) setView(previousView);
    }
  }

  // Tarefas periódicas: cada uma isolada, para uma falha não derrubar as outras.
  function housekeeping() {
    if (bgSyncDue() && !bgSyncRunning && hiddenNow()) ensureBackgroundSync().catch((e) => post({ type: 'log', message: `erro em ensureBackgroundSync: ${e}` }));
    for (const task of [enableNotifications, reportArchived, renameTitle, hidePromos]) {
      try { task(); } catch (e) { post({ type: 'log', message: `erro em ${task.name}: ${e}` }); }
    }
  }

  function hidePromos() {
    // Marcações que não batem mais (o WhatsApp reaproveita elementos) são desfeitas.
    document.querySelectorAll('[data-nz-hide]').forEach((el) => {
      if (!PROMO.test(el.textContent) && !EMPTY_PROMO.test(el.textContent.trim())) el.removeAttribute('data-nz-hide');
    });
    const tooBig = (el) => el.textContent.length > 150 || !!el.querySelector('#pane-side, [role="row"], [role="listitem"]');
    const roots = [document.querySelector('[data-nz="side"]'), document.querySelector('[data-nz="main"]')].filter(Boolean);
    for (const r of roots) {
      // Não entra na conversa aberta, na lista de conversas nem no que já está escondido.
      const walker = document.createTreeWalker(r, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, {
        acceptNode: (n) => n.nodeType === Node.ELEMENT_NODE
          ? (n.matches('#main, #pane-side, [data-nz-hide]') ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_SKIP)
          : (/mac|windows/i.test(n.data) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP),
      });
      for (let n = walker.nextNode(); n; n = walker.nextNode()) {
        let el = n.parentElement;
        while (el && el !== r && !PROMO.test(el.textContent) && !tooBig(el)) el = el.parentElement;
        if (!el || el === r || tooBig(el) || !PROMO.test(el.textContent)) continue;
        // Sobe enquanto o pai ainda for só o banner (texto curto, caixa baixa).
        while (el.parentElement && el.parentElement !== r && !tooBig(el.parentElement)
          && el.parentElement.textContent.length < 120 && el.parentElement.getBoundingClientRect().height < 120) el = el.parentElement;
        el.setAttribute('data-nz-hide', '');
      }
    }
    const main = document.querySelector('[data-nz="main"]');
    if (main && !main.querySelector('#main')) {
      for (const b of main.querySelectorAll('button')) {
        if (!EMPTY_PROMO.test(b.textContent.trim())) continue;
        // Sobe até o cartão inteiro (ilustração + botão), parando antes dos outros atalhos.
        let el = b;
        while (el.parentElement && el.parentElement !== main && el.parentElement.querySelectorAll('button').length === 1) el = el.parentElement;
        el.setAttribute('data-nz-hide', '');
      }
    }
  }

  // Foco decide a coluna visível no modo compacto: abrir uma conversa foca o
  // campo de mensagem (#main); buscar ou navegar na lista foca a lista (#side).
  document.addEventListener('focusin', (e) => {
    const t = e.target;
    if (!(t instanceof Element)) return;
    if (t.closest('#main')) setView('chat');
    else if (sidePane && sidePane.contains(t)) setView('list');
  }, true);

  const chatTitle = () => document.querySelector('#main header [data-testid="conversation-info-header-chat-title"]')?.textContent || null;
  document.addEventListener('click', (e) => {
    const t = e.target;
    if (!(t instanceof Element) || !t.closest('#pane-side [role="row"], #pane-side [role="listitem"]')
      || t.closest('[data-testid="chatlist-panel-archived-button"], .nz-read')) return;
    const before = chatTitle();
    const fromList = root.dataset.nzView === 'list';
    setTimeout(() => {
      // Mesma conversa de novo (canal só de leitura, sem campo para focar) também volta para ela.
      const after = chatTitle();
      if (after && (after !== before || fromList)) setView('chat');
    }, 400);
  }, true);

  // Clique direito: no Mac o WebKit seleciona a palavra sob o mouse antes do evento
  // e, vendo texto selecionado, o WhatsApp deixa o menu do sistema (para copiar) em
  // vez do menu dele (Reagir, Responder…). Seleção criada pelo próprio clique é
  // desfeita antes de o WhatsApp olhar; texto selecionado de propósito continua
  // abrindo o menu de copiar.
  let selectedBeforeRightClick = false;
  const hasSelection = () => String(getSelection() || '').length > 0;
  window.addEventListener('mousedown', (e) => {
    if (e.button === 2 || (e.button === 0 && e.ctrlKey)) selectedBeforeRightClick = hasSelection();
  }, true);
  window.addEventListener('contextmenu', (e) => {
    const t = e.target;
    if (selectedBeforeRightClick || !(t instanceof Element) || !hasSelection()) return;
    if (t.closest('a[href], [contenteditable="true"], input, textarea')) return;
    if (t.closest('#main [data-id], #pane-side')) getSelection().removeAllRanges();
  }, true);

  // ---------------------------------------------------------------------------
  // Botão "marcar como lida" à esquerda da foto nas conversas não lidas (lista
  // principal e Arquivadas). O clique do usuário abre o menu da própria conversa (o
  // mesmo do clique direito) e escolhe "Marcar como lida", como faria à mão, sem
  // abrir a conversa. O botão mora na linha (rola junto); o CSS abre o espaço.
  // ---------------------------------------------------------------------------
  const UNREAD_LABEL = /n[ãa]o lida|unread/i;
  const MARK_READ = /marcar como lida|mark as read/i;
  const READ_ICON = '<svg viewBox="0 0 24 24" width="15" height="15" aria-hidden="true"><path d="M4.5 12.5l4.5 4.5 10.5-10.5" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  const CHAT_ROWS = ':is(#pane-side, [data-testid="archived-chatlist"]) :is([role="row"], [role="listitem"])';

  const rowIsUnread = (row) => !row.querySelector('[data-testid="chatlist-panel-archived-button"]')
    && [...row.querySelectorAll('span[aria-label]')].some((s) => UNREAD_LABEL.test(s.getAttribute('aria-label')));

  function updateReadButtons() {
    if (document.visibilityState !== 'visible') return;
    // O WhatsApp reaproveita as linhas: botão em linha que não está mais não lida sai.
    document.querySelectorAll('.nz-read').forEach((b) => {
      const row = b.closest('[role="row"], [role="listitem"]');
      if (!row || !rowIsUnread(row)) b.remove();
    });
    for (const row of document.querySelectorAll(CHAT_ROWS)) {
      const cell = row.querySelector('[data-testid="cell-frame-container"]');
      if (!cell || cell.querySelector(':scope > .nz-read') || !rowIsUnread(row)) continue;
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'nz-read';
      button.title = 'Marcar como lida';
      button.setAttribute('aria-label', 'Marcar como lida');
      button.innerHTML = READ_ICON;
      // Nada do clique chega à linha (ela abriria a conversa no mousedown).
      for (const type of ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'dblclick', 'contextmenu']) {
        button.addEventListener(type, (e) => e.stopPropagation());
      }
      button.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        const current = button.closest('[role="row"], [role="listitem"]');
        if (current) markRead(current, button);
      });
      cell.appendChild(button);
    }
  }

  async function markRead(row, button) {
    const title = row.querySelector('[data-testid="cell-frame-title"] span, [data-testid="cell-frame-title"]');
    if (!title || button.disabled) return;
    button.disabled = true;
    root.dataset.nzMarking = ''; // o menu abre invisível (CSS)
    try {
      const r = title.getBoundingClientRect();
      title.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true, button: 2, clientX: r.left + 5, clientY: r.top + 5, view: window }));
      let item = null;
      for (let i = 0; i < 30 && !item; i++) {
        await wait(50);
        item = [...document.querySelectorAll('[role="menu"] [role="menuitem"]')]
          .find((el) => MARK_READ.test(el.textContent) && !UNREAD_LABEL.test(el.textContent));
      }
      if (item) {
        item.click();
      } else {
        const open = document.querySelector('[role="menu"] [role="menuitem"]');
        if (open) ['keydown', 'keyup'].forEach((type) => open.dispatchEvent(new KeyboardEvent(type, { key: 'Escape', code: 'Escape', keyCode: 27, which: 27, bubbles: true, cancelable: true })));
        post({ type: 'log', message: 'marcar como lida: opção não encontrada no menu da conversa' });
      }
    } finally {
      await wait(150);
      delete root.dataset.nzMarking;
      button.disabled = false;
      schedule();
    }
  }

  // Só tirar o foco não basta: com o foco no <body>, o WhatsApp devolve na hora
  // para o campo de mensagem (e a conversa voltaria). Leva o foco para a conversa
  // na lista, como o teclado faria.
  function back() {
    setView('list');
    const target = document.querySelector('#pane-side [aria-selected="true"]')
      || document.querySelector('#pane-side [role="gridcell"]');
    if (target instanceof HTMLElement) target.focus({ preventScroll: true });
    else if (document.activeElement instanceof HTMLElement) document.activeElement.blur();
  }

  // Botão de voltar (só aparece no modo compacto com a conversa aberta).
  let backButton = null;
  function updateBackButton() {
    const visible = 'nzCompact' in root.dataset && root.dataset.nzView === 'chat' && !('nzDrawer' in root.dataset)
      && !!document.getElementById('main');
    if (!visible) {
      if (backButton) backButton.hidden = true;
      return;
    }
    if (!backButton) {
      backButton = document.createElement('button');
      backButton.id = 'nz-back';
      backButton.type = 'button';
      backButton.title = 'Voltar para as conversas (⌘[)';
      backButton.innerHTML = '<svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><path d="M15 5l-7 7 7 7" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
      backButton.addEventListener('click', back);
      document.body.appendChild(backButton);
    }
    const header = document.querySelector('#main header');
    if (header) {
      const r = header.getBoundingClientRect();
      backButton.style.top = `${Math.round(r.top + (r.height - 34) / 2)}px`;
    }
    backButton.hidden = false;
  }

  // ---------------------------------------------------------------------------
  // Depuração: exporta só a estrutura da página (tags, ids, roles, caixas).
  // Não inclui textos, nomes nem mensagens.
  // ---------------------------------------------------------------------------
  function dumpLayout() {
    const attrs = ['role', 'data-testid', 'data-icon', 'data-nz', 'data-tab', 'tabindex', 'contenteditable'];
    const skip = new Set(['SCRIPT', 'STYLE', 'LINK', 'META', 'NOSCRIPT', 'TEMPLATE']);
    const walk = (el, depth) => {
      const r = el.getBoundingClientRect();
      const cs = getComputedStyle(el);
      const node = { tag: el.tagName.toLowerCase() };
      if (el.id) node.id = el.id;
      for (const a of attrs) {
        const v = el.getAttribute(a);
        if (v != null) node[a] = v;
      }
      if (el.classList.length) node.cls = el.className && el.className.baseVal != null ? el.className.baseVal : el.className;
      node.box = [r.x, r.y, r.width, r.height].map(Math.round);
      if (cs.display !== 'block') node.display = cs.display;
      if (cs.display.includes('flex')) node.flex = `${cs.flexDirection} | ${cs.flex}`;
      if (cs.minWidth !== '0px' && cs.minWidth !== 'auto') node.minWidth = cs.minWidth;
      if (cs.maxWidth !== 'none') node.maxWidth = cs.maxWidth;
      if (cs.position !== 'static') node.position = cs.position;
      const kids = [...el.children].filter((c) => !skip.has(c.tagName));
      if (depth < 30 && kids.length && el.tagName !== 'svg') {
        node.kids = kids.slice(0, 14).map((c) => walk(c, depth + 1));
        if (kids.length > 14) node.more = kids.length - 14;
      }
      return node;
    };
    return JSON.stringify({
      viewport: [window.innerWidth, window.innerHeight],
      state: { compact: 'nzCompact' in root.dataset, view: root.dataset.nzView },
      body: walk(document.body, 0),
    });
  }

  // ---------------------------------------------------------------------------
  // Conta escondida (aba fora da tela ou janela fechada) não "lê" nada: o
  // WhatsApp marca como lida a mensagem que aparece na conversa aberta, e a página
  // escondida continua com o layout montado. Enquanto oculta, a área de mensagens
  // sai do layout (CSS em html[data-nz-hidden]).
  let warnedNoMessages = false;
  function applyHidden() {
    if (document.visibilityState === 'visible') delete root.dataset.nzHidden;
    else root.dataset.nzHidden = '';
    if (!warnedNoMessages && root.dataset.nzHidden === '' && document.getElementById('main')
      && !document.querySelector('#main [data-testid="conversation-panel-messages"]')) {
      warnedNoMessages = true;
      post({ type: 'log', message: 'área de mensagens não encontrada: a proteção contra leitura da guia escondida pode não estar funcionando' });
    }
  }
  document.addEventListener('visibilitychange', applyHidden);
  applyHidden();

  function init() {
    setStyle('nz-base', cfg.baseCSS);
    setStyle('nz-user', cfg.userCSS);
    root.dataset.nzView = 'list';
    applyCompact();
    compactQuery.addEventListener('change', applyCompact);
    window.addEventListener('resize', () => { applyCompact(); schedule(); });
    new MutationObserver(schedule).observe(document.body, { childList: true, subtree: true });
    tick();
  }

  window.__neyzap = {
    notificationClicked,
    back,
    setBaseCSS: (css) => setStyle('nz-base', css),
    setUserCSS: (css) => setStyle('nz-user', css),
    dumpLayout,
  };

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init, { once: true });
  else init();
})();
