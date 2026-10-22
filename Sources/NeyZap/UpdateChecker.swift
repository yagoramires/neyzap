import AppKit

/// Procura versões novas nos releases do GitHub.
enum UpdateChecker {
    static let repository = "yagoramires/neyzap"
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// `userInitiated`: mostra o resultado mesmo sem novidade (ou com erro).
    static func check(userInitiated: Bool) {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let tag = (json?["tag_name"] as? String) ?? ""
            let page = (json?["html_url"] as? String).flatMap(URL.init(string:))
            DispatchQueue.main.async {
                guard error == nil, status == 200, !tag.isEmpty, let page else {
                    Log.write("atualização: falha ao consultar (status \(status), \(error?.localizedDescription ?? "sem release"))")
                    if userInitiated {
                        alert("Não consegui verificar atualizações", "Tente de novo mais tarde.\n\(error?.localizedDescription ?? "Status \(status)")")
                    }
                    return
                }
                let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                Log.write("atualização: instalada \(currentVersion), publicada \(latest)")
                if isVersion(latest, newerThan: currentVersion) {
                    let a = NSAlert()
                    a.messageText = "NeyZap \(latest) disponível"
                    a.informativeText = "Você está com a versão \(currentVersion)."
                    a.addButton(withTitle: "Ver novidades e baixar")
                    a.addButton(withTitle: "Depois")
                    NSApp.activate()
                    if a.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(page) }
                } else if userInitiated {
                    alert("O NeyZap está atualizado", "Versão \(currentVersion) é a mais recente.")
                }
            }
        }.resume()
    }

    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate()
        a.runModal()
    }
}
