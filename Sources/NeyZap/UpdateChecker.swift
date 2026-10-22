import AppKit
import Security

/// Procura versões novas nos releases do GitHub, baixa o zip, confere a assinatura e
/// troca o app. A versão nova entra ao reiniciar (na hora ou quando o NeyZap fechar).
enum UpdateChecker {
    static let repository = "yagoramires/neyzap"
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Versão já baixada e conferida, esperando o app reiniciar.
    private static var staged: (version: String, app: URL)?
    private static var busy = false
    private static var installOnQuit: NSObjectProtocol?

    private static let stagingDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("NeyZap/update", isDirectory: true)

    /// `userInitiated`: mostra o resultado mesmo sem novidade (ou com erro).
    static func check(userInitiated: Bool) {
        if let staged {
            if userInitiated { askToRestart(staged.version) }
            return
        }
        guard !busy else { return }
        busy = true
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let tag = (json?["tag_name"] as? String) ?? ""
            let page = (json?["html_url"] as? String).flatMap(URL.init(string:)).flatMap(gitHubURL)
            let assets = (json?["assets"] as? [[String: Any]]) ?? []
            let zip = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
                .flatMap { $0["browser_download_url"] as? String }
                .flatMap(URL.init(string:)).flatMap(gitHubURL)
            DispatchQueue.main.async {
                guard error == nil, status == 200, !tag.isEmpty, let page else {
                    busy = false
                    Log.write("atualização: falha ao consultar (status \(status), \(error?.localizedDescription ?? "sem release"))")
                    if userInitiated {
                        alert("Não consegui verificar atualizações", "Tente de novo mais tarde.\n\(error?.localizedDescription ?? "Status \(status)")")
                    }
                    return
                }
                let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                Log.write("atualização: instalada \(currentVersion), publicada \(latest)")
                guard isVersion(latest, newerThan: currentVersion) else {
                    busy = false
                    if userInitiated { alert("O NeyZap está atualizado", "Versão \(currentVersion) é a mais recente.") }
                    return
                }
                guard let zip else {
                    busy = false
                    failed(latest, page, "o release não tem o zip do app")
                    return
                }
                download(zip, version: latest, page: page)
            }
        }.resume()
    }

    private static func gitHubURL(_ url: URL) -> URL? {
        url.scheme == "https" && url.host == "github.com" ? url : nil
    }

    // MARK: - Baixar e conferir

    private static func download(_ zip: URL, version: String, page: URL) {
        Log.write("atualização: baixando \(version)")
        var request = URLRequest(url: zip)
        request.timeoutInterval = 60
        URLSession.shared.downloadTask(with: request) { file, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            var result: Result<URL, UpdateError>
            if let file, error == nil, status == 200 {
                result = prepare(zip: file, version: version)
            } else {
                result = .failure(UpdateError("download falhou (status \(status), \(error?.localizedDescription ?? "-"))"))
            }
            DispatchQueue.main.async {
                busy = false
                switch result {
                case .success(let app):
                    Log.write("atualização: \(version) baixada e conferida")
                    staged = (version, app)
                    installOnQuit = NotificationCenter.default.addObserver(
                        forName: NSApplication.willTerminateNotification, object: nil, queue: .main
                    ) { _ in _ = try? swapBundle() }
                    askToRestart(version)
                case .failure(let problem):
                    failed(version, page, problem.message)
                }
            }
        }.resume()
    }

    /// Roda fora da thread principal: descompacta e só aceita um NeyZap da versão
    /// esperada, assinado com o mesmo certificado do app aberto.
    private static func prepare(zip: URL, version: String) -> Result<URL, UpdateError> {
        let fm = FileManager.default
        try? fm.removeItem(at: stagingDir)
        do {
            try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            guard run("/usr/bin/ditto", ["-x", "-k", zip.path, stagingDir.path]) else {
                throw UpdateError("não consegui descompactar o zip")
            }
            let app = stagingDir.appendingPathComponent("NeyZap.app")
            let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
            guard info?["CFBundleShortVersionString"] as? String == version else {
                throw UpdateError("o zip não traz o NeyZap \(version)")
            }
            try verifySignature(app)
            _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
            return .success(app)
        } catch {
            try? fm.removeItem(at: stagingDir)
            return .failure(error as? UpdateError ?? UpdateError(error.localizedDescription))
        }
    }

    /// A versão nova precisa cumprir o requisito de assinatura do app aberto (mesmo
    /// identificador e mesmo certificado). Assim o macOS mantém as permissões e
    /// ninguém consegue trocar o zip do release por outro app.
    private static func verifySignature(_ app: URL) throws {
        var me: SecCode?, mine: SecStaticCode?, requirement: SecRequirement?, candidate: SecStaticCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &mine) == errSecSuccess, let mine,
              SecCodeCopyDesignatedRequirement(mine, [], &requirement) == errSecSuccess,
              let requirement else {
            throw UpdateError("não consegui ler a assinatura do app aberto")
        }
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &candidate) == errSecSuccess, let candidate else {
            throw UpdateError("o app baixado não está assinado")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        let status = SecStaticCodeCheckValidity(candidate, flags, requirement)
        guard status == errSecSuccess else {
            throw UpdateError("assinatura do app baixado não confere (\(status))")
        }
    }

    // MARK: - Instalar

    private static func askToRestart(_ version: String) {
        let a = NSAlert()
        a.messageText = "NeyZap \(version) pronto para instalar"
        a.informativeText = "Você está com a versão \(currentVersion). As guias voltam logadas depois de reiniciar.\nSe deixar para depois, a versão nova entra quando o NeyZap fechar."
        a.addButton(withTitle: "Reiniciar agora")
        a.addButton(withTitle: "Depois")
        NSApp.activate()
        if a.runModal() == .alertFirstButtonReturn { installAndRelaunch() }
    }

    private static func installAndRelaunch() {
        let old: URL
        do {
            guard let replaced = try swapBundle() else { return }
            old = replaced
        } catch {
            Log.write("atualização: falha ao instalar (\(error.localizedDescription))")
            alert("Não consegui instalar a atualização", error.localizedDescription)
            return
        }
        // Um processo à parte espera este fechar, abre o app de novo (uma instância só)
        // e apaga a cópia antiga, que este processo ainda está usando.
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; sleep 1.5; /usr/bin/open \"$2\"; rm -rf \"$3\"",
                              "sh", "\(ProcessInfo.processInfo.processIdentifier)", Bundle.main.bundlePath, old.path]
        do {
            try relaunch.run()
        } catch {
            Log.write("atualização: instalada, mas não consegui reabrir (\(error.localizedDescription))")
        }
        NSApp.terminate(nil)
    }

    /// Troca o app instalado pelo baixado de uma vez (o aberto continua usando os
    /// arquivos dele até fechar). Se algo falhar no meio, volta o antigo. Devolve onde
    /// ficou a cópia antiga.
    @discardableResult
    private static func swapBundle() throws -> URL? {
        guard let staged else { return nil }
        self.staged = nil
        if let installOnQuit { NotificationCenter.default.removeObserver(installOnQuit) }
        let fm = FileManager.default
        let current = Bundle.main.bundleURL
        let incoming = current.deletingLastPathComponent().appendingPathComponent(".NeyZap-novo.app")
        let old = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: current, create: true)
            .appendingPathComponent("NeyZap.app")
        try? fm.removeItem(at: incoming)
        try fm.moveItem(at: staged.app, to: incoming)
        try fm.moveItem(at: current, to: old)
        do {
            try fm.moveItem(at: incoming, to: current)
        } catch {
            try? fm.moveItem(at: old, to: current)
            throw error
        }
        try? fm.removeItem(at: stagingDir)
        Log.write("atualização: \(staged.version) instalada em \(current.path)")
        return old.deletingLastPathComponent()
    }

    private static func failed(_ version: String, _ page: URL, _ reason: String) {
        Log.write("atualização: \(version) não instalada (\(reason))")
        let a = NSAlert()
        a.messageText = "NeyZap \(version) disponível"
        a.informativeText = "Não consegui instalar sozinho (\(reason)). Dá para baixar pela página do release."
        a.addButton(withTitle: "Abrir página")
        a.addButton(withTitle: "Depois")
        NSApp.activate()
        if a.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(page) }
    }

    // MARK: - Apoio

    private struct UpdateError: Error, LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    private static func run(_ tool: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
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
