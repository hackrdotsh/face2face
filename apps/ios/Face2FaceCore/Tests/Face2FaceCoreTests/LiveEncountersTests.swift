import Foundation
import Testing

@testable import Face2FaceCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

@Test(
    .enabled(if: ProcessInfo.processInfo.environment["F2F_ENCOUNTER_SMOKE_URL"] != nil),
    .timeLimit(.minutes(1)))
func liveEncounterRoundTrip() async throws {
    let base = try #require(ProcessInfo.processInfo.environment["F2F_ENCOUNTER_SMOKE_URL"])
    let config = try APIConfiguration(address: base, allowInsecureHTTP: true)
    _ = try await encounterPost(config, path: "api/dev/seed", body: [:])
    let a = APIClient(configuration: config, tokens: MemoryTokens())
    let b = APIClient(configuration: config, tokens: MemoryTokens())
    let outsider = APIClient(configuration: config, tokens: MemoryTokens())
    try await a.signIn(email: "ava@seed.face2face.test", password: "face2face-seed-password")
    try await b.signIn(email: "ben@seed.face2face.test", password: "face2face-seed-password")
    try await outsider.signIn(email: "noor@seed.face2face.test", password: "face2face-seed-password")
    func chance() async throws -> String {
        let data = try await encounterPost(
            config, path: "api/dev/encounters", body: ["firstUserId": "seed-ava", "secondUserId": "seed-ben"])
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["simulated"] as? Bool == true)
        return try #require((object["connection"] as? [String: Any])?["id"] as? String)
    }
    let declinedID = try await chance()
    await #expect(throws: APIError.server(404)) {
        try await outsider.decideConnection(declinedID, decision: .accepted)
    }
    #expect(try await a.decideConnection(declinedID, decision: .declined).status == "expired")
    #expect(try await b.townConnections().allSatisfy { $0.id != declinedID })
    await #expect(throws: APIError.server(404)) { try await b.chat(declinedID) }
    let id = try await chance()
    #expect(id != declinedID)
    let firstYes = try await a.decideConnection(id, decision: .accepted)
    #expect(firstYes.isPending && firstYes.you?.decision == .accepted && firstYes.them == nil)
    await #expect(throws: APIError.server(404)) { try await a.chat(id) }
    await #expect(throws: APIError.chanceAlreadyAnswered) {
        try await a.decideConnection(id, decision: .accepted)
    }
    let secondYes = try await b.decideConnection(id, decision: .accepted)
    #expect(secondYes.status == "private" && secondYes.them == nil && secondYes.publicTownFriend == nil)
    #expect(try await a.townConnections().contains { $0.id == id && $0.status == "private" })
    #expect(try await a.chat(id).title == "Anonymous connection")
    #expect(try await b.chats().contains { $0.id == id })
}

private func encounterPost(_ config: APIConfiguration, path: String, body: [String: String]) async throws
    -> Data
{
    var request = URLRequest(url: config.baseURL.appendingPathComponent(path))
    request.httpMethod = "POST"
    request.httpBody = try JSONEncoder().encode(body)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let response = try await URLSessionTransport().send(request)
    guard (200..<300).contains(response.status) else { throw APIError.server(response.status) }
    return response.data
}
