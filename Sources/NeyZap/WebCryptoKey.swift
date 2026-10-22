import Foundation
import Security

/// Chave mestra do WebCrypto (protege as chaves que o WhatsApp Web guarda no IndexedDB).
///
/// Por padrão o WebKit guarda essa chave no Chaveiro, e como o app não tem conta de
/// desenvolvedor, o macOS amarra o acesso à impressão digital exata do binário: a
/// cada recompilação ele volta a pedir a senha. Por isso o app entrega a chave ao
/// WebKit ele mesmo (delegate `_webCryptoMasterKeyForWebView:`), guardada num
/// arquivo só do usuário.
///
/// Trocar essa chave desloga todas as guias, então ela nunca é sobrescrita às cegas:
/// arquivo válido → usa; ilegível → tenta a cópia do Chaveiro; só sem nenhuma das duas
/// gera uma nova (e guarda o arquivo ruim ao lado, para diagnóstico).
enum WebCryptoKey {
    static let url = AppPaths.support.appendingPathComponent("webcrypto.key")

    static let data: Data = {
        let fm = FileManager.default
        if let saved = try? Data(contentsOf: url), saved.count >= 16 { return saved }

        if fm.fileExists(atPath: url.path) {
            // Com data no nome: uma segunda falha não apaga a cópia da primeira.
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let bad = url.appendingPathExtension("corrompida-\(stamp)")
            try? fm.moveItem(at: url, to: bad)
            Log.write("chave do WebCrypto ilegível; guardada em \(bad.lastPathComponent)")
        }

        let key: Data
        if let fromKeychain = fromKeychain() {
            key = fromKeychain
            Log.write("chave do WebCrypto recuperada do Chaveiro")
        } else if let fresh = random(count: 16) {
            key = fresh
            Log.write("chave do WebCrypto nova (as guias vão pedir o QR code)")
        } else {
            fatalError("Sem gerador de números aleatórios para criar a chave do WebCrypto")
        }
        save(key)
        return key
    }()

    /// Grava já com permissão 0600 (nunca existe uma cópia legível por outros) e troca
    /// o arquivo de uma vez.
    private static func save(_ key: Data) {
        let temp = url.deletingLastPathComponent().appendingPathComponent(".webcrypto.key.\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: temp.path, contents: key, attributes: [.posixPermissions: 0o600]),
              rename(temp.path, url.path) == 0 else {
            try? FileManager.default.removeItem(at: temp)
            Log.write("não consegui gravar a chave do WebCrypto")
            return
        }
    }

    private static func fromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "com.apple.WebKit.WebCrypto.master+local.neyzap",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let stored = result as? Data else { return nil }
        // O WebKit grava a chave em base64.
        return Data(base64Encoded: stored) ?? stored
    }

    private static func random(count: Int) -> Data? {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { return nil }
        return Data(bytes)
    }
}
