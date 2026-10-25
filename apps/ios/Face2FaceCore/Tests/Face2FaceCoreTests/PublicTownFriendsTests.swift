import Foundation
import Testing

@testable import Face2FaceCore

@Test func townVisitorsRequireAnExplicitPublicStatusAndDisclosedProfile() async throws {
    var rows: [[String: Any]] = ["public", "private", "pending", "expired", "blocked", "future"].map {
        status in
        [
            "id": status, "status": status, "sharedInterests": ["music"],
            "expiresAt": "2026-10-26T00:00:00Z",
            "them": [
                "userId": "peer-\(status)", "name": "Person \(status)", "age": 25,
                "interests": ["music", "coffee"], "avatar": ["seed": "AAAAAAAAAAAAAAAAAAAAAA"],
            ],
        ]
    }
    rows.append([
        "id": "undisclosed", "status": "public", "sharedInterests": [],
        "expiresAt": "2026-10-26T00:00:00Z", "them": NSNull(),
    ])
    rows.append([
        "id": "missing-person-id", "status": "public", "sharedInterests": [],
        "expiresAt": "2026-10-26T00:00:00Z",
        "them": ["name": "No identity", "avatar": ["seed": "AAAAAAAAAAAAAAAAAAAAAA"]],
    ])
    let data = try JSONSerialization.data(withJSONObject: ["connections": rows])
    let transport = StubTransport([HTTPResponse(status: 200, data: data)])
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens("signed"), transport: transport)
    let friends = try await client.townPublicFriends()
    #expect(friends.map(\.id) == ["public"])
    #expect(friends[0].name == "Person public")
    #expect(friends[0].age == 25)
    #expect(friends[0].interests == ["music", "coffee"])
    #expect(friends[0].sharedInterests == ["music"])
    let requests = await transport.requests
    #expect(requests[0].url?.path == "/api/connections")
    #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer signed")
}

@Test func publicTownFriendCannotBeCreatedFromAnyPrivateStatusEvenWithIdentityData() throws {
    for status in ["private", "pending", "expired", "blocked", "PUBLIC", "unknown"] {
        let json = """
            {"id":"connection","status":"\(status)","sharedInterests":[],"expiresAt":"2026-10-26T00:00:00Z",
             "them":{"userId":"peer","name":"Hidden person","avatar":{"seed":"AAAAAAAAAAAAAAAAAAAAAA"}}}
            """
        let connection = try JSONDecoder().decode(TownConnection.self, from: Data(json.utf8))
        #expect(PublicTownFriend(connection: connection) == nil)
    }
}

@Test func publicTownFriendsRequireASession() async throws {
    let transport = StubTransport([])
    let client = APIClient(configuration: try configuration(), tokens: MemoryTokens(), transport: transport)
    await #expect(throws: APIError.unauthenticated) { try await client.townPublicFriends() }
    #expect(await transport.requests.isEmpty)
}
