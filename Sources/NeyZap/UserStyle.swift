import Foundation

/// CSS do usuário em ~/Library/Application Support/NeyZap/user.css,
/// recarregado ao vivo sempre que o arquivo é salvo.
final class UserStyle {
    static let shared = UserStyle()

    let url = AppPaths.support.appendingPathComponent("user.css")
    private(set) var css = ""
    var onChange: ((String) -> Void)?

    private init() {
        if !FileManager.default.fileExists(atPath: url.path) {
            let template = "/* NeyZap — seu tema. Salve o arquivo e o app aplica na hora. */\n"
            try? template.write(to: url, atomically: true, encoding: .utf8)
        }
        css = read()
    }

    /// Verifica o arquivo a cada meio segundo. Cobre tanto editores que gravam
    /// no lugar quanto os que trocam o arquivo inteiro ao salvar.
    func start() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let latest = self.read()
            guard latest != self.css else { return }
            self.css = latest
            self.onChange?(latest)
        }
    }

    private func read() -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
