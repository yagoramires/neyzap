import UserNotifications

/// Ponte entre as notificações do WhatsApp Web e a Central de Notificações.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// (id da conta, id da notificação no JS)
    var onClick: ((UUID, String) -> Void)?

    private let center = UNUserNotificationCenter.current()

    func setup() {
        center.delegate = self
    }

    /// Pede permissão à Central de Notificações (só no modo "notificações do sistema").
    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error { Log.write("notificações do sistema não autorizadas: \(error.localizedDescription)") }
        }
    }

    func post(identifier: String, accountID: UUID, jsID: String, title: String, subtitle: String?, body: String, tag: String, silent: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle { content.subtitle = subtitle }
        content.body = body
        content.sound = silent ? nil : .default
        content.threadIdentifier = "\(accountID.uuidString)-\(tag)"
        content.userInfo = ["account": accountID.uuidString, "js": jsID]
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    func remove(_ identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let account = (info["account"] as? String).flatMap(UUID.init(uuidString:)),
           let jsID = info["js"] as? String {
            DispatchQueue.main.async { self.onClick?(account, jsID) }
        }
        completionHandler()
    }
}
