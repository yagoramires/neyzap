import Foundation
import Security

/// Chave mestra do WebCrypto (protege as chaves que o WhatsApp Web guarda no IndexedDB).
///
/// Por padrão o WebKit guarda essa chave no Chaveiro, e como o app não tem conta de
/// desenvolvedor, o macOS amarra o acesso à impressão digital exata do binário: a
/// cada recompilação ele volta a pedir a senha. Por isso o app entrega a chave ao
/// WebKit ele mesmo (delegate `_webCryptoMasterKeyForWebView:`), guardada num
/// arquivo só do usuário.
enum WebCryptoKey {
    static let url = AppPaths.support.appendingPathComponent("webcrypto.key")

    static let data: Data = {
        if let saved = try? Data(contentsOf: url), saved.count >= 16 { return saved }
        // Primeira vez: aproveita a chave que o WebKit já tinha criado no Chaveiro,
        // para as sessões abertas continuarem valendo. Sem ela, cria uma nova.
        let key = fromKeychain() ?? random(count: 16)
        FileManager.default.createFile(atPath: url.path, contents: key, attributes: [.posixPermissions: 0o600])
        return key
    }()

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

    private static func random(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
}
