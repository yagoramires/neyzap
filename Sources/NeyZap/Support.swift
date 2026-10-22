import AppKit

enum BundledResource {
    static func text(_ name: String, _ ext: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            NSLog("NeyZap: recurso ausente %@.%@", name, ext)
            return ""
        }
        return text
    }
}

/// Codifica uma string Swift como literal JavaScript.
func jsLiteral(_ string: String) -> String {
    guard let data = try? JSONEncoder().encode(string), let literal = String(data: data, encoding: .utf8) else {
        return "\"\""
    }
    return literal
}

enum AppPaths {
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("NeyZap", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Pasta de depuração: só o usuário entra (pode guardar a senha do canal e dumps).
    static var debug: URL {
        let dir = support.appendingPathComponent("debug", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        return dir
    }

    /// Grava em debug/ um arquivo que só o usuário lê (criado já 0600, sem janela 0644).
    @discardableResult
    static func writePrivate(_ data: Data, to name: String) -> URL? {
        let url = debug.appendingPathComponent(name)
        let temp = debug.appendingPathComponent(".\(name).\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return nil }
        guard rename(temp.path, url.path) == 0 else {
            try? FileManager.default.removeItem(at: temp)
            return nil
        }
        return url
    }

    /// Nome de guia seguro para nome de arquivo (sem "/" nem "..").
    static func safeName(_ name: String) -> String {
        let cleaned = name.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        return String(cleaned.prefix(40))
    }

    /// Caminho livre em ~/Downloads (acrescenta " 2", " 3"… se já existir).
    static func uniqueDownload(named name: String) -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let safe = name.isEmpty ? "arquivo" : name.replacingOccurrences(of: "/", with: "-")
        var url = downloads.appendingPathComponent(safe)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = downloads.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }
}

enum Dialogs {
    static func prompt(title: String, message: String = "", defaultValue: String = "", confirm: String = "OK") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Cancelar")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func confirm(title: String, message: String, confirm: String, destructive: Bool = false) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = destructive ? .critical : .informational
        let button = alert.addButton(withTitle: confirm)
        button.hasDestructiveAction = destructive
        alert.addButton(withTitle: "Cancelar")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
