import Foundation
import Testing

@testable import Face2FaceCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

@Test(
    .enabled(if: ProcessInfo.processInfo.environment["F2F_FORUM_SMOKE_URL"] != nil), .timeLimit(.minutes(1)))
func liveForumRoundTrip() async throws {
    let base = try #require(ProcessInfo.processInfo.environment["F2F_FORUM_SMOKE_URL"])
    let config = try APIConfiguration(address: base, allowInsecureHTTP: true)
    var seed = URLRequest(url: config.baseURL.appendingPathComponent("api/dev/seed"))
    seed.httpMethod = "POST"
    seed.httpBody = Data("{}".utf8)
    seed.setValue("application/json", forHTTPHeaderField: "Content-Type")
    #expect(try await URLSessionTransport().send(seed).status == 200)
    let a = APIClient(configuration: config, tokens: MemoryTokens())
    let b = APIClient(configuration: config, tokens: MemoryTokens())
    try await a.signIn(email: "ava@seed.face2face.test", password: "face2face-seed-password")
    try await b.signIn(email: "ben@seed.face2face.test", password: "face2face-seed-password")
    let choices = try await a.interests()
    let coffee = try #require(choices.interests.first { $0.name == "coffee" }?.id)
    _ = try await a.replaceInterests([])
    #expect(try await a.townForums().isEmpty)
    _ = try await a.replaceInterests([coffee])
    _ = try await b.replaceInterests([])
    let forum = try #require(try await a.townForums().first)
    #expect(forum.interestId == coffee)
    let start = Date().addingTimeInterval(3600)
    let input = ForumPostInput(
        title: "Swift coffee demo", description: "Bring a little hello", location: "The square",
        startsAt: start, endsAt: start.addingTimeInterval(3600))
    let created = try await a.createForumPost(forumID: forum.id, input: input)
    #expect(created.isAuthor && !created.attending)
    await #expect(throws: APIError.server(404)) { try await b.forumPost(created.id) }
    await #expect(throws: APIError.server(404)) {
        try await b.createForumPost(forumID: forum.id, input: input)
    }
    _ = try await b.replaceInterests([coffee])
    #expect(try await b.forumPost(created.id).isAuthor == false)
    #expect(try await b.attendForumPost(created.id, attending: true).attendeeCount == 1)
    #expect(try await b.attendForumPost(created.id, attending: true).attendeeCount == 1)
    #expect(try await a.forumAttendees(created.id).first?.name == "Ben")
    await #expect(throws: APIError.forumNotAuthor) { try await b.updateForumPost(created.id, input: input) }
    let cleared = ForumPostInput(
        title: "A new coffee plan", description: nil, location: " ", startsAt: start, endsAt: nil)
    let updated = try await a.updateForumPost(created.id, input: cleared)
    #expect(updated.description == nil && updated.location == nil && updated.endsAt == nil)
    #expect(try await b.notifications().contains { $0.kind == .postUpdated && $0.postId == created.id })
    #expect(try await a.notifications().contains { $0.kind == .postRSVP && $0.postId == created.id })
    #expect(try await a.forumPosts(forumID: nil, cursor: nil).posts.contains { $0.id == created.id })
    _ = try await a.cancelForumPost(created.id)
    #expect(try await b.forumPost(created.id).cancelled)
    await #expect(throws: APIError.forumCancelled) {
        try await b.attendForumPost(created.id, attending: true)
    }
    #expect(try await b.attendForumPost(created.id, attending: false).attendeeCount == 0)
    #expect(try await b.notifications().contains { $0.kind == .postCancelled && $0.postId == created.id })
    #expect(try await a.forumPosts(forumID: nil, cursor: nil).posts.allSatisfy { $0.id != created.id })
    let past = try await a.createForumPost(
        forumID: forum.id,
        input: ForumPostInput(
            title: "Past event", description: nil, location: nil,
            startsAt: Date().addingTimeInterval(-7200), endsAt: Date().addingTimeInterval(-3600)))
    await #expect(throws: APIError.forumEventOver) { try await b.attendForumPost(past.id, attending: true) }
    _ = try await b.replaceInterests([])
    await #expect(throws: APIError.server(404)) { try await b.forumPost(created.id) }
    // Newly created interests have no forum until three different people select them.
    let name = "native demo circles"
    let added = try await a.addInterest(named: name)
    let newID = try #require(added.exactMatch(for: name)?.id)
    #expect(try await a.townForums().allSatisfy { $0.interestId != newID })
    await #expect(throws: APIError.server(404)) { try await a.forumPosts(forumID: newID, cursor: nil) }
    _ = try await b.addInterest(named: name)
    #expect(try await b.townForums().allSatisfy { $0.interestId != newID })
    let c = APIClient(configuration: config, tokens: MemoryTokens())
    try await c.signIn(email: "cleo@seed.face2face.test", password: "face2face-seed-password")
    _ = try await c.addInterest(named: name)
    #expect(try await a.townForums().contains { $0.interestId == newID })
    #expect(try await a.createForumPost(forumID: newID, input: input).forumId == newID)
}
