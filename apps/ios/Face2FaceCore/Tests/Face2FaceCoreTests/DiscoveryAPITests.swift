import Foundation
import Testing

@testable import Face2FaceCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

private actor DiscoveryTestTokens: TokenStore {
    var token: String? = "signed-auth-token"
    func load() -> String? { token }
    func save(_ value: String?) { token = value }
}

private actor DiscoveryTestTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var responses: [HTTPResponse]
    init(_ responses: [HTTPResponse]) { self.responses = responses }
    func send(_ request: URLRequest) throws -> HTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw APIError.invalidResponse }
        return responses.removeFirst()
    }
}

private func discoveryResponse(_ json: String, status: Int = 200) -> HTTPResponse {
    HTTPResponse(status: status, data: Data(json.utf8))
}

private let leaseJSON =
    #"{"sessionId":"00112233-4455-4677-8899-aabbccddeeff","token":"ffeeddcc-bbaa-4988-b766-554433221100","expiresAt":1300000,"sessionExpiresAt":2800000,"serverTime":1000000}"#

@Test func discoveryLeaseProducesTheSameWireTokenAndUsesServerRelativeExpiry() throws {
    let lease = try JSONDecoder().decode(DiscoveryLease.self, from: Data(leaseJSON.utf8))
    let token = try lease.validatedToken()
    #expect(token.identifier == lease.token)
    #expect(try DiscoveryToken(packet: token.packet).identifier == lease.token)
    let local = Date(timeIntervalSince1970: 9_000_000)
    #expect(lease.tokenDeadline(requestStartedAt: local).timeIntervalSince(local) == 290)
    #expect(lease.sessionDeadline(requestStartedAt: local).timeIntervalSince(local) == 1790)
}

@Test func discoveryRejectsMalformedOrOverlongLeases() throws {
    for json in [
        leaseJSON.replacingOccurrences(of: "ffeeddcc-bbaa-4988-b766-554433221100", with: "not-a-token"),
        leaseJSON.replacingOccurrences(of: "1300000", with: "999999"),
        leaseJSON.replacingOccurrences(of: "1300000", with: "1400000"),
        leaseJSON.replacingOccurrences(of: "2800000", with: "999999"),
    ] {
        let lease = try JSONDecoder().decode(DiscoveryLease.self, from: Data(json.utf8))
        #expect(throws: APIError.invalidResponse) { try lease.validatedToken() }
    }
}

@Test func discoveryClientUsesAuthenticatedEndpointsAndOnlySendsRadioLocators() async throws {
    let transport = DiscoveryTestTransport([
        discoveryResponse(leaseJSON), discoveryResponse(leaseJSON),
        discoveryResponse(#"{"status":"pending"}"#),
        discoveryResponse(#"{"stopped":true}"#),
    ])
    let client = APIClient(
        configuration: try APIConfiguration(address: "https://api.example.test"),
        tokens: DiscoveryTestTokens(), transport: transport)
    let lease = try await client.startDiscovery()
    _ = try await client.rotateDiscovery(sessionId: lease.sessionId)
    let observationId = UUID()
    let peer = DiscoveryToken()
    let receipt = try await client.observeEncounter(
        sessionId: lease.sessionId, peerToken: peer, observationId: observationId)
    #expect(receipt.status == .pending)
    try await client.stopDiscovery(sessionId: lease.sessionId)
    let requests = await transport.requests
    #expect(
        requests.map { $0.url?.path } == [
            "/api/discovery/start", "/api/discovery/rotate", "/api/discovery/observe",
            "/api/discovery/stop",
        ])
    #expect(
        requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer signed-auth-token" })
    let payload = try #require(requests[2].httpBody)
    let object = try #require(JSONSerialization.jsonObject(with: payload) as? [String: String])
    #expect(
        object == [
            "sessionId": lease.sessionId, "peerToken": peer.identifier,
            "observationId": observationId.uuidString.lowercased(),
        ])
    #expect(!String(decoding: payload, as: UTF8.self).contains("signed-auth-token"))
}

