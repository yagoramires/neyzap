import Foundation

/// CSS do usuário em ~/Library/Application Support/NeyZap/user.css,
/// recarregado ao vivo sempre que o arquivo é salvo.
final class UserStyle {
    static let shared = UserStyle()

    let url = AppPaths.support.appendingPathComponent("user.css")
    private(set) var css = ""
    var onChange: ((String) -> Void)?

    private var folderWatch: DispatchSourceFileSystemObject?
    private var fileWatch: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    private init() {
        if !FileManager.default.fileExists(atPath: url.path) {
            let template = "/* NeyZap — seu tema. Salve o arquivo e o app aplica na hora. */\n"
            try? template.write(to: url, atomically: true, encoding: .utf8)
        }
        css = read()
    }

    /// Avisado pelo sistema quando o arquivo muda (sem ficar lendo o disco): vigia a
    /// pasta (editores que salvam trocando o arquivo) e o próprio arquivo (os que
    /// gravam no lugar).
    func start() {
        folderWatch = watch(AppPaths.support.path, events: .write)
        watchFile()
    }

    private func watchFile() {
        fileWatch?.cancel()
        fileWatch = watch(url.path, events: [.write, .extend, .delete, .rename])
    }

    private func watch(_ path: String, events: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: events, queue: .main)
        source.setEventHandler { [weak self] in self?.changed() }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.watchFile() // o arquivo pode ter sido trocado por outro
            let latest = self.read()
            guard latest != self.css else { return }
            self.css = latest
            self.onChange?(latest)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func read() -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
