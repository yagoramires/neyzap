import AppKit

/// Log de depuração em ~/Library/Logs/NeyZap/neyzap.log (nunca grava conteúdo de
/// mensagens, só eventos do app).
enum Log {
    static let url: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/NeyZap", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("neyzap.log")
    }()

    private static let queue = DispatchQueue(label: "local.neyzap.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async {
            // Mantém o arquivo pequeno: passou de 2 MB, guarda o anterior e recomeça.
            if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > 2_000_000 {
                let old = url.deletingPathExtension().appendingPathExtension("old.log")
                try? FileManager.default.removeItem(at: old)
                try? FileManager.default.moveItem(at: url, to: old)
            }
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    /// Abre o log no Console do macOS.
    static func reveal() {
        if !FileManager.default.fileExists(atPath: url.path) { write("log criado") }
        queue.sync {}
        NSWorkspace.shared.open(url)
    }
}