@Test func discoveryReceiptCarriesOnlyAnOpaqueMatchAndRejectsInconsistentReceipts() async throws {
    let transport = DiscoveryTestTransport([
        discoveryResponse(#"{"status":"recorded","matchId":"opaque-match"}"#),
        discoveryResponse(#"{"status":"noSharedInterests","matchId":"opaque-match"}"#),
        discoveryResponse(#"{"status":"recorded"}"#),
        discoveryResponse(#"{"status":"noSharedInterests"}"#),
        discoveryResponse(#"{"status":"pending","matchId":"opaque-match"}"#),
    ])
    let client = APIClient(
        configuration: try APIConfiguration(address: "https://api.example.test"),
        tokens: DiscoveryTestTokens(), transport: transport)
    for status in [ObservationReceipt.Status.recorded, .noSharedInterests] {
        let receipt = try await client.observeEncounter(
            sessionId: "s1", peerToken: DiscoveryToken(), observationId: UUID())
        #expect(receipt == ObservationReceipt(status: status, matchId: "opaque-match"))
    }
    for _ in 0..<3 {
        await #expect(throws: APIError.invalidResponse) {
            try await client.observeEncounter(
                sessionId: "s1", peerToken: DiscoveryToken(), observationId: UUID())
        }
    }
}

@Test func discoveryOutboxKeepsIdempotencyAcrossRetriesAndBoundsBackoff() throws {
    let start = Date(timeIntervalSince1970: 100)
    let peer = DiscoveryToken()
    var outbox = DiscoveryOutbox()
    #expect(outbox.enqueue(peer, at: start) == true)
    #expect(outbox.enqueue(peer, at: start) == false)
    let first = try #require(outbox.nextReady(at: start))
    #expect(outbox.failed(first.id, at: start) == true)
    #expect(outbox.nextReady(at: start.addingTimeInterval(1)) == nil)
    let retry = try #require(outbox.nextReady(at: start.addingTimeInterval(2)))
    #expect(retry.id == first.id)
    #expect(retry.peerToken == peer)
    #expect(outbox.failed(first.id, at: start, rateLimited: true) == true)
    #expect(outbox.nextReady(at: start.addingTimeInterval(59)) == nil)
    #expect(outbox.nextReady(at: start.addingTimeInterval(60))?.id == first.id)
    outbox.acknowledge(first.id)
    #expect(outbox.pending.isEmpty)
    #expect(outbox.enqueue(peer, at: start) == false)
}

@Test func discoveryOutboxDropsAfterFiveFailuresAndCapsSessionStorage() throws {
    var outbox = DiscoveryOutbox()
    outbox.enqueue(DiscoveryToken())
    let id = try #require(outbox.pending.first?.id)
    for _ in 0..<4 { #expect(outbox.failed(id) == true) }
    #expect(outbox.failed(id) == false)
    #expect(outbox.pending.isEmpty)
    for _ in 1..<DiscoveryOutbox.limit { #expect(outbox.enqueue(DiscoveryToken()) == true) }
    #expect(outbox.enqueue(DiscoveryToken()) == false)
}

@Test func discoveryRotationPreservesPeersAndRejectsReflectedOldLocalTokens() {
    var session = DiscoverySession()
    let oldLocal = session.token
    let peer = DiscoveryToken()
    session.record(peer)
    let rotated = DiscoveryToken()
    session.rotate(to: rotated)
    #expect(session.token == rotated)
    #expect(session.record(oldLocal) == nil)
    #expect(session.record(rotated) == nil)
    #expect(session.record(peer) == nil)
    #expect(session.encounters.count == 1)
}

@Test func discoveryCredentialSnapshotDoesNotFollowAnAccountSwitch() async throws {
    let tokens = DiscoveryTestTokens()
    let transport = DiscoveryTestTransport([
        discoveryResponse(leaseJSON),
        discoveryResponse("{}", status: 401),
    ])
    let base = APIClient(
        configuration: try APIConfiguration(address: "https://api.example.test"),
        tokens: tokens, transport: transport)
    let run = try await base.capturingCurrentCredential()
    #expect(try await run.usesSameCredential(as: base))
    await tokens.save("new-account-token")
    #expect(try await run.usesSameCredential(as: base) == false)
    _ = try await run.startDiscovery()
    await #expect(throws: APIError.unauthenticated) { try await run.rotateDiscovery(sessionId: "s1") }
    let requests = await transport.requests
    #expect(
        requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer signed-auth-token" })
    #expect(await tokens.load() == "new-account-token")
}

@Test func discoveryOutboxRechecksAPendingReportWithTheSameIDUntilTheWindowCloses() throws {
    let start = Date(timeIntervalSince1970: 100)
    var outbox = DiscoveryOutbox()
    outbox.enqueue(DiscoveryToken(), at: start)
    let report = try #require(outbox.nextReady(at: start))
    #expect(outbox.awaitMatch(report.id, at: start) == true)
    #expect(outbox.nextReady(at: start.addingTimeInterval(4)) == nil)
    let recheck = try #require(outbox.nextReady(at: start.addingTimeInterval(5)))
    #expect(recheck.id == report.id)
    #expect(recheck.attempts == 0)
    #expect(outbox.awaitMatch(report.id, at: start.addingTimeInterval(119)) == true)
    #expect(outbox.awaitMatch(report.id, at: start.addingTimeInterval(120)) == false)
    #expect(outbox.pending.isEmpty)
}
