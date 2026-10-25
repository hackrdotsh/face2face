import Foundation

/// Identity disclosed to forum members, not proof of a public connection.
public struct ForumPerson: Decodable, Sendable, Identifiable {
    public var id: String { userId }
    public let userId: String
    public let name: String
    public let avatar: Avatar
}

public struct ForumPost: Decodable, Sendable, Identifiable {
    public let id: String
    public let forumId: String
    public let title: String
    public let description: String?
    public let location: String?
    public let startsAt: String
    public let endsAt: String?
    public let createdAt: String
    public let updatedAt: String
    public let author: ForumPerson
    public let attendeeCount: Int
    public let attendeePreview: [ForumPerson]
    public let attending: Bool
    public let isAuthor: Bool
    public let edited: Bool
    public let past: Bool
    public let cancelled: Bool
    public var startDate: Date? { Self.date(startsAt) }
    public var endDate: Date? { endsAt.flatMap(Self.date) }

    private static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

public struct ForumPostPage: Decodable, Sendable {
    public let posts: [ForumPost]
    public let hasMore: Bool
}

/// Full editor payload. Optional fields encode null so edits can clear old values.
public struct ForumPostInput: Encodable, Sendable, Equatable {
    public let title: String
    public let description: String?
    public let location: String?
    public let startsAt: String
    public let endsAt: String?

    public init(title: String, description: String?, location: String?, startsAt: Date, endsAt: Date?) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.description = Self.optional(description)
        self.location = Self.optional(location)
        let formatter = ISO8601DateFormatter()
        self.startsAt = startsAt.timeIntervalSince1970.isFinite ? formatter.string(from: startsAt) : ""
        self.endsAt = endsAt.map { $0.timeIntervalSince1970.isFinite ? formatter.string(from: $0) : "" }
    }
    public var validationErrors: [String: String] {
        var errors: [String: String] = [:]
        if title.isEmpty || title.utf16.count > 120 { errors["title"] = "Add a title of 1–120 characters." }
        if (description?.utf16.count ?? 0) > 4000 {
            errors["description"] = "Keep the description within 4,000 characters."
        }
        if (location?.utf16.count ?? 0) > 200 { errors["location"] = "Keep the place within 200 characters." }
        let formatter = ISO8601DateFormatter()
        if let start = formatter.date(from: startsAt) {
            if let endsAt, let end = formatter.date(from: endsAt) {
                if end < start { errors["endsAt"] = "The end must be at or after the start." }
            } else if endsAt != nil {
                errors["endsAt"] = "Choose a valid end time."
            }
        } else {
            errors["startsAt"] = "Choose a valid start time."
        }
        return errors
    }
    private static func optional(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
    private enum Keys: String, CodingKey { case title, description, location, startsAt, endsAt }
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Keys.self)
        try values.encode(title, forKey: .title)
        try values.encode(description, forKey: .description)
        try values.encode(location, forKey: .location)
        try values.encode(startsAt, forKey: .startsAt)
        try values.encode(endsAt, forKey: .endsAt)
    }
}

/// Implemented by the authenticated HTTP client and the explicitly labelled offline preview.
public protocol ForumRepository: InterestRepository {
    func townForums() async throws -> [TownForum]
    func forumPosts(forumID: String?, cursor: String?) async throws -> ForumPostPage
    func forumPost(_ id: String) async throws -> ForumPost
    func createForumPost(forumID: String, input: ForumPostInput) async throws -> ForumPost
    func updateForumPost(_ id: String, input: ForumPostInput) async throws -> ForumPost
    func cancelForumPost(_ id: String) async throws -> ForumPost
    func attendForumPost(_ id: String, attending: Bool) async throws -> ForumPost
    func forumAttendees(_ id: String) async throws -> [ForumPerson]
}

extension APIClient: ForumRepository {
    public func forumPosts(forumID: String?, cursor: String? = nil) async throws -> ForumPostPage {
        let path = try forumID.map { "api/forums/\(try Self.forumComponent($0))/posts" } ?? "api/posts"
        let query = cursor.map { [URLQueryItem(name: forumID == nil ? "after" : "before", value: $0)] } ?? []
        return try decode(
            ForumPostPage.self,
            from: try await send(APIRequest(path: path, query: query, authenticated: true)))
    }
    public func forumPost(_ id: String) async throws -> ForumPost {
        struct Result: Decodable { let post: ForumPost }
        return try decode(
            Result.self,
            from: try await send(
                APIRequest(path: "api/posts/\(try Self.forumComponent(id))", authenticated: true))
        ).post
    }
    public func createForumPost(forumID: String, input: ForumPostInput) async throws -> ForumPost {
        try await writeForumPost(
            path: "api/forums/\(try Self.forumComponent(forumID))/posts", method: "POST", input: input)
    }
    public func updateForumPost(_ id: String, input: ForumPostInput) async throws -> ForumPost {
        try await writeForumPost(
            path: "api/posts/\(try Self.forumComponent(id))", method: "PATCH", input: input)
    }
    private func writeForumPost(path: String, method: String, input: ForumPostInput) async throws -> ForumPost
    {
        guard input.validationErrors.isEmpty else { throw APIError.invalidFields(input.validationErrors) }
        struct Result: Decodable { let post: ForumPost }
        return try decode(
            Result.self,
            from: try await send(
                APIRequest(
                    path: path, method: method,
                    body: try JSONEncoder().encode(input), authenticated: true))
        ).post
    }
    public func cancelForumPost(_ id: String) async throws -> ForumPost {
        struct Result: Decodable { let post: ForumPost }
        return try decode(
            Result.self,
            from: try await send(
                APIRequest(
                    path: "api/posts/\(try Self.forumComponent(id))", method: "DELETE", authenticated: true))
        ).post
    }
    public func attendForumPost(_ id: String, attending: Bool) async throws -> ForumPost {
        struct Result: Decodable { let post: ForumPost }
        return try decode(
            Result.self,
            from: try await send(
                APIRequest(
                    path: "api/posts/\(try Self.forumComponent(id))/rsvp",
                    method: attending ? "PUT" : "DELETE", authenticated: true))
        ).post
    }
    public func forumAttendees(_ id: String) async throws -> [ForumPerson] {
        struct Result: Decodable { let attendees: [ForumPerson] }
        return try decode(
            Result.self,
            from: try await send(
                APIRequest(path: "api/posts/\(try Self.forumComponent(id))/attendees", authenticated: true))
        ).attendees
    }
    private static func forumComponent(_ id: String) throws -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard !id.isEmpty, id.utf8.count <= 256, id != ".", id != "..",
            id.unicodeScalars.allSatisfy(allowed.contains)
        else { throw APIError.invalidResponse }
        return id
    }
}
