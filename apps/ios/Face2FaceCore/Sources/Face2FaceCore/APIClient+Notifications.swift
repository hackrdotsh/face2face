import Foundation

public struct PushSetupStatus: Decodable, Sendable {
    public let providerConfigured: Bool
    public let registeredDeviceCount: Int
    public let topic: String?
}

extension APIClient {
    public func pushSetupStatus() async throws -> PushSetupStatus {
        try decode(
            PushSetupStatus.self,
            from: try await send(APIRequest(path: "api/notifications/push-status", authenticated: true)))
    }
}

/// Participant-safe inbox events. The API never includes the other person's identity.
public struct InboxNotification: Decodable, Sendable, Identifiable {
    public enum Kind: String, Decodable, Sendable {
        case encounter, connected, message
        case publicConnection = "public"
        case postUpdated = "post_updated"
        case postCancelled = "post_cancelled"
        case postRSVP = "post_rsvp"
        case unknown

        public init(from decoder: any Decoder) throws {
            let value = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: value) ?? .unknown
        }
    }

    public let id: String
    public let kind: Kind
    public let createdAt: Date
    public let connectionId: String?
    public let postId: String?
    public let forumId: String?
    /// Set for `message`. The chat ID is the connection ID.
    public let chatId: String?
    public let sharedInterests: [String]

    private enum CodingKeys: String, CodingKey {
        case id, kind, createdAt, connectionId, postId, forumId, chatId, sharedInterests
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        kind = try values.decode(Kind.self, forKey: .kind)
        let timestamp = try values.decode(String.self, forKey: .createdAt)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fractional = formatter.date(from: timestamp)
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = fractional ?? formatter.date(from: timestamp) else {
            throw DecodingError.dataCorruptedError(
                forKey: .createdAt, in: values,
                debugDescription: "Expected an ISO 8601 notification timestamp")
        }
        createdAt = date
        connectionId = try values.decodeIfPresent(String.self, forKey: .connectionId)
        postId = try values.decodeIfPresent(String.self, forKey: .postId)
        forumId = try values.decodeIfPresent(String.self, forKey: .forumId)
        chatId = try values.decodeIfPresent(String.self, forKey: .chatId)
        sharedInterests = try values.decodeIfPresent([String].self, forKey: .sharedInterests) ?? []
    }
}

public struct NotificationInbox: Decodable, Sendable {
    public let notifications: [InboxNotification]
    /// Notifications that arrived after the inbox was last seen.
    public let unreadCount: Int

    private enum CodingKeys: String, CodingKey { case notifications, unreadCount }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        notifications = try values.decode([InboxNotification].self, forKey: .notifications)
        unreadCount = try values.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
    }
}

/// Which APNs gateway a device token belongs to. Development-signed builds use the sandbox.
public enum PushEnvironment: String, Encodable, Sendable {
    case sandbox, production
}

extension APIClient {
    public func notifications() async throws -> [InboxNotification] {
        try await notificationInbox().notifications
    }

    public func notificationInbox() async throws -> NotificationInbox {
        try decode(
            NotificationInbox.self,
            from: try await send(APIRequest(path: "api/notifications", authenticated: true)))
    }

    /// Marks everything in the inbox as seen. Returns the new unread count.
    public func markNotificationsSeen() async throws -> Int {
        try decode(
            UnreadCount.self,
            from: try await post("api/notifications/seen", [String: String](), authenticated: true)
        ).unreadCount
    }

    /// Deletes one notification for good. Returns the new unread count.
    public func deleteNotification(_ id: String) async throws -> Int {
        guard !id.isEmpty, id.utf8.count <= 200,
            id.unicodeScalars.allSatisfy({
                $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-")
            })
        else { throw APIError.invalidResponse }
        return try decode(
            UnreadCount.self,
            from: try await send(
                APIRequest(path: "api/notifications/" + id, method: "DELETE", authenticated: true))
        ).unreadCount
    }

    public func clearNotifications() async throws {
        _ = try await send(APIRequest(path: "api/notifications", method: "DELETE", authenticated: true))
    }

    public func registerPushDevice(token: Data, environment: PushEnvironment) async throws {
        struct Body: Encodable { let environment: PushEnvironment }
        _ = try await send(
            APIRequest(
                path: try Self.devicePath(token), method: "PUT",
                body: try JSONEncoder().encode(Body(environment: environment)), authenticated: true))
    }

    public func unregisterPushDevice(token: Data) async throws {
        _ = try await send(
            APIRequest(path: try Self.devicePath(token), method: "DELETE", authenticated: true))
    }

    private struct UnreadCount: Decodable { let unreadCount: Int }

    private static func devicePath(_ token: Data) throws -> String {
        guard (32...100).contains(token.count) else { throw APIError.invalidResponse }
        return "api/notifications/devices/" + token.map { String(format: "%02x", $0) }.joined()
    }
}
