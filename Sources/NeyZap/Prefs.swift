import Foundation

/// Preferências do app no UserDefaults. As chaves guardam o que o usuário já escolheu:
/// não renomear.
enum Prefs {
    private static let defaults = UserDefaults.standard

    /// Desligado: balões do próprio NeyZap. Ligado: Central de Notificações.
    static var systemNotifications: Bool {
        get { defaults.bool(forKey: "systemNotifications") }
        set { defaults.set(newValue, forKey: "systemNotifications") }
    }
    static var showStatusItem: Bool {
        get { defaults.bool(forKey: "showStatusItem") }
        set { defaults.set(newValue, forKey: "showStatusItem") }
    }
    static var sideBySide: Bool {
        get { defaults.bool(forKey: "sideBySide") }
        set { defaults.set(newValue, forKey: "sideBySide") }
    }
    static var pinned: Bool {
        get { defaults.bool(forKey: "pinned") }
        set { defaults.set(newValue, forKey: "pinned") }
    }
    static var selectedAccount: Int {
        get { defaults.integer(forKey: "selectedAccount") }
        set { defaults.set(newValue, forKey: "selectedAccount") }
    }
    static var zoom: Double {
        get { defaults.object(forKey: "zoom") as? Double ?? 1 }
        set { defaults.set(newValue, forKey: "zoom") }
    }
    /// Só se ligam com `defaults write local.neyzap <chave> -bool true`.
    static var debugBridge: Bool { defaults.bool(forKey: "debugBridge") }
    /// Abre o WhatsApp Web puro, sem nada injetado.
    static var debugNoInject: Bool { defaults.bool(forKey: "debugNoInject") }
}

/// Preferências de uma guia. `AccountStore.remove` apaga todas junto com a guia.
struct AccountPrefs {
    let id: UUID

    /// Última tentativa de ligar a sincronização em segundo plano (dando certo ou não).
    var bgSyncCheckedAt: Date? {
        get { date("bgSyncCheckedAt") }
        nonmutating set { setDate(newValue, "bgSyncCheckedAt") }
    }
    /// Última vez que a guia (desativada) ficou conectada.
    var lastOnline: Date? {
        get { date("lastOnline") }
        nonmutating set { setDate(newValue, "lastOnline") }
    }

    func clear() {
        bgSyncCheckedAt = nil
        lastOnline = nil
    }

    private func key(_ name: String) -> String { "\(name)-\(id.uuidString)" }
    private func date(_ name: String) -> Date? { UserDefaults.standard.object(forKey: key(name)) as? Date }
    private func setDate(_ value: Date?, _ name: String) {
        if let value { UserDefaults.standard.set(value, forKey: key(name)) } else { UserDefaults.standard.removeObject(forKey: key(name)) }
    }
}
