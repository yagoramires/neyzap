import AppKit
import Carbon
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private var windowController: MainWindowController!
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private var debugBridge: DebugBridge?
    private let accountsMenu = NSMenu(title: "Contas")
    private let statusMenu = NSMenu()

    private var window: NSWindow { windowController.window! }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = WebCryptoKey.data
        Notifier.shared.setup()
        let openNotification: (UUID, String) -> Void = { [weak self] accountID, jsID in
            guard let self else { return }
            self.showWindow()
            self.windowController.select(accountID: accountID)
            self.windowController.sessions.first { $0.accountID == accountID }?.notificationClicked(jsID)
        }
        Notifier.shared.onClick = openNotification
        BannerCenter.shared.onClick = openNotification

        windowController = MainWindowController()
        windowController.onUnreadChange = { [weak self] in
            self?.updateBadges()
            self?.refreshAccountsMenu()
        }

        UserStyle.shared.onChange = { [weak self] css in self?.windowController.applyUserCSS(css) }
        UserStyle.shared.start()

        NSApp.mainMenu = buildMainMenu()
        refreshAccountsMenu()
        if UserDefaults.standard.bool(forKey: "showStatusItem") { setUpStatusItem() }
        // ⌃⌥Z mostra/esconde o NeyZap de qualquer lugar.
        hotKey = HotKey(keyCode: kVK_ANSI_Z, modifiers: controlKey | optionKey) { [weak self] in self?.toggleWindow() }

        debugBridge = DebugBridge(windowController: windowController)
        showWindow()
        Log.write("NeyZap \(UpdateChecker.currentVersion) aberto, \(windowController.sessions.count) conta(s)")
        // Verificação silenciosa: só aparece algo se houver versão nova.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { UpdateChecker.check(userInitiated: false) }
    }

    /// Menu do ícone no Dock: contas (com não lidas), conectar número, atualizações e logs.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        for (i, session) in windowController.sessions.enumerated() {
            let entry = item(session.unread > 0 ? "\(session.name) (\(session.unread))" : session.name, #selector(selectAccount(_:)), "")
            entry.tag = i
            entry.state = i == windowController.selectedIndex ? .on : .off
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(item("Conectar outro número…", #selector(addAccount), ""))
        menu.addItem(.separator())
        menu.addItem(item("Verificar atualizações…", #selector(checkForUpdates), ""))
        menu.addItem(item("Logs de depuração", #selector(openLogs), ""))
        return menu
    }

    @objc private func checkForUpdates() { UpdateChecker.check(userInitiated: true) }
    @objc private func openLogs() { Log.reveal() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Janela

    private func showWindow() {
        windowController.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    @objc private func toggleWindow() {
        if NSApp.isActive && window.isVisible && window.isKeyWindow {
            NSApp.hide(nil)
        } else {
            showWindow()
        }
    }

    private func updateBadges() {
        let total = windowController.sessions.reduce(0) { $0 + $1.unread }
        NSApp.dockTile.badgeLabel = total > 0 ? String(total) : nil
        statusItem?.button?.title = total > 0 ? " \(total)" : ""
    }

    // MARK: - Barra de menus (ícone)

    private func setUpStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem
        let image = NSImage(systemSymbolName: "bubble.left.and.bubble.right.fill", accessibilityDescription: "NeyZap")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusMenu.delegate = self
    }

    /// Clique esquerdo mostra/esconde; clique direito (ou ⌃clique) abre o menu.
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            statusItem?.menu = statusMenu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            toggleWindow()
        }
    }

    // MARK: - Menu principal

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Sobre o NeyZap", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(item("Verificar atualizações…", #selector(checkForUpdates), ""))
        appMenu.addItem(item("Logs de depuração", #selector(openLogs), ""))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Editar tema (user.css)…", #selector(openUserCSS), ","))
        appMenu.addItem(item("Abrir ao iniciar sessão", #selector(toggleLaunchAtLogin), ""))
        appMenu.addItem(item("Usar notificações do sistema", #selector(toggleSystemNotifications), ""))
        appMenu.addItem(item("Mostrar ícone na barra de menus", #selector(toggleStatusItem), ""))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Ocultar NeyZap", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Ocultar Outros", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Mostrar Todos", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Encerrar NeyZap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(appMenu, "NeyZap"))

        let edit = NSMenu(title: "Editar")
        edit.addItem(withTitle: "Desfazer", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Refazer", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Recortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Colar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Selecionar Tudo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu(edit, "Editar"))

        accountsMenu.delegate = self
        main.addItem(submenu(accountsMenu, "Contas"))

        let view = NSMenu(title: "Visualizar")
        view.addItem(item("Voltar para as conversas", #selector(goBack), "["))
        view.addItem(.separator())
        view.addItem(item("Lado a lado", #selector(toggleSideBySide), "\\"))
        view.addItem(item("Sempre na frente", #selector(togglePinned), "t", [.command, .option]))
        view.addItem(.separator())
        view.addItem(item("Aumentar zoom", #selector(zoomIn), "+"))
        let zoomInAlt = item("Aumentar zoom", #selector(zoomIn), "=")
        zoomInAlt.isHidden = true
        zoomInAlt.allowsKeyEquivalentWhenHidden = true
        view.addItem(zoomInAlt)
        view.addItem(item("Diminuir zoom", #selector(zoomOut), "-"))
        view.addItem(item("Tamanho real", #selector(zoomReset), "0"))
        view.addItem(.separator())
        view.addItem(item("Exportar estrutura da página (depuração)", #selector(dumpLayout), "d", [.command, .option, .shift]))
        main.addItem(submenu(view, "Visualizar"))

        let windowMenu = NSMenu(title: "Janela")
        windowMenu.addItem(withTitle: "Minimizar", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(withTitle: "Fechar", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu(windowMenu, "Janela"))
        NSApp.windowsMenu = windowMenu

        return main
    }

    /// Os atalhos ⌘1…⌘9 precisam existir antes do menu ser aberto pela primeira vez.
    private func refreshAccountsMenu() {
        menuNeedsUpdate(accountsMenu)
    }

    /// Menus dinâmicos: lista de contas (menu principal) e menu do ícone.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let sessions = windowController.sessions

        if menu === statusMenu {
            menu.addItem(item(window.isVisible ? "Esconder NeyZap" : "Mostrar NeyZap", #selector(toggleWindow), ""))
            menu.addItem(.separator())
        }

        for (i, session) in sessions.enumerated() {
            let title = session.unread > 0 ? "\(session.name) (\(session.unread))" : session.name
            let entry = item(title, #selector(selectAccount(_:)), menu === accountsMenu && i < 9 ? "\(i + 1)" : "")
            entry.tag = i
            entry.state = i == windowController.selectedIndex ? .on : .off
            menu.addItem(entry)
        }

        menu.addItem(.separator())
        if menu === accountsMenu {
            menu.addItem(item("Conectar outro número…", #selector(addAccount), "n", [.command, .shift]))
            menu.addItem(item("Renomear conta…", #selector(renameAccount), ""))
            menu.addItem(item("Remover conta…", #selector(removeAccount), ""))
            menu.addItem(.separator())
            menu.addItem(item("Recarregar", #selector(reload), "r"))
            menu.addItem(item("Limpar sessão (novo QR code)…", #selector(resetSession), ""))
        } else {
            menu.addItem(withTitle: "Encerrar NeyZap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleSideBySide): menuItem.state = windowController.isSideBySide ? .on : .off
        case #selector(togglePinned): menuItem.state = windowController.isPinned ? .on : .off
        case #selector(toggleLaunchAtLogin): menuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        case #selector(toggleStatusItem): menuItem.state = statusItem == nil ? .off : .on
        case #selector(toggleSystemNotifications): menuItem.state = UserDefaults.standard.bool(forKey: "systemNotifications") ? .on : .off
        case #selector(removeAccount): return windowController.sessions.count > 1
        default: break
        }
        return true
    }

    // MARK: - Ações

    @objc private func selectAccount(_ sender: NSMenuItem) {
        showWindow()
        windowController.select(index: sender.tag)
        refreshAccountsMenu()
    }

    @objc private func addAccount() {
        let n = windowController.sessions.count + 1
        guard let name = Dialogs.prompt(title: "Nova conta", message: "Dê um nome para identificar este número.", defaultValue: "Conta \(n)", confirm: "Adicionar") else { return }
        windowController.addAccount(named: name)
        refreshAccountsMenu()
    }

    @objc private func renameAccount() {
        let session = windowController.activeSession
        guard let name = Dialogs.prompt(title: "Renomear conta", defaultValue: session.name, confirm: "Renomear") else { return }
        windowController.renameActiveAccount(to: name)
        refreshAccountsMenu()
    }

    @objc private func removeAccount() {
        let session = windowController.activeSession
        let ok = Dialogs.confirm(
            title: "Remover “\(session.name)”?",
            message: "A sessão do WhatsApp Web desta conta será apagada deste Mac. Lembre de desconectar o aparelho também no celular (Aparelhos conectados).",
            confirm: "Remover",
            destructive: true
        )
        if ok {
            windowController.removeActiveAccount()
            refreshAccountsMenu()
        }
    }

    @objc private func reload() { windowController.activeSession.reload() }

    @objc private func resetSession() {
        let session = windowController.activeSession
        let ok = Dialogs.confirm(
            title: "Limpar a sessão de “\(session.name)”?",
            message: "Os dados do WhatsApp Web desta conta serão apagados deste Mac e o QR code aparecerá de novo. Desconecte o aparelho antigo no celular (Aparelhos conectados).",
            confirm: "Limpar",
            destructive: true
        )
        if ok { session.resetSession() }
    }
    @objc private func goBack() { windowController.activeSession.back() }
    @objc private func toggleSideBySide() { windowController.toggleSideBySide(nil) }
    @objc private func togglePinned() { windowController.togglePinned(nil) }
    @objc private func zoomIn() { windowController.setZoom(windowController.selectedSession.webView.pageZoom + 0.1) }
    @objc private func zoomOut() { windowController.setZoom(windowController.selectedSession.webView.pageZoom - 0.1) }
    @objc private func zoomReset() { windowController.setZoom(1) }

    @objc private func toggleStatusItem() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        } else {
            setUpStatusItem()
            updateBadges()
        }
        UserDefaults.standard.set(statusItem != nil, forKey: "showStatusItem")
    }

    /// Desligado: balões do próprio NeyZap (com a foto). Ligado: Central de Notificações.
    @objc private func toggleSystemNotifications() {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: "systemNotifications"), forKey: "systemNotifications")
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Não consegui mudar a abertura automática"
            alert.runModal()
        }
    }

    @objc private func openUserCSS() {
        NSWorkspace.shared.open(UserStyle.shared.url)
    }

    @objc private func dumpLayout() {
        let session = windowController.activeSession
        session.dumpLayout { json in
            guard let json else { return }
            let url = AppPaths.debug.appendingPathComponent("layout-\(session.name).json")
            try? json.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    // MARK: - Utilitários

    private func item(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    private func submenu(_ menu: NSMenu, _ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menu.title = title
        item.submenu = menu
        return item
    }
}
