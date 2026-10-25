import Foundation
import Testing

@testable import Face2FaceCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

private let challengeCookie = ["better-auth.better-auth-passkey": "signed.value"]

@Test func returnsTheChallengeCookieWithRegistration() async throws {
    let transport = StubTransport([
        response(
            json: #"""
                {"challenge":"AQID","rp":{"id":"face2face.example","name":"face2face"},
                 "user":{"id":"dXNlcg","name":"sam@example.test"},"excludeCredentials":[{"id":"_w"}]}
                """#,
            cookies: challengeCookie),
        response(json: #"{"id":"passkey"}"#),
    ])
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens("t"), transport: transport)
    let challenge = try await client.passkeyRegistrationChallenge(userName: "sam@example.test")
    #expect(challenge.relyingPartyID == "face2face.example")
    #expect(challenge.challenge == Data([1, 2, 3]))
    #expect(challenge.userID == Data("user".utf8))
    #expect(challenge.excludedCredentialIDs == [Data([0xFF])])
    try await client.registerPasskey(
        PasskeyRegistration(
            credentialID: Data([0xFB, 0xFF]), clientDataJSON: Data("{}".utf8), attestationObject: Data([0])),
        for: challenge)
    let requests = await transport.requests
    #expect(requests[0].url?.query?.contains("name=sam@example.test") == true)
    #expect(requests[1].value(forHTTPHeaderField: "Cookie") == "better-auth.better-auth-passkey=signed.value")
    #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer t")
    let body = try JSONSerialization.jsonObject(with: requests[1].httpBody ?? Data()) as? [String: Any]
    let credential = try #require(body?["response"] as? [String: Any])
    #expect(credential["id"] as? String == "-_8")
    #expect(credential["type"] as? String == "public-key")
    #expect((credential["response"] as? [String: Any])?["clientDataJSON"] as? String == "e30")
}

@Test func signsInWithAnAssertionAndStoresTheSession() async throws {
    let transport = StubTransport([
        response(json: #"{"challenge":"AQID","rpId":"face2face.example"}"#, cookies: challengeCookie),
        response(json: #"{"session":{}}"#, token: "passkey-token"),
    ])
    let tokens = MemoryTokens()
    let client = APIClient(configuration: try configuration(), tokens: tokens, transport: transport)
    let challenge = try await client.passkeySignInChallenge()
    #expect(challenge.allowedCredentialIDs.isEmpty)
    try await client.signIn(
        with: PasskeyAssertion(
            credentialID: Data([1]), clientDataJSON: Data("{}".utf8), authenticatorData: Data([2]),
            signature: Data([3]), userID: nil),
        for: challenge)
    let requests = await transport.requests
    #expect(requests[0].value(forHTTPHeaderField: "Authorization") == nil)
    #expect(requests[1].value(forHTTPHeaderField: "Cookie") == "better-auth.better-auth-passkey=signed.value")
    #expect(await tokens.load() == "passkey-token")
}

@Test func rejectsOptionsWithoutAChallengeCookie() async throws {
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens(),
        transport: StubTransport([response(json: #"{"challenge":"AQID","rpId":"face2face.example"}"#)]))
    await #expect(throws: APIError.invalidResponse) { try await client.passkeySignInChallenge() }
}

@Test func readsTheChallengeCookieFromSetCookieHeaders() throws {
    let url = try #require(
        URL(string: "https://api.example.test/api/auth/passkey/generate-authenticate-options"))
    let cookies = URLSessionTransport.cookies(
        fromHeaders: [
            "Set-Cookie":
                "__Secure-better-auth.better-auth-passkey=abc.def%3D; Max-Age=300; Path=/; HttpOnly; Secure; SameSite=Lax"
        ],
        for: url)
    #expect(cookies == ["__Secure-better-auth.better-auth-passkey": "abc.def%3D"])
    let challengeCookie = try PasskeyChallengeCookie(
        from: HTTPResponse(status: 200, data: Data(), cookies: cookies))
    #expect(challengeCookie.header == "__Secure-better-auth.better-auth-passkey=abc.def%3D")
}
