import Foundation
import Testing

@testable import Face2FaceCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

private func jsonBody(_ request: URLRequest) throws -> [String: String] {
    try JSONDecoder().decode([String: String].self, from: request.httpBody ?? Data())
}

@Test func createsAPasswordAccountWithoutStoringASession() async throws {
    let transport = StubTransport([response(json: #"{"token":null,"user":{}}"#)])
    let tokens = MemoryTokens()
    let client = APIClient(configuration: try configuration(), tokens: tokens, transport: transport)
    try await client.createAccount(email: "new@example.test", password: "a-long-password")
    #expect(await tokens.load() == nil)
    let request = try #require(await transport.requests.first)
    #expect(request.url?.path == "/api/auth/sign-up/email")
    #expect(
        try jsonBody(request) == ["name": "", "email": "new@example.test", "password": "a-long-password"])
}

@Test func verifiesTheEmailAndStoresTheSession() async throws {
    let transport = StubTransport([response(json: #"{"status":true}"#, token: "verified-token")])
    let tokens = MemoryTokens()
    let client = APIClient(configuration: try configuration(), tokens: tokens, transport: transport)
    try await client.verifyEmail(email: "new@example.test", code: "123456")
    #expect(await tokens.load() == "verified-token")
    #expect(await transport.requests.first?.url?.path == "/api/auth/email-otp/verify-email")
}

@Test func sendsAndUsesASignInCode() async throws {
    let transport = StubTransport([
        response(json: #"{"success":true}"#),
        response(json: #"{"token":"x"}"#, token: "code-token"),
    ])
    let tokens = MemoryTokens()
    let client = APIClient(configuration: try configuration(), tokens: tokens, transport: transport)
    try await client.sendSignInCode(email: "code@example.test")
    try await client.signIn(email: "code@example.test", code: "654321")
    let requests = await transport.requests
    #expect(try jsonBody(requests[0]) == ["email": "code@example.test", "type": "sign-in"])
    #expect(try jsonBody(requests[1]) == ["email": "code@example.test", "otp": "654321"])
    #expect(await tokens.load() == "code-token")
}

@Test(arguments: [
    (400, #"{"code":"INVALID_OTP"}"#, APIError.invalidCode),
    (403, #"{"code":"TOO_MANY_ATTEMPTS"}"#, APIError.invalidCode),
    (401, #"{"code":"INVALID_EMAIL_OR_PASSWORD"}"#, APIError.invalidCredentials),
    (403, #"{"code":"EMAIL_NOT_VERIFIED"}"#, APIError.emailNotVerified),
    (429, "{}", APIError.rateLimited),
    (500, "not json", APIError.server(500)),
])
func mapsServerErrors(status: Int, body: String, expected: APIError) async throws {
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens(),
        transport: StubTransport([response(status, json: body)]))
    await #expect(throws: expected) { try await client.signIn(email: "a@example.test", password: "p") }
}

@Test func mapsSignedOutAndOnboardedAccountsToPhases() {
    let avatar = Avatar(seed: "AAAAAAAAAAAAAAAAAAAAAA", photo: nil)
    let user = User(id: "1", name: "Sam", email: "sam@example.test", avatar: avatar)
    let ready = Account(user: user, onboardingComplete: true)
    #expect(SessionPhase(account: nil) == .signedOut)
    #expect(SessionPhase(account: ready) == .ready(ready))
}
