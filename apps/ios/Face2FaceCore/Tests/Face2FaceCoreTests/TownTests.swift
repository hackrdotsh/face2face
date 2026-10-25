import Foundation
import Testing

@testable import Face2FaceCore

@Test func townReadsExistingEndpointsWithBearerAuth() async throws {
    let transport = StubTransport([
        response(
            json:
                #"{"forums":[{"id":"music","interestId":"music","interestName":"music","upcomingPostCount":2}]}"#
        ),
        response(
            json:
                #"{"connections":[{"id":"chance","status":"pending","sharedInterests":["music"],"them":null,"expiresAt":"2026-10-26T00:00:00Z"},{"id":"friend","status":"private","sharedInterests":[],"them":null,"expiresAt":"2026-10-26T00:00:00Z"}]}"#
        ),
    ])
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens("signed"), transport: transport)
    let forums = try await client.townForums()
    let connections = try await client.townConnections()
    #expect(forums.first?.upcomingPostCount == 2)
    #expect(connections.filter(\.isPending).map(\.id) == ["chance"])
    #expect(connections.filter(\.isFriend).map(\.id) == ["friend"])
    #expect(connections.allSatisfy { $0.them == nil })
    let requests = await transport.requests
    #expect(requests.map { $0.url?.path } == ["/api/forums", "/api/connections"])
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer signed" })
}

@Test func townRequiresSessionAndRejectsMalformedResponses() async throws {
    let transport = StubTransport([response(json: #"{"forums":[{"id":"missing-fields"}]}"#)])
    let client = APIClient(configuration: try configuration(), tokens: MemoryTokens(), transport: transport)
    await #expect(throws: APIError.unauthenticated) { try await client.townConnections() }
    #expect(await transport.requests.isEmpty)
    let signed = APIClient(
        configuration: try configuration(), tokens: MemoryTokens("signed"), transport: transport)
    await #expect(throws: APIError.invalidResponse) { try await signed.townForums() }
}
