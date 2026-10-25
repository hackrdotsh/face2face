import Foundation
import UserNotifications

/// Requested navigation is not visibility: only the foreground chat owns suppression.
struct MessagePushVisibility {
    private(set) var chatID: String?
    private var accountID: String?
    private var owner: UUID?

    mutating func show(chatID: String, accountID: String, owner: UUID) {
        self.chatID = chatID
        self.accountID = accountID
        self.owner = owner
    }
    mutating func hide(owner: UUID) {
        guard self.owner == owner else { return }
        clear()
    }
    mutating func clear() {
        chatID = nil
        accountID = nil
        owner = nil
    }

    func options(kind: String?, chatID: String?, accountID: String) -> UNNotificationPresentationOptions {
        guard kind == "message" else { return [] }
        if let chatID, self.chatID == chatID, self.accountID == accountID { return [] }
        return [.banner, .list, .sound, .badge]
    }
}
