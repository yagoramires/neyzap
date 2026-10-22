import AppKit
import WebKit

/// Uma conta do WhatsApp: uma WKWebView com armazenamento próprio carregando o
/// WhatsApp Web oficial.
final class AccountSession: NSObject {
    static let home = URL(string: "https://web.whatsapp.com/")!
    static var baseCSS = BundledResource.text("layout", "css")
    static var injectJS = BundledResource.text("inject", "js")

    /// Versão do Safari instalado, para a WebView se identificar igual a ele.
    static let safariVersion: String = {
        let plist = URL(fileURLWithPath: "/Applications/Safari.app/Contents/Info.plist")
        let info = NSDictionary(contentsOf: plist)
        return info?["CFBundleShortVersionString"] as? String ?? "27.0"
    }()

    let accountID: UUID
    var name: String
    let webView: WKWebView

    var onUnreadChange: (() -> Void)?
    private(set) var unread = 0 {
        didSet { if unread != oldValue { onUnreadChange?() } }
    }
    /// Conversas arquivadas não lidas (lidas da linha "Arquivadas" da lista).
    private(set) var archivedUnread = 0 {
        didSet { if archivedUnread != oldValue { onUnreadChange?() } }
    }

    private var titleObservation: NSKeyValueObservation?
    private var notificationIDs: [String: String] = [:] // id no JS → id na Central
    private var downloads: [ObjectIdentifier: URL] = [:]

    init(account: Account) {
        accountID = account.id
        name = account.name

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: account.id)
        config.applicationNameForUserAgent = "Version/\(Self.safariVersion) Safari/605.1.15"
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true
        // Contas independentes: sem isso o WebKit suspende o processo da página
        // escondida (aba fora da tela ou janela fechada) e as mensagens só chegam,
        // e notificam, quando a aba volta. Os temporizadores da página escondida
        // continuam desacelerados (economia de bateria); as mensagens chegam pela
        // conexão de rede, que não depende deles.
        Self.setPrivatePreference(config.preferences, "_setPageVisibilityBasedProcessSuppressionEnabled:", false)
        webView = WKWebView(frame: .zero, configuration: config)

        super.init()

        config.userContentController.add(WeakScriptHandler(self), name: "neyzap")
        installUserScripts(userCSS: UserStyle.shared.css)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.isInspectable = true
        webView.pageZoom = CGFloat(UserDefaults.standard.object(forKey: "zoom") as? Double ?? 1)

