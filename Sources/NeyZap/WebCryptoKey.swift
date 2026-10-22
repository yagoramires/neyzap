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
            let bad = url.appendingPathExtension("corrompida")
            try? fm.removeItem(at: bad)
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

    private static func save(_ key: Data) {
        do {
            try key.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            Log.write("não consegui gravar a chave do WebCrypto: \(error.localizedDescription)")
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
