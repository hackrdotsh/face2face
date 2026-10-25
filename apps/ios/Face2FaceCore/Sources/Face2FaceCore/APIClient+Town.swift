import Foundation

public struct TownForum: Decodable, Sendable, Identifiable {
    public let id: String
    public let interestId: String
    public let interestName: String
    public let upcomingPostCount: Int
}

/// Only the participant-facing fields needed on the landing page. No hidden peer identity.
public struct TownConnection: Decodable, Sendable, Identifiable {
    public struct Viewer: Decodable, Sendable {
        public let decision: ConnectionDecision?
        public let decidedAt: String?
        public let publicAt: String?
    }
    public let id: String
    public let status: String
    public let sharedInterests: [String]
    public let them: PublicPerson?
    public let expiresAt: String
    public let createdAt: String?
    public let you: Viewer?

    public var expiryDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: expiresAt) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: expiresAt)
    }

    public struct PublicPerson: Decodable, Sendable {
        public let userId: String?
        public let name: String
        public let avatar: Avatar
        public let age: Int?
        public let interests: [String]?
    }

    public var isFriend: Bool { status == "private" || status == "public" }
    public var isPending: Bool { status == "pending" }

    public var publicTownFriend: PublicTownFriend? { PublicTownFriend(connection: self) }
}

/// A renderer can only receive a friend through the explicit public-status gate.
/// Never represents online presence or a person's physical location.
public struct PublicTownFriend: Identifiable, Sendable, Equatable {
    public let id: String
    public let userId: String
    public let name: String
    public let avatar: Avatar
    public let age: Int?
    public let interests: [String]
    public let sharedInterests: [String]

    public init?(connection: TownConnection) {
        guard connection.status == "public", let person = connection.them,
            let userId = person.userId, !userId.isEmpty,
            !person.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        id = connection.id
        self.userId = userId
        name = person.name
        avatar = person.avatar
        age = person.age
        interests = person.interests ?? []
        sharedInterests = connection.sharedInterests
    }
}

extension APIClient {
    public func townForums() async throws -> [TownForum] {
        struct Result: Decodable { let forums: [TownForum] }
        return try decode(
            Result.self, from: try await send(APIRequest(path: "api/forums", authenticated: true))
        ).forums
    }

    public func townConnections() async throws -> [TownConnection] {
        struct Result: Decodable { let connections: [TownConnection] }
        return try decode(
            Result.self, from: try await send(APIRequest(path: "api/connections", authenticated: true))
        ).connections
    }

    public func townPublicFriends() async throws -> [PublicTownFriend] {
        try await townConnections().compactMap(\.publicTownFriend)
    }
}
