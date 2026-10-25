import Foundation

/// Participant-safe inbox events. The API never includes the other person's identity.
public struct InboxNotification: Decodable, Sendable, Identifiable {
    public enum Kind: String, Decodable, Sendable {
        case encounter, connected
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
    public let sharedInterests: [String]

    private enum CodingKeys: String, CodingKey {
        case id, kind, createdAt, connectionId, postId, forumId, sharedInterests
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
        sharedInterests = try values.decodeIfPresent([String].self, forKey: .sharedInterests) ?? []
    }
}

extension APIClient {
    public func notifications() async throws -> [InboxNotification] {
        struct Inbox: Decodable { let notifications: [InboxNotification] }
        return try decode(
            Inbox.self,
            from: try await send(APIRequest(path: "api/notifications", authenticated: true))
        ).notifications
    }
}
