import Foundation

struct Account: Codable, Equatable {
    enum Site: String, Codable { case whatsapp, instagram }

    let id: UUID
    var name: String
    /// nil nas guias salvas antes de existir o Instagram (= WhatsApp).
    var site: Site?
}

/// Lista de contas (números) persistida no UserDefaults. Cada conta tem um
/// armazenamento web isolado, identificado pelo `id`.
final class AccountStore {
    static let shared = AccountStore()

    private let key = "accounts"
    private let closedKey = "closedAccounts"
    private(set) var accounts: [Account]
    /// A lista salva não existia ou não pôde ser lida: começou com uma guia nova.
    private(set) var startedFresh = false
    /// Guias fechadas cujos dados ainda não foram apagados do disco.
    private(set) var closed: Set<UUID>

    private init() {
        let closedIDs = UserDefaults.standard.stringArray(forKey: closedKey) ?? []
        closed = Set(closedIDs.compactMap(UUID.init(uuidString:)))
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Account].self, from: data),
           !saved.isEmpty {
            accounts = saved
        } else {
            accounts = [Account(id: UUID(), name: "WhatsApp")]
            startedFresh = true
            save()
        }
    }

    @discardableResult
    func add(name: String, id: UUID = UUID(), site: Account.Site? = nil) -> Account {
        let account = Account(id: id, name: name, site: site)
        accounts.append(account)
        save()
        return account
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[i].name = name
        save()
    }

    /// Tira a guia da lista e anota o id: só dados de guias anotadas aqui podem ser
    /// apagados sem guia (ver MainWindowController.reconcileDataStores).
    func remove(_ id: UUID) {
        accounts.removeAll { $0.id == id }
        closed.insert(id)
        save()
    }

    /// Os dados da guia fechada já foram apagados.
    func forgetClosed(_ id: UUID) {
        closed.remove(id)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: key)
        }
        UserDefaults.standard.set(closed.map(\.uuidString), forKey: closedKey)
    }
}
