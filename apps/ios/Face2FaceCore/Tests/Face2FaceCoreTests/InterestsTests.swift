import Foundation
import Testing

@testable import Face2FaceCore

private func catalog(_ rows: [(String, Int)], selected: Set<String> = []) -> InterestCatalog {
    InterestCatalog(
        maxSelected: 10,
        interests: rows.map { name, count in
            InterestChoice(
                id: name.replacingOccurrences(of: " ", with: "-"), name: name, memberCount: count,
                selected: selected.contains(name))
        })
}

@Test func ranksByMembersWithoutAQuery() {
    let ranked = catalog([("coffee", 4), ("jazz", 9), ("film", 4)]).ranked(for: "  ")
    #expect(ranked.map(\.name) == ["jazz", "coffee", "film"])
}

@Test func ranksPrefixThenWordThenContainsMatches() {
    let interests = catalog([
        ("live music", 30), ("music theory", 2), ("musicals", 5), ("film music", 1), ("cooking", 50),
    ])
    #expect(
        interests.ranked(for: "Music").map(\.name)
            == ["musicals", "music theory", "live music", "film music"])
    #expect(
        interests.ranked(for: "usic").map(\.name) == ["live music", "musicals", "music theory", "film music"])
}

@Test func findsAnExactMatchAfterNormalizing() {
    let interests = catalog([("board games", 3)])
    #expect(interests.exactMatch(for: "  Board   Games ")?.id == "board-games")
    #expect(interests.exactMatch(for: "board") == nil)
}

@Test func normalizesNamesLikeTheServer() {
    #expect(InterestName.normalize("  Rock  Climbing\u{2019}s ") == "rock climbing's")
    #expect(InterestName.normalize("Cafe\u{301}") == "caf\u{e9}")
}

@Test func acceptsOnlyNamesTheServerAccepts() {
    #expect(InterestName.isValid("d&d"))
    #expect(InterestName.isValid("k-pop"))
    #expect(InterestName.isValid("caf\u{e9}"))
    #expect(!InterestName.isValid("a"))
    #expect(!InterestName.isValid(String(repeating: "x", count: 33)))
    #expect(!InterestName.isValid("-dash"))
    #expect(!InterestName.isValid("emoji 🎸"))
}

@Test func countsPicksAgainstTheCap() {
    let full = InterestCatalog(
        maxSelected: 1, interests: [InterestChoice(id: "a", name: "aa", memberCount: 1, selected: true)])
    #expect(full.isFull)
    #expect(full.selected.map(\.id) == ["a"])
}

@Test func addsAnInterestByName() async throws {
    let transport = StubTransport([
        response(
            json:
                #"{"interestId":"kite-flying","maxSelected":10,"interests":[{"id":"kite-flying","name":"kite flying","memberCount":1,"selected":true}]}"#
        )
    ])
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens("t"), transport: transport)
    let result = try await client.addInterest(named: "Kite Flying")
    #expect(result.selected.map(\.id) == ["kite-flying"])
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/api/interests")
    #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self) == #"{"name":"Kite Flying"}"#)
}

@Test func replacesPicksWithIds() async throws {
    let transport = StubTransport([response(json: #"{"maxSelected":10,"interests":[]}"#)])
    let client = APIClient(
        configuration: try configuration(), tokens: MemoryTokens("t"), transport: transport)
    _ = try await client.replaceInterests(["coffee"])
    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "PUT")
    #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self) == #"{"interestIds":["coffee"]}"#)
}

@Test func mapsTheInterestCap() {
    #expect(
        APIError.from(status: 409, body: Data(#"{"error":"too_many_interests"}"#.utf8))
            == .interestLimitReached)
}
