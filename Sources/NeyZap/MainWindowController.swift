import AppKit
import WebKit

final class MainWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private(set) var sessions: [AccountSession] = []
    private(set) var selectedIndex = 0
    var onUnreadChange: (() -> Void)?

    private let accountPicker = NSSegmentedControl()
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

        accountPicker.segmentStyle = .automatic
        accountPicker.trackingMode = .selectOne
        accountPicker.target = self
        accountPicker.action = #selector(pickAccount(_:))

        let toolbar = NSToolbar(identifier: "main")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact

        sessions = AccountStore.shared.accounts.map(makeSession)
        selectedIndex = min(defaults.integer(forKey: "selectedAccount"), sessions.count - 1)
        if isPinned { window.level = .floating }
        layoutSessions()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Contas

    private func makeSession(_ account: Account) -> AccountSession {
        let session = AccountSession(account: account)
        session.onUnreadChange = { [weak self] in
            self?.refreshPicker()
            self?.onUnreadChange?()
        }
        return session
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

    func addAccount(named name: String) {
        sessions.append(makeSession(AccountStore.shared.add(name: name)))
        select(index: sessions.count - 1)
    }

    func renameActiveAccount(to name: String) {
        let session = activeSession
        session.name = name
        AccountStore.shared.rename(session.accountID, to: name)
        refreshPicker()
    }

    /// Remove a conta e apaga a sessão dela (o WhatsApp vai pedir o QR de novo se ela for recriada).
    func removeActiveAccount() {
        guard sessions.count > 1 else { return }
        let session = activeSession
        let id = session.accountID
        session.webView.removeFromSuperview()
        sessions.removeAll { $0 === session }
        AccountStore.shared.remove(id)
        selectedIndex = min(selectedIndex, sessions.count - 1)
        layoutSessions()
        onUnreadChange?()
        // Dá tempo da WebView ser liberada antes de apagar o armazenamento.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            WKWebsiteDataStore.remove(forIdentifier: id) { error in
                if let error { NSLog("NeyZap: não consegui apagar os dados da conta: %@", error.localizedDescription) }
            }
        }
    }

    // MARK: - Layout

    private func layoutSessions() {
        let visible = isSideBySide ? sessions : [selectedSession]
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
        equalizePanes()
        window?.makeFirstResponder(selectedSession.webView)
        refreshPicker()
        refreshToolbar()
    }

    /// Contas fora da tela ficam na janela, ocultas, com o tamanho real. Fora da
    /// hierarquia a página fica 0×0, e o WhatsApp pode travar carregando assim.
    private func parkHiddenSessions(except visible: [AccountSession]) {
        guard let content = window?.contentView else { return }
        for session in sessions where !visible.contains(where: { $0 === session }) {
            let webView = session.webView
            if webView.superview !== content {
                webView.removeFromSuperview()
                content.addSubview(webView, positioned: .below, relativeTo: splitView)
            }
            webView.frame = splitView.frame
            webView.autoresizingMask = [.width, .height]
            webView.isHidden = true
        }
        for session in visible { session.webView.isHidden = false }
    }

    /// Cada conta visível precisa de pelo menos 340 px (320 com uma só).
    private func updateMinimumSize(panes: Int) {
        guard let window else { return }
        let width = panes > 1 ? CGFloat(panes) * 340 + splitView.dividerThickness * CGFloat(panes - 1) : 320
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

    private static let pickerItem = NSToolbarItem.Identifier("accounts")
    private static let sideBySideItem = NSToolbarItem.Identifier("sideBySide")
    private static let pinItem = NSToolbarItem.Identifier("pin")

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.pickerItem, .flexibleSpace, Self.sideBySideItem, Self.pinItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: id)
        switch id {
        case Self.pickerItem:
            item.view = accountPicker
            item.label = "Contas"
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

    private func refreshPicker() {
        accountPicker.segmentCount = sessions.count
        for (i, session) in sessions.enumerated() {
            accountPicker.setLabel("", forSegment: i)
            accountPicker.setImage(Self.tabImage(name: session.name, unread: session.unread), forSegment: i)
            accountPicker.setToolTip(session.unread > 0 ? "\(session.name): \(session.unread) conversa(s) não lida(s)" : session.name, forSegment: i)
            accountPicker.setWidth(0, forSegment: i)
        }
        accountPicker.selectedSegment = selectedIndex
        accountPicker.sizeToFit()
    }

    /// Nome da conta + selo vermelho com as não lidas, como o do Dock. Desenhado na
    /// hora de pintar, então a cor do texto acompanha o tema claro/escuro.
    private static func tabImage(name: String, unread: Int) -> NSImage {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        let text = NSAttributedString(string: name, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        let textSize = text.size()
        let badge = unread > 99 ? "99+" : "\(unread)"
        let badgeText = NSAttributedString(string: badge, attributes: [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .bold), .foregroundColor: NSColor.white,
        ])
        let badgeHeight: CGFloat = 16
        let badgeWidth = unread > 0 ? max(badgeHeight, badgeText.size().width + 9) : 0
        let gap: CGFloat = unread > 0 ? 5 : 0
        let size = NSSize(width: ceil(textSize.width + gap + badgeWidth), height: max(ceil(textSize.height), badgeHeight))
        let image = NSImage(size: size, flipped: false) { _ in
            text.draw(at: NSPoint(x: 0, y: (size.height - textSize.height) / 2))
            guard unread > 0 else { return true }
            let rect = NSRect(x: textSize.width + gap, y: (size.height - badgeHeight) / 2, width: badgeWidth, height: badgeHeight)
            NSColor.systemRed.setFill()
            NSBezierPath(roundedRect: rect, xRadius: badgeHeight / 2, yRadius: badgeHeight / 2).fill()
            let b = badgeText.size()
            badgeText.draw(at: NSPoint(x: rect.midX - b.width / 2, y: rect.midY - b.height / 2))
            return true
        }
        image.isTemplate = false
        return image
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

    @objc private func pickAccount(_ sender: NSSegmentedControl) {
        if isSideBySide {
            selectedIndex = sender.selectedSegment
            window?.makeFirstResponder(selectedSession.webView)
        } else {
            select(index: sender.selectedSegment)
        }
    }

    @objc func toggleSideBySide(_ sender: Any?) { isSideBySide.toggle() }
    @objc func togglePinned(_ sender: Any?) { isPinned.toggle() }

    // MARK: - Janela

    /// Fechar só esconde: o app continua recebendo mensagens e notificando.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
