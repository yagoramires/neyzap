import AppKit
import Security

/// Comandos de depuração vindos do terminal. **Desligado por padrão.** Ligado, o
/// comando vem no arquivo `debug/command` (pasta 0700) e precisa começar com a senha
/// de `debug/token` (0600, nova a cada abertura do app). A notificação que avisa do
/// comando não leva dado nenhum: nada de senha ou comando passando por um canal que
/// outros programas escutam. Desligado, a senha é apagada.
///
///   defaults write local.neyzap debugBridge -bool true   (e reabrir o app)
///   scripts/debug.sh <comando>   (grava debug/command e avisa o app)
///   scripts/debug.sh dump | snap | size 420x700 | front | reload | side on|off
///   scripts/debug.sh select <guia> | reset <guia> | eval <expr> | evalin <guia> <expr>
///   scripts/debug.sh click X Y | esc | hot <pasta com layout.css e inject.js>
///
/// Saída em ~/Library/Application Support/NeyZap/debug/ (arquivos 0600).
final class DebugBridge {
    static let name = Notification.Name("local.neyzap.debug")

    private let windowController: MainWindowController
    private let token: String
    private var observer: NSObjectProtocol?

    private static var commandURL: URL { AppPaths.debug.appendingPathComponent("command") }

    init?(windowController: MainWindowController) {
        guard UserDefaults.standard.bool(forKey: "debugBridge") else {
            Self.cleanUp()
            return nil
        }
        guard let token = Self.newToken() else {
            Log.write("canal de depuração não ligou: sem gerador de números aleatórios")
            return nil
        }
        self.windowController = windowController
        self.token = token
        Log.write("canal de depuração ligado")
        observer = DistributedNotificationCenter.default().addObserver(forName: Self.name, object: nil, queue: .main) { [weak self] _ in
            self?.receive()
        }
        // Ao encerrar, a senha deixa de existir até a próxima abertura.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            Self.cleanUp()
        }
    }

    /// Canal desligado: apaga a senha e o que a depuração deixou (capturas de tela
    /// podem mostrar conversas).
    private static func cleanUp() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: AppPaths.debug, includingPropertiesForKeys: nil) else { return }
        for file in files where ["token", "command", "eval.txt"].contains(file.lastPathComponent) || file.lastPathComponent.hasPrefix("snap-") {
            try? fm.removeItem(at: file)
        }
    }

    private func receive() {
        let url = Self.commandURL
        guard let data = try? Data(contentsOf: url) else { return }
        try? FileManager.default.removeItem(at: url)
        let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
        guard message.hasPrefix(token + " ") else {
            Log.write("depuração: comando recusado (sem a senha)")
            return
        }
        run(String(message.dropFirst(token.count + 1)))
    }

    private func run(_ command: String) {
        let parts = command.split(separator: " ").map(String.init)
        let rest = parts.dropFirst().joined(separator: " ")
        switch parts.first {
        case "dump":
            for session in windowController.sessions {
                session.dumpLayout { json in
                    guard let json else { return }
                    self.write(json, to: "layout-\(AppPaths.safeName(session.name)).json")
                }
            }
        case "snap":
            // Só as guias que estão na tela.
            for session in windowController.sessions where session.webView.window === windowController.window {
                session.webView.takeSnapshot(with: nil) { image, _ in
                    guard let image, let tiff = image.tiffRepresentation,
                          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
                    self.write(png, to: "snap-\(AppPaths.safeName(session.name)).png")
                }
            }
        case "size":
            guard parts.count > 1, let window = windowController.window else { return }
            let dims = parts[1].split(separator: "x").compactMap { Double($0) }
            guard dims.count == 2 else { return }
            var frame = window.frame
            frame.origin.y += frame.height - dims[1]
            frame.size = NSSize(width: dims[0], height: dims[1])
            window.setFrame(frame, display: true, animate: false)
        case "front":
            windowController.window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
        case "reload":
            windowController.sessions.forEach { $0.reload() }
        case "side":
            windowController.isSideBySide = parts.count > 1 && parts[1] == "on"
        case "click":
            // Clique em coordenadas da página (CSS px, origem no canto superior esquerdo).
            guard parts.count > 2, let x = Double(parts[1]), let y = Double(parts[2]) else { return }
            click(at: NSPoint(x: x, y: y), in: windowController.selectedSession.webView)
        case "esc":
            // Só Esc: nada que possa enviar texto (Enter num campo de mensagem enviaria).
            sendEscape(to: windowController.selectedSession.webView)
        case "eval":
            evaluate(rest, in: windowController.selectedSession)
        case "evalin":
            // evalin <guia> <expr>: como eval, mas numa guia específica (sem trocar de guia).
            guard let (session, js) = session(prefixing: rest) else { return }
            evaluate(js, in: session)
        case "hot":
            // Recarrega layout.css e inject.js de uma pasta (ex.: Resources do projeto).
            let dir = URL(fileURLWithPath: rest)
            guard let css = try? String(contentsOf: dir.appendingPathComponent("layout.css"), encoding: .utf8),
                  let js = try? String(contentsOf: dir.appendingPathComponent("inject.js"), encoding: .utf8) else { return }
            let jsChanged = js != AccountSession.injectJS
            AccountSession.baseCSS = css
            AccountSession.injectJS = js
            windowController.sessions.forEach { $0.reloadResources(jsChanged: jsChanged) }
        case "select":
            guard let (session, _) = session(prefixing: rest) else { return }
            windowController.select(accountID: session.accountID)
        case "reset":
            guard let (session, _) = session(prefixing: rest) else { return }
            session.resetSession()
        default:
            Log.write("depuração: comando desconhecido \(parts.first ?? "")")
        }
    }

    /// Guia cujo nome começa o texto (nomes podem ter espaços, como "WhatsApp 2").
    private func session(prefixing text: String) -> (AccountSession, String)? {
        let match = windowController.sessions
            .filter { text == $0.name || text.hasPrefix($0.name + " ") }
            .max { $0.name.count < $1.name.count }
        guard let match else { return nil }
        return (match, String(text.dropFirst(match.name.count)).trimmingCharacters(in: .whitespaces))
    }

    /// Avalia JavaScript na página (qualquer código: por isso a senha). Resultado em debug/eval.txt.
    private func evaluate(_ js: String, in session: AccountSession) {
        session.webView.evaluateJavaScript("JSON.stringify((() => { return \(js) })())") { result, error in
            self.write((result as? String) ?? "erro: \(String(describing: error))", to: "eval.txt")
        }
    }

    private func click(at point: NSPoint, in webView: NSView) {
        guard let window = webView.window else { return }
        let inWindow = webView.convert(point, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: inWindow, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                window.sendEvent(event)
            }
        }
    }

    private func sendEscape(to webView: NSView) {
        guard let window = webView.window else { return }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                                            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) {
                window.sendEvent(event)
            }
        }
    }

    // MARK: - Arquivos

    private func write(_ text: String, to name: String) {
        write(Data(text.utf8), to: name)
    }

    private func write(_ data: Data, to name: String) {
        AppPaths.writePrivate(data, to: name)
    }

    /// Senha nova a cada abertura (a de antes deixa de valer).
    private static func newToken() -> String? {
        var bytes = [UInt8](repeating: 0, count: 24)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        guard AppPaths.writePrivate(Data(token.utf8), to: "token") != nil else { return nil }
        return token
    }
}
