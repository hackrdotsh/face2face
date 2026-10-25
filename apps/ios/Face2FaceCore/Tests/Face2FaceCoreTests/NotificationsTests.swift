import Foundation
import Testing

@testable import Face2FaceCore

@Test func pushSetupDiagnosticsAreAuthenticatedAndContainNoDeviceToken() async throws {
    let transport = StubTransport([
        response(
            json: #"{"providerConfigured":true,"registeredDeviceCount":2,"topic":"systems.rocky.face2face"}"#)
    ])
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens("signed"), transport: transport)
    let status = try await client.pushSetupStatus()
    #expect(status.providerConfigured && status.registeredDeviceCount == 2)
    #expect(status.topic == "systems.rocky.face2face")
    let request = try #require(await transport.requests.first)
    #expect(request.url?.path == "/api/notifications/push-status")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer signed")
}

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
                  {"id":"8","kind":"message","createdAt":"2026-10-24T09:30:00Z","chatId":"chat"},
                  {"id":"7","kind":"future_event","createdAt":"2026-10-24T09:00:00Z","futureField":"ignored"}
                ]}
                """#)
    ])
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens("signed"), transport: transport)
    let inbox = try await client.notifications()
    #expect(
        inbox.map(\.kind) == [
            .encounter, .connected, .publicConnection, .postUpdated, .postCancelled, .postRSVP, .message,
            .unknown,
        ])
    #expect(inbox[0].sharedInterests == ["music"])
    #expect(inbox[1].sharedInterests.isEmpty)
    #expect(inbox[4].forumId == "forum")
    #expect(inbox[4].connectionId == nil)
    #expect(inbox[6].chatId == "chat")
    #expect(inbox[0].chatId == nil)
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

@Test func inboxCarriesTheUnreadCount() async throws {
    let transport = StubTransport([
        response(json: #"{"notifications":[],"unreadCount":3}"#),
        response(json: #"{"notifications":[]}"#),
    ])
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens("signed"), transport: transport)
    #expect(try await client.notificationInbox().unreadCount == 3)
    #expect(try await client.notificationInbox().unreadCount == 0)
}

@Test func seenDeleteAndClearUseTheirOwnRoutes() async throws {
    let transport = StubTransport([
        response(json: #"{"unreadCount":0}"#),
        response(json: #"{"unreadCount":2}"#),
        response(json: #"{"unreadCount":0}"#),
    ])
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens("signed"), transport: transport)
    #expect(try await client.markNotificationsSeen() == 0)
    #expect(try await client.deleteNotification("4f6c-9a") == 2)
    try await client.clearNotifications()
    await #expect(throws: APIError.invalidResponse) { try await client.deleteNotification("") }
    await #expect(throws: APIError.invalidResponse) { try await client.deleteNotification("../devices") }

    let requests = await transport.requests
    #expect(requests.map(\.httpMethod) == ["POST", "DELETE", "DELETE"])
    #expect(
        requests.map(\.url?.path) == [
            "/api/notifications/seen", "/api/notifications/4f6c-9a", "/api/notifications",
        ])
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer signed" })
}

@Test func pushDevicesAreSentAsLowercaseHex() async throws {
    let transport = StubTransport([response(204, json: ""), response(204, json: "")])
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens("signed"), transport: transport)
    let token = Data((0..<32).map { UInt8($0 * 8) })
    try await client.registerPushDevice(token: token, environment: .sandbox)
    try await client.unregisterPushDevice(token: token)
    await #expect(throws: APIError.invalidResponse) {
        try await client.registerPushDevice(token: Data([1, 2, 3]), environment: .production)
    }

    let requests = await transport.requests
    let path = "/api/notifications/devices/" + token.map { String(format: "%02x", $0) }.joined()
    #expect(requests.map(\.url?.path) == [path, path])
    #expect(requests.map(\.httpMethod) == ["PUT", "DELETE"])
    #expect(path.hasSuffix("0008101820283038404850586068707880889098a0a8b0b8c0c8d0d8e0e8f0f8"))
    #expect(requests.first?.httpBody == Data(#"{"environment":"sandbox"}"#.utf8))
}
