import Foundation
import Testing

@testable import Face2FaceCore

@Test func inboxDecodesEveryServerEventAndUsesBearerAuth() async throws {
    let transport = StubTransport([
        response(
            json: #"""
                {"notifications":[
                  {"id":"1","kind":"encounter","createdAt":"2026-10-25T10:00:00.123Z",
                   "connectionId":"chance","sharedInterests":["music"],"expiresAt":"2026-10-26T10:00:00Z"},
                  {"id":"2","kind":"connected","createdAt":"2026-10-25T09:00:00Z","connectionId":"friend"},
                  {"id":"3","kind":"public","createdAt":"2026-10-25T08:00:00Z","connectionId":"friend"},
                  {"id":"4","kind":"post_updated","createdAt":"2026-10-24T12:00:00Z","postId":"post","forumId":"forum"},
                  {"id":"5","kind":"post_cancelled","createdAt":"2026-10-24T11:00:00Z","postId":"post","forumId":"forum"},
                  {"id":"6","kind":"post_rsvp","createdAt":"2026-10-24T10:00:00Z","postId":"post","forumId":"forum"},
                  {"id":"7","kind":"future_event","createdAt":"2026-10-24T09:00:00Z","futureField":"ignored"}
                ]}
                """#)
    ])
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens("signed"), transport: transport)
    let inbox = try await client.notifications()
    #expect(
        inbox.map(\.kind) == [
            .encounter, .connected, .publicConnection, .postUpdated, .postCancelled, .postRSVP, .unknown,
        ])
    #expect(inbox[0].sharedInterests == ["music"])
    #expect(inbox[1].sharedInterests.isEmpty)
    #expect(inbox[4].forumId == "forum")
    #expect(inbox[4].connectionId == nil)
    #expect(inbox[0].createdAt > inbox[1].createdAt)
    let requests = await transport.requests
    #expect(requests.count == 1)
    #expect(requests.first?.url?.path == "/api/notifications")
    #expect(requests.first?.httpMethod == "GET")
    #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer signed")
}

@Test func inboxSupportsEmptyResponsesAndRequiresSignIn() async throws {
    let transport = StubTransport([response(json: #"{"notifications":[]}"#)])
    let tokens = MemoryTokens()
    let client = APIClient(configuration: try configuration(), tokens: tokens, transport: transport)
    await #expect(throws: APIError.unauthenticated) { try await client.notifications() }
    #expect(await transport.requests.isEmpty)
    await tokens.save("signed")
    #expect(try await client.notifications().isEmpty)
}

@Test func inboxDoesNotTurnFailedLoadsIntoAnEmptyInbox() async throws {
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens("signed"),
        transport: StubTransport([
            response(503, json: #"{"error":"unavailable"}"#),
            response(json: #"{"notifications":[{"id":"1","kind":"connected","createdAt":"not-a-date"}]}"#),
        ]))
    await #expect(throws: APIError.server(503)) { try await client.notifications() }
    await #expect(throws: APIError.invalidResponse) { try await client.notifications() }
}
