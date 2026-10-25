import Foundation

public struct TownForum: Decodable, Sendable, Identifiable {
    public let id: String
    public let interestId: String
    public let interestName: String
    public let upcomingPostCount: Int
}

/// Only the participant-facing fields needed on the landing page. No hidden peer identity.
public struct TownConnection: Decodable, Sendable, Identifiable {
    public let id: String
    public let status: String
    public let sharedInterests: [String]
    public let them: PublicPerson?
    public let expiresAt: String

    public struct PublicPerson: Decodable, Sendable {
        public let name: String
        public let avatar: Avatar
    }

    public var isFriend: Bool { status == "private" || status == "public" }
    public var isPending: Bool { status == "pending" }
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
}
