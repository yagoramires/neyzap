import AppKit
import WebKit

final class MainWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private(set) var sessions: [AccountSession] = []
    private(set) var selectedIndex = 0
    var onUnreadChange: (() -> Void)?
    /// Guias criadas, renomeadas ou fechadas (para atualizar menus).
    var onAccountsChange: (() -> Void)?

    private let tabBar = TabBarView()
    private let splitView = NSSplitView()
    private let defaults = UserDefaults.standard

    var selectedSession: AccountSession { sessions[selectedIndex] }

    /// Sessão que tem o foco do teclado (no modo lado a lado), senão a selecionada.
    var activeSession: AccountSession {
        if isSideBySide, let responder = window?.firstResponder as? NSView,
           let session = sessions.first(where: { responder.isDescendant(of: $0.webView) }) {
            return session
        }
        return selectedSession
    }

    var isSideBySide: Bool {
        get { defaults.bool(forKey: "sideBySide") }
        set { defaults.set(newValue, forKey: "sideBySide"); layoutSessions() }
    }

    var isPinned: Bool {
        get { defaults.bool(forKey: "pinned") }
        set { defaults.set(newValue, forKey: "pinned"); window?.level = newValue ? .floating : .normal; refreshToolbar() }
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NeyZap"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Grafite.sidebar
        window.minSize = NSSize(width: 320, height: 420)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.center()
        window.setFrameAutosaveName("NeyZapMain")
        super.init(window: window)
        window.delegate = self

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autoresizingMask = [.width, .height]
        window.contentView = NSView()
        window.contentView?.addSubview(splitView)
        splitView.frame = window.contentView!.bounds

        tabBar.onSelect = { [weak self] id in self?.selectTab(id) }
        tabBar.onAdd = { [weak self] site in self?.newTab(site: site) }
        tabBar.onRename = { [weak self] id, name in self?.rename(accountID: id, to: name) }
        tabBar.onClose = { [weak self] id in self?.confirmClose(accountID: id) }
        tabBar.onResetSession = { [weak self] id in self?.confirmReset(accountID: id) }
        tabBar.onToggleDisabled = { [weak self] id in self?.toggleDisabled(accountID: id) }
        tabBar.onEditingEnded = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.activeSession.webView)
        }

        let toolbar = NSToolbar(identifier: "main")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact

        sessions = AccountStore.shared.accounts.map { makeSession($0) }
        selectedIndex = min(defaults.integer(forKey: "selectedAccount"), sessions.count - 1)
        if isPinned { window.level = .floating }
        layoutSessions()

        let memoryCheck = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            self?.sessions.forEach {
                $0.killIfHung()
                $0.reloadIfOverMemory(minimumLimit: 1 << 30)
            }
            self?.keepDisabledLinked()
        }
        memoryCheck.tolerance = 60
        RunLoop.main.add(memoryCheck, forMode: .common)
        NotificationCenter.default.addObserver(forName: NSApplication.didHideNotification, object: nil, queue: .main) { [weak self] _ in
            self?.pauseInstagram()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Contas

    private func makeSession(_ account: Account, keepAlive: Bool = false) -> AccountSession {
        let session = AccountSession(account: account, keepAlive: keepAlive)
        session.onUnreadChange = { [weak self] in
            self?.refreshTabs()
            self?.onUnreadChange?()
        }
        session.onEnable = { [weak self, id = account.id] in self?.toggleDisabled(accountID: id) }
        return session
    }

    /// Desativar troca a sessão por uma que não carrega: a WebView antiga é liberada
    /// e o processo da página fecha. Ativar cria uma sessão nova, que carrega normal.
    func toggleDisabled(accountID: UUID) {
        guard let i = sessions.firstIndex(where: { $0.accountID == accountID }) else { return }
        let old = sessions[i]
        AccountStore.shared.setDisabled(accountID, !old.isDisabled)
        if !old.isDisabled { defaults.set(Date(), forKey: "lastOnline-\(accountID.uuidString)") }
        Log.write("[\(old.name)] guia \(old.isDisabled ? "ativada" : "desativada")")
        replaceSession(at: i)
    }

    private func replaceSession(at i: Int, keepAlive: Bool = false) {
        let old = sessions[i]
        guard let account = AccountStore.shared.accounts.first(where: { $0.id == old.accountID }) else { return }
        old.webView.removeFromSuperview()
        BannerCenter.shared.dismissAll(accountID: old.accountID)
        sessions[i] = makeSession(account, keepAlive: keepAlive)
        layoutSessions()
        onUnreadChange?() // atualiza selos, Dock e menus
    }

    /// O WhatsApp desconecta aparelhos que passam muito tempo sem se conectar: guia de
    /// WhatsApp desativada há 7 dias conecta escondida por 15 min e volta a desligar.
    private func keepDisabledLinked() {
        for (i, session) in sessions.enumerated() where session.isDisabled && !session.isInstagram {
            let key = "lastOnline-\(session.accountID.uuidString)"
            if let started = session.keepAliveStarted {
                guard started.timeIntervalSinceNow < -15 * 60 else { continue }
                defaults.set(Date(), forKey: key)
                Log.write("[\(session.name)] desativada: conexão de manutenção feita")
                replaceSession(at: i)
            } else if (defaults.object(forKey: key) as? Date ?? .distantPast).timeIntervalSinceNow < -7 * 86400 {
                replaceSession(at: i, keepAlive: true)
            }
        }
    }

    func select(index: Int) {
        guard sessions.indices.contains(index) else { return }
        selectedIndex = index
        defaults.set(index, forKey: "selectedAccount")
        layoutSessions()
    }

    func select(accountID: UUID) {
        if let i = sessions.firstIndex(where: { $0.accountID == accountID }) { select(index: i) }
    }

    /// Guia nova: conecta outro número (mostra o QR) ou abre o Instagram; o nome dá para trocar depois.
    func newTab(site: Account.Site = .whatsapp) {
        let base = site == .instagram ? "Instagram" : "WhatsApp"
        let taken = Set(sessions.map(\.name))
        var name = base, n = 1
        while taken.contains(name) { n += 1; name = "\(base) \(n)" }
        sessions.append(makeSession(AccountStore.shared.add(name: name, site: site)))
        select(index: sessions.count - 1)
        onAccountsChange?()
    }

    func rename(accountID: UUID, to name: String) {
        guard let session = sessions.first(where: { $0.accountID == accountID }) else { return }
        session.name = name
        AccountStore.shared.rename(accountID, to: name)
        refreshTabs()
        onAccountsChange?()
    }

    func promptRename(accountID: UUID) {
        guard let session = sessions.first(where: { $0.accountID == accountID }),
              let name = Dialogs.prompt(title: "Renomear guia", defaultValue: session.name, confirm: "Renomear") else { return }
        rename(accountID: accountID, to: name)
    }

    /// Fecha a guia e apaga a sessão dela deste Mac (o número precisa ler o QR de novo).
    func confirmClose(accountID: UUID) {
        guard sessions.count > 1, let session = sessions.first(where: { $0.accountID == accountID }) else { return }
        let ok = Dialogs.confirm(
            title: "Fechar a guia “\(session.name)”?",
            message: session.isInstagram
                ? "O login do Instagram desta guia será apagado deste Mac."
                : "A sessão do WhatsApp Web desta guia será apagada deste Mac. Lembre de desconectar o aparelho também no celular (Aparelhos conectados).",
            confirm: "Fechar guia",
            destructive: true
        )
        if ok { remove(session) }
    }

    func confirmReset(accountID: UUID) {
        guard let session = sessions.first(where: { $0.accountID == accountID }) else { return }
        let ok = Dialogs.confirm(
            title: "Limpar a sessão de “\(session.name)”?",
            message: session.isInstagram
                ? "Os dados do Instagram desta guia serão apagados deste Mac e será preciso entrar de novo."
                : "Os dados do WhatsApp Web desta guia serão apagados deste Mac e o QR code aparecerá de novo. Desconecte o aparelho antigo no celular (Aparelhos conectados).",
            confirm: "Limpar",
            destructive: true
        )
        if ok { session.resetSession() }
    }

    private func remove(_ session: AccountSession) {
        let id = session.accountID
        // A seleção continua na mesma guia (pelo id): mudar sozinha traria outra conta
        // para a tela e marcaria as mensagens dela como lidas.
        let keep = session === selectedSession ? nil : selectedSession.accountID
        let removedIndex = sessions.firstIndex { $0 === session } ?? selectedIndex
        session.webView.removeFromSuperview()
        sessions.removeAll { $0 === session }
        AccountStore.shared.remove(id)
        BannerCenter.shared.dismissAll(accountID: id)
        defaults.removeObject(forKey: "bgSyncCheckedAt-\(id.uuidString)")
        defaults.removeObject(forKey: "lastOnline-\(id.uuidString)")
        if let keep, let i = sessions.firstIndex(where: { $0.accountID == keep }) {
            selectedIndex = i
        } else {
            selectedIndex = min(removedIndex, sessions.count - 1)
        }
        defaults.set(selectedIndex, forKey: "selectedAccount")
        layoutSessions()
        onUnreadChange?() // atualiza selos, Dock e menus
        // Dá tempo da WebView ser liberada antes de apagar o armazenamento.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { Self.deleteData(of: id, retries: 2) }
    }

    /// O WebKit pode demorar a largar o armazenamento ("in use"): tenta de novo mais
    /// tarde e, em último caso, na próxima abertura do app.
    private static func deleteData(of id: UUID, retries: Int = 0) {
        WKWebsiteDataStore.remove(forIdentifier: id) { error in
            guard let error else {
                AccountStore.shared.forgetClosed(id)
                return
            }
            if retries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { deleteData(of: id, retries: retries - 1) }
            } else {
                Log.write("não consegui apagar os dados da guia fechada (tento de novo ao abrir): \(error.localizedDescription)")
            }
        }
    }

    /// Armazenamentos sem guia na lista. Os de guias fechadas (remoção que falhou ou
    /// foi interrompida) são apagados; qualquer outro volta como guia: se a lista de
    /// guias se perder, as sessões reaparecem em vez de serem apagadas.
    func reconcileDataStores() {
        WKWebsiteDataStore.fetchAllDataStoreIdentifiers { [weak self] ids in
            DispatchQueue.main.async { self?.reconcile(ids) }
        }
    }

    private func reconcile(_ ids: [UUID]) {
        let store = AccountStore.shared
        let known = Set(store.accounts.map(\.id))
        let unknown = ids.filter { !known.contains($0) }
        for id in unknown where store.closed.contains(id) { Self.deleteData(of: id) }
        for id in store.closed where !ids.contains(id) { store.forgetClosed(id) } // já não existem
        let lost = unknown.filter { !store.closed.contains($0) }
        guard !lost.isEmpty else { return }
        // A guia em branco criada no lugar da lista perdida dá lugar às recuperadas.
        let placeholder = store.startedFresh && sessions.count == 1 ? sessions.first : nil
        for (i, id) in lost.enumerated() {
            sessions.append(makeSession(store.add(name: lost.count > 1 ? "Recuperada \(i + 1)" : "Recuperada", id: id)))
        }
        Log.write("\(lost.count) sessão(ões) sem guia recuperada(s) como guia")
        if let placeholder { remove(placeholder) } else { layoutSessions() }
        onAccountsChange?()
    }

    private func selectTab(_ id: UUID) {
        guard let i = sessions.firstIndex(where: { $0.accountID == id }) else { return }
        // Guia desativada só aparece lado a lado enquanto selecionada: o layout muda.
        if isSideBySide && !sessions[i].isDisabled && !selectedSession.isDisabled {
            selectedIndex = i
            defaults.set(i, forKey: "selectedAccount")
            window?.makeFirstResponder(selectedSession.webView)
            refreshTabs()
        } else {
            select(index: i)
        }
    }

    // MARK: - Layout

    private func layoutSessions() {
        let visible = isSideBySide ? sessions.filter { !$0.isDisabled || $0 === selectedSession } : [selectedSession]
        for view in splitView.arrangedSubviews where !visible.contains(where: { $0.webView === view }) {
            splitView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (i, session) in visible.enumerated() where splitView.arrangedSubviews.firstIndex(of: session.webView) != i {
            session.webView.removeFromSuperview()
            splitView.insertArrangedSubview(session.webView, at: i)
        }
        parkHiddenSessions(except: visible)
        updateMinimumSize(panes: visible.count)
        splitView.adjustSubviews()
        // Só redistribui quando muda o número de colunas (preserva divisórias arrastadas).
        if visible.count != lastPaneCount {
            equalizePanes()
            lastPaneCount = visible.count
        }
        window?.makeFirstResponder(selectedSession.webView)
        refreshTabs()
        refreshToolbar()
    }

    /// Janela invisível (nunca mostrada, nunca em foco) onde ficam as contas fora
    /// da tela. Para o WebKit elas viram uma aba de fundo de outra janela: ocultas e
    /// sem foco, então o WhatsApp notifica e não marca nada como lido. E mantêm o
    /// tamanho real (fora de qualquer janela a página fica 0×0 e pode travar).
    private lazy var parkingWindow: NSWindow = {
        let parking = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                               styleMask: [.borderless], backing: .buffered, defer: false)
        parking.isReleasedWhenClosed = false
        parking.contentView = NSView()
        return parking
    }()

    private func parkHiddenSessions(except visible: [AccountSession]) {
        guard let parked = parkingWindow.contentView else { return }
        parkingWindow.setContentSize(splitView.frame.size)
        for session in sessions where !visible.contains(where: { $0 === session }) {
            let webView = session.webView
            if webView.superview !== parked {
                webView.removeFromSuperview()
                parked.addSubview(webView)
            }
            webView.frame = parked.bounds
            webView.autoresizingMask = [.width, .height]
            webView.isHidden = false
            if session.parkedAt == nil {
                session.parkedAt = Date()
                // Reel saindo da tela não continua tocando no fundo.
                if session.isInstagram { webView.pauseAllMediaPlayback() }
            }
        }
        for session in visible {
            session.webView.isHidden = false
            session.parkedAt = nil
        }
    }

    /// Cada conta visível precisa de pelo menos 340 px (320 com uma só).
    private var lastPaneCount = 0

    private func updateMinimumSize(panes: Int) {
        guard let window else { return }
        let wanted = panes > 1 ? CGFloat(panes) * 340 + splitView.dividerThickness * CGFloat(panes - 1) : 320
        let screenWidth = (window.screen ?? NSScreen.main)?.visibleFrame.width ?? wanted
        let width = min(wanted, screenWidth) // muitas guias lado a lado: não passa da tela
        window.minSize = NSSize(width: width, height: 420)
        if window.frame.width < width {
            var frame = window.frame
            frame.size.width = width
            window.setFrame(frame, display: true, animate: true)
        }
    }

    private func equalizePanes() {
        let count = splitView.arrangedSubviews.count
        guard count > 1 else { return }
        let width = (splitView.bounds.width - splitView.dividerThickness * CGFloat(count - 1)) / CGFloat(count)
        for i in 0..<(count - 1) {
            splitView.setPosition(width * CGFloat(i + 1) + splitView.dividerThickness * CGFloat(i), ofDividerAt: i)
        }
    }

    func setZoom(_ zoom: CGFloat) {
        let clamped = min(max(zoom, 0.5), 2)
        defaults.set(Double(clamped), forKey: "zoom")
        sessions.forEach { $0.webView.pageZoom = clamped }
    }

    func applyUserCSS(_ css: String) {
        sessions.forEach { $0.applyUserCSS(css) }
    }

    // MARK: - Barra de ferramentas

    private static let tabsItem = NSToolbarItem.Identifier("tabs")
    private static let sideBySideItem = NSToolbarItem.Identifier("sideBySide")
    private static let pinItem = NSToolbarItem.Identifier("pin")

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.tabsItem, .flexibleSpace, Self.sideBySideItem, Self.pinItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        switch id {
        case Self.tabsItem:
            item.view = tabBar
            item.label = "Guias"
            item.visibilityPriority = .high
        case Self.sideBySideItem:
            item.label = "Lado a lado"
            item.toolTip = "Mostrar as contas lado a lado (⌘\\)"
            item.isBordered = true
            item.target = self
            item.action = #selector(toggleSideBySide(_:))
        case Self.pinItem:
            item.label = "Sempre na frente"
            item.toolTip = "Manter a janela sempre na frente (⌥⌘T)"
            item.isBordered = true
            item.target = self
            item.action = #selector(togglePinned(_:))
        default:
            return nil
        }
        return item
    }

    private func refreshTabs() {
        tabBar.maxWidth = max(120, (window?.frame.width ?? 800) - 190)
        let tabs = sessions.map { TabBarView.Tab(id: $0.accountID, name: $0.name, unread: $0.unread, archived: $0.archivedUnread, disabled: $0.isDisabled) }
        tabBar.update(tabs: tabs, selected: sessions.indices.contains(selectedIndex) ? selectedSession.accountID : nil)
    }

    private func refreshToolbar() {
        for item in window?.toolbar?.items ?? [] {
            switch item.itemIdentifier {
            case Self.sideBySideItem:
                item.image = NSImage(systemSymbolName: isSideBySide ? "rectangle.split.2x1.fill" : "rectangle.split.2x1", accessibilityDescription: "Lado a lado")
            case Self.pinItem:
                item.image = NSImage(systemSymbolName: isPinned ? "pin.fill" : "pin", accessibilityDescription: "Sempre na frente")
            default:
                break
            }
        }
    }

    // MARK: - Ações

    @objc func toggleSideBySide(_ sender: Any?) { isSideBySide.toggle() }
    @objc func togglePinned(_ sender: Any?) { isPinned.toggle() }

    // MARK: - Janela

    /// Fechar só esconde: o app continua recebendo mensagens e notificando.
    func windowDidResize(_ notification: Notification) {
        tabBar.maxWidth = max(120, (window?.frame.width ?? 800) - 190)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        pauseInstagram()
        return false
    }

    /// Janela fechada ou app escondido: os reels param de tocar.
    private func pauseInstagram() {
        sessions.filter { $0.isInstagram && !$0.isDisabled }.forEach { $0.webView.pauseAllMediaPlayback() }
    }
}
