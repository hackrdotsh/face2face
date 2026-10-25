import Foundation
import Testing

@testable import Face2FaceCore

@Test func connectionDecisionsUseOnlyAuthenticatedViewerAndTypedAnswer() async throws {
    let transport = StubTransport([
        response(
            json:
                #"{"connection":{"id":"chance","status":"pending","sharedInterests":["coffee"],"expiresAt":"2026-10-26T12:00:00.000Z","you":{"decision":"accepted","decidedAt":"2026-10-25T12:00:00Z","publicAt":null},"them":null}}"#
        ),
        response(
            json:
                #"{"connection":{"id":"other","status":"expired","sharedInterests":[],"expiresAt":"2026-10-26T12:00:00Z","you":{"decision":"declined","decidedAt":"2026-10-25T12:00:00Z","publicAt":null},"them":null}}"#
        ),
    ])
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens("signed"), transport: transport)
    let waiting = try await client.decideConnection("chance", decision: .accepted)
    #expect(waiting.isPending && waiting.you?.decision == .accepted)
    #expect(waiting.expiryDate != nil)
    #expect(waiting.publicTownFriend == nil)
    let declined = try await client.decideConnection("other", decision: .declined)
    #expect(declined.status == "expired" && declined.you?.decision == .declined)
    let requests = await transport.requests
    #expect(
        requests.map { $0.url?.path } == [
            "/api/connections/chance/decision", "/api/connections/other/decision",
        ])
    #expect(
        requests.allSatisfy {
            $0.httpMethod == "POST" && $0.value(forHTTPHeaderField: "Authorization") == "Bearer signed"
        })
    #expect(String(decoding: requests[0].httpBody!, as: UTF8.self) == #"{"decision":"accepted"}"#)
    #expect(String(decoding: requests[1].httpBody!, as: UTF8.self) == #"{"decision":"declined"}"#)
}

@Test func connectionDecisionRefusalsRequireReconciliationNotAutomaticRetry() async throws {
    let transport = StubTransport([
        response(409, json: #"{"error":"already_decided"}"#),
        response(409, json: #"{"error":"not_pending"}"#),
        response(409, json: #"{"error":"conflict"}"#),
    ])
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens("signed"), transport: transport)
    await #expect(throws: APIError.chanceAlreadyAnswered) {
        try await client.decideConnection("id", decision: .accepted)
    }
    await #expect(throws: APIError.chanceEnded) {
        try await client.decideConnection("id", decision: .declined)
    }
    await #expect(throws: APIError.connectionChanged) {
        try await client.decideConnection("id", decision: .accepted)
    }
    #expect(await transport.requests.count == 3)
    await #expect(throws: APIError.invalidResponse) {
        try await client.decideConnection("../other", decision: .accepted)
    }
    #expect(await transport.requests.count == 3)
}

@Test func pendingIdentityShapedFieldsNeverBecomePublicFriendData() throws {
    let json =
        #"{"id":"id","status":"pending","sharedInterests":["coffee"],"expiresAt":"2026-10-26T12:00:00Z","you":{"decision":null},"them":{"userId":"secret","name":"Must stay hidden","avatar":{"seed":"AAAAAAAAAAAAAAAAAAAAAA"}}}"#
    let connection = try JSONDecoder().decode(TownConnection.self, from: Data(json.utf8))
    #expect(connection.publicTownFriend == nil)
    #expect(connection.you?.decision == nil)
}
