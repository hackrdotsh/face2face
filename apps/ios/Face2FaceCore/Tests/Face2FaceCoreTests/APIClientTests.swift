import Foundation
import Testing

@testable import Face2FaceCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

private actor MemoryTokens: TokenStore {
    var token: String?
    init(_ token: String? = nil) { self.token = token }
    func load() -> String? { token }
    func save(_ token: String?) { self.token = token }
}

private actor StubTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var responses: [HTTPResponse]
    init(_ responses: [HTTPResponse]) { self.responses = responses }
    func send(_ request: URLRequest) throws -> HTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw APIError.invalidResponse }
        return responses.removeFirst()
    }
}

private func response(_ status: Int = 200, json: String, token: String? = nil) -> HTTPResponse {
    HTTPResponse(status: status, data: Data(json.utf8), authToken: token)
}

private func configuration() throws -> APIConfiguration {
    try APIConfiguration(address: "https://api.example.test")
}

@Test func validatesServerAddresses() throws {
    #expect(
        try APIConfiguration(address: " https://api.example.test/ ").baseURL.absoluteString
            == "https://api.example.test")
    #expect(throws: APIError.insecureServerURL) { try APIConfiguration(address: "http://100.100.20.30:8787") }
    #expect(
        try APIConfiguration(address: "http://100.100.20.30:8787", allowInsecureHTTP: true).baseURL.host
            == "100.100.20.30")
}

@Test(arguments: [
    "file:///tmp/api", "https://name:password@example.test", "https://example.test/api",
    "https://example.test?token=secret", "https://example.test/#fragment", "invalid",
])
func rejectsInvalidAddresses(_ address: String) {
    #expect(throws: APIError.invalidServerURL) { try APIConfiguration(address: address) }
}

@Test func checksTheExpectedService() async throws {
    let transport = StubTransport([
        response(json: #"{"status":"ok","service":"face2face-api"}"#),
        response(json: #"{"status":"ok","service":"another-api"}"#),
    ])
    let client = APIClient(configuration: try configuration(), tokens: MemoryTokens(), transport: transport)
    try await client.checkHealth()
    await #expect(throws: APIError.invalidResponse) { try await client.checkHealth() }
}

@Test func storesSignedHeaderAndSendsBearerToken() async throws {
    let transport = StubTransport([
        response(
            json: #"{"token":"unsigned-body-token","user":{"id":"1","name":"Test"}}"#,
            token: "signed-header-token"),
        response(json: #"{"user":{"id":"1","name":"Test"}}"#),
    ])
    let tokens = MemoryTokens()
    let client = APIClient(configuration: try configuration(), tokens: tokens, transport: transport)
    let signedIn = try await client.signIn(email: "test@example.test", password: "a-long-password")
    #expect(signedIn.name == "Test")
    #expect(await tokens.load() == "signed-header-token")
    #expect(try await client.currentUser() == signedIn)
    let requests = await transport.requests
    #expect(requests[0].url?.path == "/api/auth/sign-in/email")
    #expect(requests[0].value(forHTTPHeaderField: "Authorization") == nil)
    #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer signed-header-token")
    #expect(requests[1].value(forHTTPHeaderField: "Origin") == "face2face://")
}

@Test func requiresTheSignedTokenHeader() async throws {
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens(),
        transport: StubTransport([
            response(json: #"{"user":{"id":"1","name":"Test"}}"#)
        ]))
    await #expect(throws: APIError.invalidResponse) {
        try await client.signUp(name: "Test", email: "test@example.test", password: "a-long-password")
    }
}

@Test func expiredSessionClearsTheSavedToken() async throws {
    let tokens = MemoryTokens("expired")
    let client = APIClient(
        configuration: try configuration(), tokens: tokens,
        transport: StubTransport([response(401, json: "{}")]))
    await #expect(throws: APIError.unauthenticated) { try await client.currentUser() }
    #expect(await tokens.load() == nil)
}

@Test func missingSessionDoesNotMakeARequest() async throws {
    let transport = StubTransport([])
    let client = APIClient(configuration: try configuration(), tokens: MemoryTokens(), transport: transport)
    await #expect(throws: APIError.unauthenticated) { try await client.currentUser() }
    #expect(await transport.requests.isEmpty)
}

@Test func successfulSignOutClearsTheToken() async throws {
    let tokens = MemoryTokens("signed")
    let transport = StubTransport([response(json: "{}")])
    let client = APIClient(
        configuration: try configuration(), tokens: tokens, transport: transport)
    try await client.signOut()
    #expect(await tokens.load() == nil)
    let requests = await transport.requests
    #expect(requests[0].httpBody == Data("{}".utf8))
}

@Test func failedSignOutKeepsTheTokenForRetry() async throws {
    let tokens = MemoryTokens("signed")
    let client = APIClient(
        configuration: try configuration(), tokens: tokens,
        transport: StubTransport([response(503, json: "{}")]))
    await #expect(throws: APIError.server(503)) { try await client.signOut() }
    #expect(await tokens.load() == "signed")
}
