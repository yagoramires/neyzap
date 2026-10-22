// NeyZap — roda dentro do WhatsApp Web (frame principal, no início do documento).
// Regra de ouro: este script só mexe em apresentação e lê a tela. Nunca envia
// mensagens, nunca automatiza ações e nunca toca nos módulos internos do WhatsApp.
(() => {
  'use strict';
  if (window.__neyzap) return;

  const cfg = window.__neyzapConfig || {};
  const root = document.documentElement;
  const post = (msg) => {
    try { window.webkit.messageHandlers.neyzap.postMessage(msg); } catch (_) {}
  };

  // ---------------------------------------------------------------------------
  // Notificações: troca a API web por notificações nativas do macOS.
  // ---------------------------------------------------------------------------
  const live = new Map();
  let seq = 0;

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
      this.id = String(++seq);
      this.title = String(title ?? '');
      this.body = options.body ? String(options.body) : '';
      this.tag = options.tag ? String(options.tag) : '';
      this.icon = options.icon || '';
      this.data = options.data ?? null;
      this.silent = !!options.silent;
      this.onclick = this.onclose = this.onshow = this.onerror = null;
      live.set(this.id, this);
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
      if (role === 'overlay' && c.children.length >= 2 && getComputedStyle(c).flexDirection === 'row') {
        [...c.children].forEach((k, j) => {
          const sub = j === 0 ? 'side' : 'rest';
          if (k.getAttribute('data-nz-sub') !== sub) k.setAttribute('data-nz-sub', sub);
        });
      }
    });

    // Painel da direita (dados do contato, busca na conversa…) aberto? Fechado,
    // ele só tem um <span> vazio.
    const drawerOpen = kids.some((c) => c.getAttribute('data-nz') === 'drawer' && c.children.length
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

    for (let a = panes.parentElement; a && a !== document.body; a = a.parentElement) {
      if (!a.hasAttribute('data-nz-anc')) a.setAttribute('data-nz-anc', '');
    }
  }

  // Decide uma vez por elemento, sem os nossos atributos: o próprio CSS do modo
  // compacto põe colunas em position:fixed, o que não pode virar "camada".
  const overlayCache = new WeakMap();
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
  }

  let scheduled = false;
  function schedule() {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(() => { scheduled = false; tick(); });
    schedulePromoScan();
  }

  // ---------------------------------------------------------------------------
  // Propaganda do app para Mac/Windows ("Baixe o WhatsApp para Mac"): aparece de
  // vez em quando acima da lista ou no lugar da conversa. Não tem id estável,
  // então é achada pelo texto e marcada com data-nz-hide (o CSS esconde).
  // Mensagens e prévias de conversa nunca são tocadas.
  // ---------------------------------------------------------------------------
  const PROMO = /(baixe|baixar|download|get)\b.{0,30}whatsapp.{0,20}\b(para|for)\s+(mac|windows)/i;
  let promoTimer = 0;

  function schedulePromoScan() {
    if (promoTimer) return;
    promoTimer = setTimeout(() => { promoTimer = 0; hidePromos(); }, 1500);
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

  function hidePromos() {
    enableNotifications();
    reportArchived();
    renameTitle();
    const roots = [document.querySelector('[data-nz="side"]'), document.querySelector('[data-nz="main"]')].filter(Boolean);
    for (const r of roots) {
      const walker = document.createTreeWalker(r, NodeFilter.SHOW_TEXT);
      for (let n = walker.nextNode(); n; n = walker.nextNode()) {
        if (!/mac|windows/i.test(n.data)) continue;
        let el = n.parentElement;
        if (!el || el.closest('#main, #pane-side [role="row"], #pane-side [role="listitem"], [data-nz-hide]')) continue;
        while (el && el !== r && !PROMO.test(el.textContent)) el = el.parentElement;
        if (!el || el === r) continue;
        // Sobe enquanto o pai ainda for só o banner (texto curto, caixa baixa).
        while (el.parentElement && el.parentElement !== r && el.parentElement.textContent.length < 120
          && el.parentElement.getBoundingClientRect().height < 120) el = el.parentElement;
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
  function applyHidden() {
    if (document.visibilityState === 'visible') delete root.dataset.nzHidden;
    else root.dataset.nzHidden = '';
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
