import Foundation
import Testing

@testable import Face2FaceCore

private let radioStart = Date(timeIntervalSince1970: 50_000)
private let serverLease =
    #"{"sessionId":"00112233-4455-4677-8899-aabbccddeeff","token":"ffeeddcc-bbaa-4988-b766-554433221100","expiresAt":1300000,"sessionExpiresAt":2800000,"serverTime":1000000}"#

private func validity(start: Date = radioStart, uptime: Double = 1000, token: String? = nil) throws
    -> DiscoveryTokenValidity
{
    let json =
        token.map { serverLease.replacingOccurrences(of: "ffeeddcc-bbaa-4988-b766-554433221100", with: $0) }
        ?? serverLease
    let lease = try JSONDecoder().decode(DiscoveryLease.self, from: Data(json.utf8))
    return try DiscoveryTokenValidity(lease: lease, requestStartedAt: start, requestStartedUptime: uptime)
}

@Test func authenticatedTokenExpiresWithoutAnyTimerOrNetworkCallback() throws {
    let token = try validity()
    #expect(token.remaining(at: radioStart, uptime: 1000) == 290)
    #expect(token.remaining(at: radioStart.addingTimeInterval(289), uptime: 1289) == 1)
    #expect(token.remaining(at: radioStart.addingTimeInterval(290), uptime: 1290) == 0)
    #expect(token.remaining(at: radioStart.addingTimeInterval(900), uptime: 1900) == 0)
}

@Test func authenticatedRadioIncludesRequestLatencyAndIgnoresWallClockRollback() throws {
    let token = try validity()
    #expect(token.remaining(at: radioStart.addingTimeInterval(25), uptime: 1025) == 265)
    #expect(token.remaining(at: radioStart.addingTimeInterval(20), uptime: 1200) == 90)
    #expect(token.remaining(at: radioStart.addingTimeInterval(-1), uptime: 1001) == 0)
    #expect(token.remaining(at: radioStart, uptime: 1) == 0)
    #expect(token.remaining(at: radioStart, uptime: .nan) == 0)
}

@Test func authenticatedRotationCannotExtendOriginalConsentOrReviveOldTokens() throws {
    let consent = PocketTestWindow(at: radioStart, uptime: 1000)
    let initialValidity = try validity()
    let initial = AuthenticatedRadioPermit(validity: initialValidity, consent: consent)
    let rotatedValidity = try validity(
        start: radioStart.addingTimeInterval(120), uptime: 1120,
        token: "00112233-4455-4677-8899-aabbccddeeff")
    let rotated = initial.rotating(to: rotatedValidity)
    #expect(rotated.token != initial.token)
    #expect(rotated.consent.id == consent.id)
    #expect(rotated.remaining(at: radioStart.addingTimeInterval(299), uptime: 1299) == 1)
    #expect(rotated.remaining(at: radioStart.addingTimeInterval(301), uptime: 1301) == 0)
    // An in-flight exchange carrying the old token must obey the old token's own expiry.
    #expect(initialValidity.remaining(at: radioStart.addingTimeInterval(291), uptime: 1291) == 0)
    #expect(rotatedValidity.remaining(at: radioStart.addingTimeInterval(291), uptime: 1291) > 0)
}

@Test func authenticatedPermitRejectsMalformedLeaseOrClock() throws {
    let lease = try JSONDecoder().decode(DiscoveryLease.self, from: Data(serverLease.utf8))
    #expect(throws: APIError.invalidResponse) {
        try DiscoveryTokenValidity(
            lease: lease, requestStartedAt: radioStart, requestStartedUptime: .infinity)
    }
    let invalid = serverLease.replacingOccurrences(of: "1300000", with: "999999")
    let expired = try JSONDecoder().decode(DiscoveryLease.self, from: Data(invalid.utf8))
    #expect(throws: APIError.invalidResponse) {
        try DiscoveryTokenValidity(lease: expired, requestStartedAt: radioStart, requestStartedUptime: 1000)
    }
}

@Test func backgroundUploadPassesHaveCooldownAndFailClosedOnInvalidTime() {
    var policy = BackgroundUploadPolicy()
    #expect(policy.begin(at: 100) == true)
    #expect(policy.begin(at: 101) == false)
    #expect(policy.begin(at: 109.9) == false)
    #expect(policy.begin(at: 110) == true)
    #expect(policy.begin(at: 1) == false)
    #expect(policy.begin(at: .nan) == false)
    #expect(policy.begin(at: .infinity) == false)
}
