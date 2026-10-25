import Foundation
import Testing

@testable import Face2FaceCore

@Test func normalizesAStatusToOneTrimmedLine() {
    #expect(StatusMessage.normalized("  Out for\n coffee  ") == "Out for coffee")
    #expect(StatusMessage.normalized(" \n\t ") == nil)
}

@Test func countsCodePointsLikeTheServer() {
    #expect(!StatusMessage.isTooLong(String(repeating: "🌲", count: 80)))
    #expect(StatusMessage.isTooLong(String(repeating: "a", count: 81)))
    #expect(StatusMessage.isTooLong(String(repeating: "👨‍👩‍👧", count: 20)))
    #expect(!StatusMessage.isTooLong("a" + String(repeating: " ", count: 100) + "b"))
}

@Test func sendsTheStatusAndReturnsWhatWasSaved() async throws {
    let transport = StubTransport([response(json: #"{"statusMessage":"Out for coffee"}"#)])
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens("t"), transport: transport)
    #expect(try await client.updateStatusMessage(" Out for coffee ") == "Out for coffee")
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "PUT")
    #expect(request.url?.path == "/api/profile/status")
    let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String]
    #expect(body == ["statusMessage": " Out for coffee "])
}

@Test func sendsAnExplicitNullToClearTheStatus() async throws {
    let transport = StubTransport([response(json: #"{"statusMessage":null}"#)])
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens("t"), transport: transport)
    #expect(try await client.updateStatusMessage(nil) == nil)
    let body = String(decoding: await transport.requests.first?.httpBody ?? Data(), as: UTF8.self)
    #expect(body == #"{"statusMessage":null}"#)
}

@Test func decodesTheAccountStatus() throws {
    let json = #"""
        {"user":{"id":"1","name":"Sam","email":"sam@example.test",
        "avatar":{"seed":"AAAAAAAAAAAAAAAAAAAAAA","photo":null},"statusMessage":"Hi"},
        "onboardingComplete":true}
        """#
    let account = try JSONDecoder().decode(Account.self, from: Data(json.utf8))
    #expect(account.user.statusMessage == "Hi")
}

@Test func givesAPublicFriendTheirStatusAndDropsABlankOne() throws {
    func friend(status: String) throws -> PublicTownFriend? {
        let json = """
            {"id":"c","status":"public","sharedInterests":[],"expiresAt":"2026-10-26T00:00:00Z",
             "them":{"userId":"peer","name":"Ava","avatar":{"seed":"AAAAAAAAAAAAAAAAAAAAAA"},
             "statusMessage":\(status)}}
            """
        return PublicTownFriend(
            connection: try JSONDecoder().decode(TownConnection.self, from: Data(json.utf8)))
    }
    #expect(try friend(status: #""Out for coffee""#)?.statusMessage == "Out for coffee")
    #expect(try friend(status: #""  ""#)?.statusMessage == nil)
    #expect(try friend(status: "null")?.statusMessage == nil)
}
