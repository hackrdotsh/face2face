import Testing

@testable import Face2FaceCore

@Test func walkMatchTrackerCountsEachMatchOnce() {
    var tracker = WalkMatchTracker()
    #expect(tracker.ingest(ObservationReceipt(status: .pending)) == false)
    #expect(tracker.ingest(ObservationReceipt(status: .recorded, matchId: "match-a")) == true)
    #expect(tracker.ingest(ObservationReceipt(status: .recorded, matchId: "match-a")) == false)
    #expect(tracker.ingest(ObservationReceipt(status: .recorded, matchId: "match-b")) == true)
    #expect(tracker.matchIds == ["match-a", "match-b"])
}

@Test func walkMatchTrackerIgnoresRecordedReceiptsWithoutAnID() {
    var tracker = WalkMatchTracker()
    #expect(tracker.ingest(ObservationReceipt(status: .recorded)) == false)
    #expect(tracker.matchIds.isEmpty)
}

@Test func walkMatchTrackerIsBounded() {
    var tracker = WalkMatchTracker()
    for index in 0..<WalkMatchTracker.limit {
        tracker.ingest(ObservationReceipt(status: .recorded, matchId: "match-\(index)"))
    }
    #expect(tracker.ingest(ObservationReceipt(status: .recorded, matchId: "one-more")) == false)
    #expect(tracker.matchIds.count == WalkMatchTracker.limit)
}

@Test func walkMatchTrackerCountsOnlyItsStatus() {
    var matches = WalkMatchTracker()
    var unshared = WalkMatchTracker(counting: .noSharedInterests)
    let receipt = ObservationReceipt(status: .noSharedInterests, matchId: "match-a")
    #expect(matches.ingest(receipt) == false)
    #expect(unshared.ingest(receipt) == true)
    #expect(unshared.ingest(receipt) == false)
    #expect(unshared.ingest(ObservationReceipt(status: .recorded, matchId: "match-b")) == false)
}
