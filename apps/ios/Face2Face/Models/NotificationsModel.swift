import Face2FaceCore
import Foundation
import Observation

@MainActor
@Observable
final class NotificationsModel {
    private let session: SessionModel
    private(set) var notifications: [InboxNotification] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var error: String?
    var isPreview: Bool { session.isTownPreview }

    init(session: SessionModel) { self.session = session }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let result: [InboxNotification]
            #if DEBUG
                if isPreview {
                    let arguments = ProcessInfo.processInfo.arguments
                    let index = arguments.firstIndex(of: "-notifications-preview-state")
                    let state = index.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
                    if state == "error" { throw APIError.server(503) }
                    result = state == "empty" ? [] : try previewNotifications()
                } else {
                    result = try await session.client().notifications()
                }
            #else
                result = try await session.client().notifications()
            #endif
            try Task.checkCancellation()
            notifications = result.sorted {
                $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt
            }
            hasLoaded = true
        } catch is CancellationError {
            // Leaving the screen must not display a failed-request message.
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    #if DEBUG
        /// Offline art review only. Never mixed with a signed-in person's inbox.
        private func previewNotifications() throws -> [InboxNotification] {
            let formatter = ISO8601DateFormatter()
            let now = Date()
            let events: [(String, TimeInterval)] = [
                ("encounter", -180), ("connected", -2400), ("post_rsvp", -5400),
                ("post_updated", -90000), ("public", -100000), ("post_cancelled", -180000),
            ]
            let rows: [[String: Any]] = events.enumerated().map { index, event in
                [
                    "id": "preview-\(index)", "kind": event.0,
                    "createdAt": formatter.string(from: now.addingTimeInterval(event.1)),
                    "connectionId": "preview-connection", "postId": "preview-event", "forumId": "music",
                    "sharedInterests": event.0 == "encounter" ? ["music", "coffee"] : [],
                ]
            }
            return try JSONDecoder().decode(
                [InboxNotification].self, from: JSONSerialization.data(withJSONObject: rows))
        }
    #endif
}
