import Foundation
import Testing

@testable import Face2FaceCore

@Test func continuousConsentSurvivesHoursButEveryRadioTokenStillExpires() throws {
    let consent = DiscoveryConsent(untilStopped: UUID())
    let start = Date(timeIntervalSince1970: 50_000)
    for offset in stride(from: 0, through: 7_200, by: 120) {
        let json =
            #"{"sessionId":"00112233-4455-4677-8899-aabbccddeeff","token":"ffeeddcc-bbaa-4988-b766-554433221100","expiresAt":1300000,"sessionExpiresAt":2800000,"serverTime":1000000}"#
        let lease = try JSONDecoder().decode(DiscoveryLease.self, from: Data(json.utf8))
        let now = start.addingTimeInterval(Double(offset))
        let uptime = Double(1_000 + offset)
        let validity = try DiscoveryTokenValidity(
            lease: lease, requestStartedAt: now, requestStartedUptime: uptime)
        let permit = AuthenticatedRadioPermit(validity: validity, consent: consent)
        #expect(permit.remaining(at: now, uptime: uptime) == 290)
        #expect(permit.remaining(at: now.addingTimeInterval(291), uptime: uptime + 291) == 0)
        #expect(permit.remaining(at: now.addingTimeInterval(-1), uptime: uptime + 1) == 0)
        #expect(validity.sessionRemaining(at: now, uptime: uptime) == 1_790)
        #expect(validity.sessionRemaining(at: now.addingTimeInterval(1_791), uptime: uptime + 1_791) == 0)
        #expect(permit.rotating(to: validity).consent.id == consent.id)
    }
}

@Test func discoveryPreferenceRestoresOnlyForTheSameAccountAndServer() throws {
    let server = try APIConfiguration(address: "https://api.example.test").baseURL
    let preference = DiscoveryOptIn(accountID: "alice", server: server)
    let data = try JSONEncoder().encode(preference)
    let restored = try JSONDecoder().decode(DiscoveryOptIn.self, from: data)
    #expect(restored == preference)
    #expect(restored.matches(accountID: "alice", server: server))
    #expect(!restored.matches(accountID: "bob", server: server))
    #expect(!restored.matches(accountID: "alice", server: URL(string: "https://other.example.test")!))
    let fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(fields.keys) == ["id", "accountID", "server"])
}
