import AppKit

/// Comandos de depuração vindos do terminal (desligado por padrão).
///
///   defaults write local.neyzap debugBridge -bool true
///   scripts/debug.sh dump | snap | size 420x700 | front | reload | reset <conta> | select <conta>
///   click X Y | esc | eval <expressão JS> | hot <pasta com layout.css e inject.js> | side on|off
///
/// Tudo é gravado em ~/Library/Application Support/NeyZap/debug/.
final class DebugBridge {
    static let name = Notification.Name("local.neyzap.debug")

    private let windowController: MainWindowController
    private var observer: NSObjectProtocol?

    init?(windowController: MainWindowController) {
        guard UserDefaults.standard.bool(forKey: "debugBridge") else { return nil }
        self.windowController = windowController
        observer = DistributedNotificationCenter.default().addObserver(forName: Self.name, object: nil, queue: .main) { [weak self] note in
            self?.run(note.object as? String ?? "")
        }
    }

    private func run(_ command: String) {
        let parts = command.split(separator: " ").map(String.init)
        switch parts.first {
        case "dump":
            for session in windowController.sessions {
                session.dumpLayout { json in
                    guard let json else { return }
                    try? json.write(to: self.file("layout-\(session.name).json"), atomically: true, encoding: .utf8)
                }
            }
        case "snap":
            for session in windowController.sessions where session.webView.window != nil {
                session.webView.takeSnapshot(with: nil) { image, _ in
                    guard let image, let tiff = image.tiffRepresentation,
                          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
                    try? png.write(to: self.file("snap-\(session.name).png"))
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
        case "click":
            // Clique em coordenadas da página (CSS px, origem no canto superior esquerdo).
            guard parts.count > 2, let x = Double(parts[1]), let y = Double(parts[2]) else { return }
            click(at: NSPoint(x: x, y: y), in: windowController.selectedSession.webView)
        case "esc":
            // Só Esc: nada que possa enviar texto (Enter num campo de mensagem enviaria).
            sendEscape(to: windowController.selectedSession.webView)
        case "eval":
            // Consulta de leitura; o resultado vai para debug/eval.txt.
            let js = parts.dropFirst().joined(separator: " ")
            windowController.selectedSession.webView.evaluateJavaScript("JSON.stringify((() => { return \(js) })())") { result, error in
                let text = (result as? String) ?? "erro: \(String(describing: error))"
                try? text.write(to: self.file("eval.txt"), atomically: true, encoding: .utf8)
            }
        case "hot":
            // Recarrega layout.css e inject.js de uma pasta (ex.: Resources do projeto).
            guard parts.count > 1 else { return }
            let dir = URL(fileURLWithPath: parts.dropFirst().joined(separator: " "))
            guard let css = try? String(contentsOf: dir.appendingPathComponent("layout.css"), encoding: .utf8),
                  let js = try? String(contentsOf: dir.appendingPathComponent("inject.js"), encoding: .utf8) else { return }
            let jsChanged = js != AccountSession.injectJS
            AccountSession.baseCSS = css
            AccountSession.injectJS = js
            windowController.sessions.forEach { $0.reloadResources(jsChanged: jsChanged) }
        case "side":
            windowController.isSideBySide = parts.count > 1 && parts[1] == "on"
        case "select":
            guard parts.count > 1, let i = windowController.sessions.firstIndex(where: { $0.name == parts[1] }) else { return }
            windowController.select(index: i)
        case "reset":
            guard parts.count > 1 else { return }
            windowController.sessions.first { $0.name == parts[1] }?.resetSession()
        default:
            NSLog("NeyZap debug: comando desconhecido %@", command)
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

    private func file(_ name: String) -> URL {
        AppPaths.debug.appendingPathComponent(name)
    }
}
