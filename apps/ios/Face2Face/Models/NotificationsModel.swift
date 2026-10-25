import Face2FaceCore
import Foundation
import Observation
import SwiftUI

/// The inbox and its unread count. The town owns one, so the bell and the inbox screen agree.
@MainActor
@Observable
final class NotificationsModel {
    private let session: SessionModel
    private(set) var notifications: [InboxNotification] = []
    private(set) var unreadCount = 0
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var error: String?
    private var previewSeen = false
    var isPreview: Bool { session.isTownPreview }

    init(session: SessionModel) { self.session = session }

    /// Updates the bell without loading the inbox screen's state.
    func refreshUnreadCount() async {
        guard let inbox = try? await loadInbox() else { return }
        setUnreadCount(inbox.unreadCount)
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let inbox = try await loadInbox()
            try Task.checkCancellation()
            notifications = inbox.notifications.sorted {
                $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt
            }
            setUnreadCount(inbox.unreadCount)
            hasLoaded = true
        } catch is CancellationError {
            // Leaving the screen must not display a failed-request message.
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    /// Call after the inbox has been shown.
    func markSeen() async {
        guard unreadCount > 0 else { return }
        if isPreview {
            previewSeen = true
            setUnreadCount(0)
            return
        }
        if let count = try? await session.client().markNotificationsSeen() { setUnreadCount(count) }
    }

    func delete(_ notification: InboxNotification) async {
        guard let index = notifications.firstIndex(where: { $0.id == notification.id }) else { return }
        withAnimation { _ = notifications.remove(at: index) }
        guard !isPreview else { return }
        do {
            setUnreadCount(try await session.client().deleteNotification(notification.id))
        } catch APIError.server(404) {
            // Already gone on the server.
        } catch {
            withAnimation { notifications.insert(notification, at: min(index, notifications.count)) }
            self.error = error.localizedDescription
        }
    }

    func clearAll() async {
        let previous = notifications
        withAnimation { notifications = [] }
        guard !isPreview else {
            setUnreadCount(0)
            return
        }
        do {
            try await session.client().clearNotifications()
            setUnreadCount(0)
        } catch {
            withAnimation { notifications = previous }
            self.error = error.localizedDescription
        }
    }

    private func setUnreadCount(_ count: Int) {
        unreadCount = count
        if !isPreview { PushNotifications.shared.setBadge(count) }
    }

    private func loadInbox() async throws -> NotificationInbox {
        #if DEBUG
            if isPreview {
                let arguments = ProcessInfo.processInfo.arguments
                let index = arguments.firstIndex(of: "-notifications-preview-state")
                let state = index.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
                if state == "error" { throw APIError.server(503) }
                return try previewInbox(empty: state == "empty")
            }
        #endif
        return try await session.client().notificationInbox()
    }

    #if DEBUG
        /// Offline art review only. Never mixed with a signed-in person's inbox.
        private func previewInbox(empty: Bool) throws -> NotificationInbox {
            let formatter = ISO8601DateFormatter()
            let now = Date()
            let events: [(String, TimeInterval)] = [
                ("encounter", -180), ("connected", -2400), ("post_rsvp", -5400),
                ("post_updated", -90000), ("public", -100000), ("post_cancelled", -180000),
            ]
            let rows: [[String: Any]] =
                empty
                ? []
                : events.enumerated().map { index, event in
                    [
                        "id": "preview-\(index)", "kind": event.0,
                        "createdAt": formatter.string(from: now.addingTimeInterval(event.1)),
                        "connectionId": "preview-connection",
                        "postId": event.0 == "post_cancelled"
                            ? "preview-cancelled"
                            : event.0 == "post_updated" ? "preview-past" : "preview-event",
                        "forumId": event.0 == "post_rsvp" ? "music" : "coffee",
                        "sharedInterests": event.0 == "encounter" ? ["music", "coffee"] : [],
                    ]
                }
            let unread = empty || previewSeen ? 0 : 2
            return try JSONDecoder().decode(
                NotificationInbox.self,
                from: JSONSerialization.data(withJSONObject: ["notifications": rows, "unreadCount": unread]))
        }
    #endif
}
