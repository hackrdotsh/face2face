import Face2FaceCore
import XCTest

@testable import Face2Face

@MainActor
private final class CompanionClientStub: BlobCompanionClient {
    var isAvailable = true
    var sessions: [BlobCompanionSession] = []
    var starts = 0
    var ended: [String] = []
    var failsToStart = false
    var continuations: [String: AsyncStream<Bool>.Continuation] = [:]

    func start(seed: String, endsAt: Date) throws -> BlobCompanionSession {
        if failsToStart { throw CocoaError(.featureUnsupported) }
        starts += 1
        let session = BlobCompanionSession(id: UUID().uuidString, seed: seed, endsAt: endsAt)
        sessions.append(session)
        return session
    }

    func end(_ session: BlobCompanionSession) async {
        ended.append(session.id)
        sessions.removeAll { $0.id == session.id }
        continuations.removeValue(forKey: session.id)?.finish()
    }

    func updates(for session: BlobCompanionSession) -> AsyncStream<Bool> {
        AsyncStream { continuations[session.id] = $0 }
    }
}

@MainActor
final class BlobCompanionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let seed = BlobSurface.previewSeed

    func testPendingPresentationIsNotMistakenForDismissal() {
        XCTAssertTrue(SystemBlobCompanionClient.isOngoing(.active))
        if #available(iOS 26.0, *) {
            XCTAssertTrue(SystemBlobCompanionClient.isOngoing(.pending))
        }
        XCTAssertFalse(SystemBlobCompanionClient.isOngoing(.stale))
        XCTAssertFalse(SystemBlobCompanionClient.isOngoing(.ended))
        XCTAssertFalse(SystemBlobCompanionClient.isOngoing(.dismissed))
    }

    func testExplicitStartIsBoundedAndRepeatedStartDoesNotDuplicate() {
        let client = CompanionClientStub()
        let model = BlobCompanionModel(client: client, now: { self.now })
        model.start(seed: seed)
        model.start(seed: seed)
        XCTAssertTrue(model.isEnabled)
        XCTAssertEqual(client.starts, 1)
        XCTAssertEqual(model.session?.endsAt, now.addingTimeInterval(3600))
        XCTAssertEqual(model.session?.seed, seed)
        model.stop()
    }

    func testDisabledAuthorizationAndRequestFailureLeaveToggleOff() {
        let client = CompanionClientStub()
        let model = BlobCompanionModel(client: client)
        client.isAvailable = false
        model.start(seed: seed)
        XCTAssertFalse(model.isEnabled)
        XCTAssertFalse(model.isAvailable)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(client.starts, 0)
        client.isAvailable = true
        client.failsToStart = true
        model.start(seed: seed)
        XCTAssertFalse(model.isEnabled)
        XCTAssertNotNil(model.errorMessage)
    }

    func testRelaunchAdoptsExistingActivityWithoutRestartingIt() {
        let client = CompanionClientStub()
        client.sessions = [.init(id: "existing", seed: seed, endsAt: now.addingTimeInterval(60))]
        let model = BlobCompanionModel(client: client, now: { self.now })
        model.refresh(seed: seed)
        XCTAssertEqual(model.session?.id, "existing")
        XCTAssertEqual(client.starts, 0)
        model.stop()
    }

    func testExpiredAndOtherAccountActivitiesAreRemoved() async {
        let client = CompanionClientStub()
        client.sessions = [
            .init(id: "expired", seed: seed, endsAt: now),
            .init(id: "other", seed: "other-seed", endsAt: now.addingTimeInterval(60)),
        ]
        let model = BlobCompanionModel(client: client, now: { self.now })
        model.refresh(seed: seed)
        XCTAssertFalse(model.isEnabled)
        await drainTasks()
        XCTAssertEqual(Set(client.ended), ["expired", "other"])
    }

    func testSignedOutRefreshClearsEveryActivity() async {
        let client = CompanionClientStub()
        let model = BlobCompanionModel(client: client, now: { self.now })
        model.start(seed: seed)
        model.refresh(seed: nil)
        XCTAssertFalse(model.isEnabled)
        await drainTasks()
        XCTAssertTrue(client.sessions.isEmpty)
    }

    func testRapidOffOnDoesNotReviveOrEndTheWrongActivity() async {
        let client = CompanionClientStub()
        let model = BlobCompanionModel(client: client, now: { self.now })
        model.start(seed: seed)
        let old = model.session?.id
        model.stop()
        model.refresh(seed: seed)
        XCTAssertFalse(model.isEnabled, "Pending teardown must not be re-adopted")
        model.start(seed: seed)
        let new = model.session?.id
        XCTAssertNotEqual(old, new)
        await drainTasks()
        XCTAssertEqual(model.session?.id, new)
        XCTAssertEqual(client.sessions.map(\.id), [new!])
        model.stop()
    }

    func testSystemDismissalTurnsToggleOffWithoutRestart() async {
        let client = CompanionClientStub()
        let model = BlobCompanionModel(client: client, now: { self.now })
        model.start(seed: seed)
        client.continuations[model.session!.id]?.yield(false)
        await drainTasks()
        XCTAssertFalse(model.isEnabled)
        XCTAssertEqual(client.starts, 1)
    }

    func testAuthorizationRevocationEndsExistingActivity() async {
        let client = CompanionClientStub()
        let model = BlobCompanionModel(client: client, now: { self.now })
        model.start(seed: seed)
        client.isAvailable = false
        model.refresh(seed: seed)
        XCTAssertFalse(model.isEnabled)
        await drainTasks()
        XCTAssertTrue(client.sessions.isEmpty)
    }

    func testDailyWidgetSeedIsValidAndChangesAtUTCMidnight() {
        let midnight = Date(timeIntervalSince1970: 20_000 * 86_400)
        let seed = BlobSurface.dailySeed(at: midnight)
        XCTAssertNotNil(BlobAvatar(seed: seed))
        XCTAssertEqual(seed, BlobSurface.dailySeed(at: midnight.addingTimeInterval(86_399)))
        XCTAssertNotEqual(seed, BlobSurface.dailySeed(at: midnight.addingTimeInterval(86_400)))
    }

    func testAttributesContainOnlyDecorativeSeedAndDeadline() throws {
        let attributes = BlobCompanionAttributes(seed: seed)
        let state = BlobCompanionAttributes.ContentState(endsAt: now)
        let object =
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(attributes)) as? [String: Any]
        let content = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any]
        XCTAssertEqual(Set(object?.keys.map { $0 } ?? []), ["seed"])
        XCTAssertEqual(Set(content?.keys.map { $0 } ?? []), ["endsAt"])
    }

    private func drainTasks() async {
        for _ in 0..<20 { await Task.yield() }
    }
}
