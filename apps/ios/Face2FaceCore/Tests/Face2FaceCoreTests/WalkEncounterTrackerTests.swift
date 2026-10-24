import Foundation
import Testing

@testable import Face2FaceCore

private func encounter(_ id: String = "pair-a", seen: Int64, name: String = "Maya") throws -> ServerEncounter
{
    let object: [String: Any] = [
        "id": id, "peer": ["id": "peer-\(id)", "name": name],
        "firstSeenAt": 10, "lastSeenAt": seen, "source": "client_reported_bluetooth",
    ]
    return try JSONDecoder().decode(
        ServerEncounter.self, from: JSONSerialization.data(withJSONObject: object))
}

@Test func walkDoesNotCelebrateHistoricalRecordsOrStaleReceipts() throws {
    let old = try encounter(seen: 100)
    var tracker = WalkEncounterTracker(baseline: [old], serverStartedAt: 200)
    #expect(tracker.ingest([old]).isEmpty)
    // A history row not present in the baseline still must be from this server-time window.
    #expect(tracker.ingest([try encounter("pair-b", seen: 199)]).isEmpty)
    #expect(tracker.encounters.isEmpty)
}

@Test func walkRevealsNewAndUpdatedPairsOnlyOnceDespitePollingAndRotation() throws {
    let old = try encounter(seen: 100)
    let updated = try encounter(seen: 201)
    let fresh = try encounter("pair-b", seen: 202)
    var tracker = WalkEncounterTracker(baseline: [old], serverStartedAt: 200)
    #expect(tracker.ingest([updated, fresh]).count == 2)
    #expect(tracker.encounters.map(\.id) == ["pair-b", "pair-a"])
    #expect(tracker.ingest([fresh, updated, fresh]).isEmpty)
    let rotated = try encounter(seen: 220, name: "Updated name")
    #expect(tracker.ingest([rotated]).isEmpty)
    #expect(tracker.encounters.first?.peer.name == "Updated name")
    #expect(tracker.encounters.count == 2)
    #expect(tracker.ingest([updated]).isEmpty)
    #expect(tracker.encounters.first?.lastSeenAt == 220)
}

@Test func walkBaselineAndServerWindowBothGateReveal() throws {
    let existing = try encounter(seen: 201)
    var tracker = WalkEncounterTracker(baseline: [existing, existing], serverStartedAt: 200)
    #expect(tracker.ingest([existing]).isEmpty)
    #expect(tracker.ingest([try encounter(seen: 202)]).count == 1)
    var invalid = WalkEncounterTracker(baseline: [], serverStartedAt: -1)
    #expect(invalid.ingest([existing]).isEmpty)
}

@Test func walkRevealStorageIsBoundedAndSeparateForEveryRun() throws {
    var tracker = WalkEncounterTracker(baseline: [], serverStartedAt: 200)
    for index in 0..<100 {
        tracker.ingest([try encounter("pair-\(index)", seen: 201)])
    }
    #expect(tracker.encounters.count == 50)
    let history = tracker.encounters
    var nextRun = WalkEncounterTracker(baseline: history, serverStartedAt: 300)
    #expect(nextRun.ingest(history).isEmpty)
}