        titleObservation = webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
            self?.updateUnread(from: webView.title)
        }

        Log.write("[\(account.name)] carregando WhatsApp Web")
        webView.load(URLRequest(url: Self.home))
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "neyzap")
        Notifier.shared.remove(Array(notificationIDs.values))
    }

    // MARK: - Ações vindas do app

    func reload() {
        if webView.url == nil { webView.load(URLRequest(url: Self.home)) } else { webView.reload() }
    }

    /// Apaga os dados do WhatsApp Web desta conta e volta para o QR code.
    func resetSession() {
        let store = webView.configuration.websiteDataStore
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
            self?.webView.load(URLRequest(url: Self.home))
        }
    }

    func back() {
        webView.evaluateJavaScript("window.__neyzap && __neyzap.back()")
    }

    func notificationClicked(_ jsID: String) {
        webView.evaluateJavaScript("window.__neyzap && __neyzap.notificationClicked(\(jsLiteral(jsID)))")
    }

    func applyUserCSS(_ css: String) {
        installUserScripts(userCSS: css)
        webView.evaluateJavaScript("window.__neyzap && __neyzap.setUserCSS(\(jsLiteral(css)))")
    }

    /// Reaplica layout.css/inject.js depois de trocados (recarga a quente na depuração).
    func reloadResources(jsChanged: Bool) {
        installUserScripts(userCSS: UserStyle.shared.css)
        if jsChanged {
            webView.reload()
        } else {
            webView.evaluateJavaScript("window.__neyzap && __neyzap.setBaseCSS(\(jsLiteral(Self.baseCSS)))")
        }
    }

    func dumpLayout(completion: @escaping (String?) -> Void) {
        webView.evaluateJavaScript("window.__neyzap ? __neyzap.dumpLayout() : 'sem __neyzap'") { result, error in
            completion(result as? String ?? error.map { "erro: \($0)" })
        }
    }

    // MARK: - Internos

    private func installUserScripts(userCSS: String) {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        // Depuração: abre o WhatsApp Web puro, sem nada injetado.
        if UserDefaults.standard.bool(forKey: "debugNoInject") { return }
        let config = "window.__neyzapConfig = { baseCSS: \(jsLiteral(Self.baseCSS)), userCSS: \(jsLiteral(userCSS)), compactWidth: 760 };"
        controller.addUserScript(WKUserScript(source: config, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.addUserScript(WKUserScript(source: Self.injectJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    /// O WhatsApp Web põe as conversas não lidas no título: "(3) WhatsApp".
    private func updateUnread(from title: String?) {
        guard let title, title.hasPrefix("("), let close = title.firstIndex(of: ")") else {
            unread = 0
            return
        }
        unread = Int(title[title.index(after: title.startIndex)..<close]) ?? 0
    }

    /// Ajustes privados do WKPreferences (sem eles na versão do WebKit, só registra no log).
    private static func setPrivatePreference(_ preferences: WKPreferences, _ name: String, _ value: Bool) {
        let selector = NSSelectorFromString(name)
        guard preferences.responds(to: selector) else {
            Log.write("WebKit sem \(name)")
            return
        }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(preferences.method(for: selector), to: Setter.self)(preferences, selector, value)
    }

    private static func isWhatsApp(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return ["whatsapp.com", "whatsapp.net"].contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

// MARK: - Mensagens do JS

extension AccountSession: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "notify":
            guard let jsID = body["id"] as? String else { return }
            Log.write("[\(name)] notificação recebida")
            let tag = body["tag"] as? String ?? ""
            let identifier = tag.isEmpty ? "\(accountID.uuidString)|\(UUID().uuidString)" : "\(accountID.uuidString)|tag|\(tag)"
            notificationIDs[jsID] = identifier
            let title = body["title"] as? String ?? "WhatsApp"
            let text = body["body"] as? String ?? ""
            let account = AccountStore.shared.accounts.count > 1 ? name : nil
            guard UserDefaults.standard.bool(forKey: "systemNotifications") else {
                BannerCenter.shared.show(
                    BannerContent(accountID: accountID, jsID: jsID, key: tag.isEmpty ? identifier : "\(accountID.uuidString)|\(tag)",
                                  account: account, title: title, body: text),
                    icon: body["icon"] as? String ?? ""
                )
                return
            }
            Notifier.shared.post(
                identifier: identifier,
                accountID: accountID,
                jsID: jsID,
                title: title,
                subtitle: account,
                body: text,
                tag: tag,
                silent: body["silent"] as? Bool ?? false
            )
        case "log":
            Log.write("[\(name)] \(body["message"] as? String ?? "")")
        case "archived":
            archivedUnread = body["count"] as? Int ?? 0
            Log.write("[\(name)] arquivadas não lidas: \(archivedUnread)")
        case "notifyClose":
            guard let jsID = body["id"] as? String else { return }
            BannerCenter.shared.dismiss(accountID: accountID, jsID: jsID)
            guard let identifier = notificationIDs.removeValue(forKey: jsID) else { return }
            if !notificationIDs.values.contains(identifier) { Notifier.shared.remove([identifier]) }
        default:
            break
        }
    }
}

/// Evita o ciclo de retenção WKUserContentController → handler.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

// MARK: - Navegação e downloads

extension AccountSession: WKNavigationDelegate, WKDownloadDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        guard let url = action.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow)
            return
        }
        let isMainFrame = action.targetFrame?.isMainFrame ?? true
        let isWeb = scheme == "http" || scheme == "https"
        if (isWeb && isMainFrame && !Self.isWhatsApp(url.host)) || ["mailto", "tel", "sms", "facetime"].contains(scheme) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(response.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    // Delegates privados do WebKit: o app entrega a chave mestra do WebCrypto em vez
    // de o WebKit buscá-la no Chaveiro (ver WebCryptoKey).
    @objc(_webCryptoMasterKeyForWebView:completionHandler:)
    func webCryptoMasterKey(for webView: WKWebView, completionHandler: @escaping (NSData?) -> Void) {
        completionHandler(WebCryptoKey.data as NSData)
    }

    @objc(_webCryptoMasterKeyForWebView:)
    func webCryptoMasterKey(for webView: WKWebView) -> NSData? {
        WebCryptoKey.data as NSData
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Log.write("[\(name)] página carregada")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Log.write("[\(name)] falha ao carregar: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Log.write("[\(name)] falha ao conectar: \(error.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Log.write("[\(name)] processo da página encerrou; recarregando")
        webView.reload()
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let url = AppPaths.uniqueDownload(named: suggestedFilename)
        downloads[ObjectIdentifier(download)] = url
        completionHandler(url)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        // Faz a pilha de Downloads do Dock pular, como no Safari.
        DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: url.path)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloads.removeValue(forKey: ObjectIdentifier(download))
        NSLog("NeyZap: download falhou: %@", error.localizedDescription)
    }
}

// MARK: - Interface (janelas, arquivos, câmera/microfone, alertas)

extension AccountSession: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        if let window = webView.window {
            panel.beginSheetModal(for: window) { completionHandler($0 == .OK ? panel.urls : nil) }
        } else {
            completionHandler(panel.runModal() == .OK ? panel.urls : nil)
        }
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(Self.isWhatsApp(origin.host) ? .grant : .deny)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancelar")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }
}
