import Foundation
import Testing

@testable import Face2FaceCore

@Test func discoveryPacketFitsDefaultATTWriteAndRoundTrips() throws {
    let token = DiscoveryToken()
    #expect(token.packet.count == 17)
    #expect(try DiscoveryToken(packet: token.packet) == token)
    // A known packet guards against swapping bytes during UUID conversion.
    let packet = Data([1] + Array(UInt8(0)...UInt8(15)))
    #expect(try DiscoveryToken(packet: packet).packet == packet)
}

@Test(arguments: [0, 1, 16, 18, 512])
func discoveryRejectsMalformedPacketLengths(_ length: Int) {
    #expect(throws: DiscoveryPacketError.invalidLength) {
        try DiscoveryToken(packet: Data(repeating: 1, count: length))
    }
}

@Test func discoveryRejectsUnknownProtocolVersion() {
    #expect(throws: DiscoveryPacketError.unsupportedVersion) {
        try DiscoveryToken(packet: Data([2] + Array(repeating: UInt8(0), count: 16)))
    }
}

@Test func discoveryIgnoresOwnTokenAndDeduplicatesBothExchangeDirections() {
    let start = Date(timeIntervalSince1970: 1_000)
    var session = DiscoverySession(startedAt: start)
    let peer = DiscoveryToken()
    #expect(session.record(session.token, at: start) == nil)
    let incoming = session.record(peer, at: start.addingTimeInterval(2.5))
    #expect(incoming?.elapsed == 2.5)
    #expect(session.record(peer, at: start.addingTimeInterval(3)) == nil)
    #expect(session.encounters.count == 1)
    #expect(session.encounters.first?.observedAt == start.addingTimeInterval(2.5))
}

@Test func discoveryFreshSessionsAndPeerTokensAreIndependent() {
    let peer = DiscoveryToken()
    var first = DiscoverySession()
    var second = DiscoverySession()
    #expect(first.token != second.token)
    #expect(first.record(peer) != nil)
    #expect(second.record(peer) != nil)
    #expect(first.record(DiscoveryToken()) != nil)
    #expect(first.encounters.count == 2)
}

@Test func discoveryClampsElapsedTimeWhenWallClockMovesBackwards() {
    let start = Date(timeIntervalSince1970: 100)
    var session = DiscoverySession(startedAt: start)
    #expect(session.record(DiscoveryToken(), at: start.addingTimeInterval(-1))?.elapsed == 0)
}

@Test func discoveryBoundsUntrustedTokenStorage() {
    var session = DiscoverySession()
    for _ in 0..<DiscoverySession.encounterLimit {
        #expect(session.record(DiscoveryToken()) != nil)
    }
    #expect(session.record(DiscoveryToken()) == nil)
    #expect(session.encounters.count == DiscoverySession.encounterLimit)
}
