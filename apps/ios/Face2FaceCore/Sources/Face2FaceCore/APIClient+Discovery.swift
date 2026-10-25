import Foundation

extension APIClient {
    public func startDiscovery() async throws -> DiscoveryLease {
        let lease = try decode(
            DiscoveryLease.self,
            from: try await send(
                APIRequest(
                    path: "api/discovery/start", method: "POST", body: Data("{}".utf8), authenticated: true)))
        _ = try lease.validatedToken()
        return lease
    }

    public func rotateDiscovery(sessionId: String) async throws -> DiscoveryLease {
        let lease = try decode(
            DiscoveryLease.self,
            from: try await post(
                "api/discovery/rotate", LeaseRequest(sessionId: sessionId), authenticated: true))
        guard lease.sessionId == sessionId else { throw APIError.invalidResponse }
        _ = try lease.validatedToken()
        return lease
    }

    public func stopDiscovery(sessionId: String) async throws {
        _ = try await post("api/discovery/stop", LeaseRequest(sessionId: sessionId), authenticated: true)
    }

    public func observeEncounter(sessionId: String, peerToken: DiscoveryToken, observationId: UUID)
        async throws -> ObservationReceipt
    {
        struct Request: Encodable {
            let sessionId: String
            let peerToken: String
            let observationId: String
        }
        let receipt = try decode(
            ObservationReceipt.self,
            from: try await post(
                "api/discovery/observe",
                Request(
                    sessionId: sessionId, peerToken: peerToken.identifier,
                    observationId: observationId.uuidString.lowercased()),
                authenticated: true))
        guard (receipt.status == .recorded) == (receipt.matchId != nil) else {
            throw APIError.invalidResponse
        }
        return receipt
    }
}

private struct LeaseRequest: Encodable {
    let sessionId: String
}
