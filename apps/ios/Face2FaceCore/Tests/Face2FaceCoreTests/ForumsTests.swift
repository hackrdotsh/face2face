import Foundation
import Testing

@testable import Face2FaceCore

let forumPostFixture = #"""
    {"id":"post","forumId":"coffee","title":"Coffee in the square","description":null,"location":null,
     "startsAt":"2026-10-26T12:00:00.000Z","endsAt":null,"createdAt":"2026-10-25T10:00:00Z","updatedAt":"2026-10-25T10:00:00Z",
     "author":{"userId":"author","name":"Ava","avatar":{"seed":"AAAAAAAAAAAAAAAAAAAAAA"}},
     "attendeeCount":1,"attendeePreview":[],"attending":false,"isAuthor":true,"edited":false,"past":false,"cancelled":false}
    """#

@Test func forumInputsValidateLimitsAndExplicitlyClearOptionalFields() throws {
    let start = Date(timeIntervalSince1970: 2_000_000_000)
    let value = ForumPostInput(
        title: "  A little plan  ", description: "  ", location: nil, startsAt: start, endsAt: nil)
    #expect(value.validationErrors.isEmpty)
    let fields = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    #expect(fields["title"] as? String == "A little plan")
    #expect(fields["description"] is NSNull && fields["location"] is NSNull && fields["endsAt"] is NSNull)
    let invalid = ForumPostInput(
        title: String(repeating: "😀", count: 61), description: String(repeating: "a", count: 4001),
        location: String(repeating: "a", count: 201), startsAt: start, endsAt: start.addingTimeInterval(-60))
    #expect(Set(invalid.validationErrors.keys) == ["title", "description", "location", "endsAt"])
    #expect(
        ForumPostInput(title: "", description: nil, location: nil, startsAt: start, endsAt: start)
            .validationErrors["title"] != nil)
}

@Test func forumsUseCorrectPaginationDirectionsAndBearerAuth() async throws {
    let transport = StubTransport([
        response(json: "{\"posts\":[\(forumPostFixture)],\"hasMore\":true}"),
        response(json: #"{"posts":[],"hasMore":false}"#),
        response(
            json:
                #"{"maxSelected":10,"interests":[{"id":"coffee","name":"coffee","memberCount":4,"selected":true}]}"#
        ),
    ])
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens("signed"), transport: transport)
    let page = try await client.forumPosts(forumID: nil, cursor: "older")
    #expect(page.posts[0].startDate != nil && page.posts[0].endDate == nil)
    _ = try await client.forumPosts(forumID: "coffee", cursor: "before")
    #expect(try await client.replaceInterests(["coffee"]).maxSelected == 10)
    let requests = await transport.requests
    #expect(requests[0].url?.path == "/api/posts")
    #expect(
        URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.name
            == "after")
    #expect(requests[1].url?.path == "/api/forums/coffee/posts")
    #expect(
        URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.name
            == "before")
    #expect(requests[2].httpMethod == "PUT" && requests[2].url?.path == "/api/interests")
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer signed" })
}

@Test func forumMutationsUseServerOwnedAuthorAndCorrectVerbs() async throws {
    let transport = StubTransport(
        Array(repeating: response(json: "{\"post\":\(forumPostFixture)}"), count: 5))
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens("signed"), transport: transport)
    let input = ForumPostInput(
        title: "Coffee", description: nil, location: nil, startsAt: Date(), endsAt: nil)
    _ = try await client.createForumPost(forumID: "coffee", input: input)
    _ = try await client.updateForumPost("post", input: input)
    _ = try await client.attendForumPost("post", attending: true)
    _ = try await client.attendForumPost("post", attending: false)
    _ = try await client.cancelForumPost("post")
    let requests = await transport.requests
    #expect(requests.map(\.httpMethod) == ["POST", "PATCH", "PUT", "DELETE", "DELETE"])
    let body = try #require(JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: Any])
    #expect(body["authorId"] == nil && body["userId"] == nil)
    #expect(requests[2].url?.path == "/api/posts/post/rsvp")
}

@Test func forumRefusalsAreNotMistakenForSuccessOrAnEmptyFeed() async throws {
    let transport = StubTransport([
        response(409, json: #"{"error":"event_over"}"#),
        response(409, json: #"{"error":"post_cancelled"}"#),
        response(403, json: #"{"error":"not_author"}"#),
        response(404, json: #"{"error":"not_found"}"#),
    ])
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens("signed"), transport: transport)
    await #expect(throws: APIError.forumEventOver) {
        try await client.attendForumPost("post", attending: true)
    }
    await #expect(throws: APIError.forumCancelled) {
        try await client.attendForumPost("post", attending: true)
    }
    await #expect(throws: APIError.forumNotAuthor) { try await client.cancelForumPost("post") }
    await #expect(throws: APIError.server(404)) {
        try await client.forumPosts(forumID: "unjoined", cursor: nil)
    }
    await #expect(throws: APIError.invalidResponse) { try await client.forumPost("../another") }
    #expect(await transport.requests.count == 4)
}
