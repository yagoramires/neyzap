import Foundation

struct Account: Codable, Equatable {
    let id: UUID
    var name: String
}

/// Lista de contas (números) persistida no UserDefaults. Cada conta tem um
/// armazenamento web isolado, identificado pelo `id`.
final class AccountStore {
    static let shared = AccountStore()

    private let key = "accounts"
    private(set) var accounts: [Account]

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Account].self, from: data),
           !saved.isEmpty {
            accounts = saved
        } else {
            accounts = [Account(id: UUID(), name: "Pessoal"), Account(id: UUID(), name: "Trabalho")]
            save()
        }
    }

    @discardableResult
    func add(name: String) -> Account {
        let account = Account(id: UUID(), name: name)
        accounts.append(account)
        save()
        return account
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[i].name = name
        save()
    }

    func remove(_ id: UUID) {
        accounts.removeAll { $0.id == id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
