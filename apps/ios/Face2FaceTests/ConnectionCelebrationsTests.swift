import Face2FaceCore
import XCTest

@testable import Face2Face

@MainActor
final class ConnectionCelebrationsTests: XCTestCase {
    private func connection(_ status: String, id: String = "connection", consent: Bool = false) throws
        -> TownConnection
    {
        let row: [String: Any] = [
            "id": id, "status": status, "sharedInterests": [], "expiresAt": "2026-12-01T00:00:00Z",
            "you": ["decision": "accepted", "publicAt": consent ? "2026-10-25T00:00:00Z" as Any : NSNull()],
            "them": [
                "userId": "private-peer", "name": "MUST STAY HIDDEN",
                "avatar": ["seed": "AAAAAAAAAAAAAAAAAAAAAA"],
            ],
        ]
        return try JSONDecoder().decode(
            TownConnection.self, from: JSONSerialization.data(withJSONObject: row))
    }

    private func feedback(_ haptic: @escaping @MainActor () -> Void = {}) -> ConnectionCelebrations {
        let model = ConnectionCelebrations(haptic: haptic)
        model.bind(accountID: "preview", server: "https://test.invalid", preview: true)
        return model
    }

    func testExistingFriendsAndOneSidedAnswersDoNotCelebrate() throws {
        var taps = 0
        let model = feedback { taps += 1 }
        let rows = try [
            connection("private"), connection("public", id: "old-public"),
            connection("pending", id: "waiting"),
        ]
        model.observeSnapshot(rows, context: model.context, revision: model.revision)
        model.observe(try connection("private", consent: true), context: model.context)
        XCTAssertNil(model.claim(owner: UUID()))
        XCTAssertEqual(taps, 0)
    }

    func testMutualAcceptanceHasOneOwnerAndExactlyOneHaptic() throws {
        var taps = 0
        let model = feedback { taps += 1 }
        model.observeSnapshot([try connection("pending")], context: model.context, revision: model.revision)
        let accepted = try connection("private")
        model.observe(accepted, context: model.context, allowNew: true)
        XCTAssertEqual(taps, 0, "A queued but hidden celebration must not vibrate")
        let owner = UUID()
        XCTAssertEqual(model.claim(owner: owner)?.kind, .privateChat)
        XCTAssertNil(model.claim(owner: UUID()))
        model.observe(accepted, context: model.context, allowNew: true)
        model.observeSnapshot([accepted], context: model.context, revision: model.revision)
        XCTAssertEqual(taps, 1)
        model.dismiss(owner: UUID())
        XCTAssertNotNil(model.presented, "A covered screen cannot dismiss another screen's celebration")
        model.dismiss(owner: owner)
        XCTAssertNil(model.claim(owner: owner))
        XCTAssertEqual(taps, 1)
    }

    func testPublicConsentIsASeparateServerConfirmedMilestone() throws {
        let model = feedback()
        model.observe(try connection("private"), context: model.context)
        model.observe(try connection("private", consent: true), context: model.context)
        XCTAssertNil(model.claim(owner: UUID()))
        model.observe(try connection("public", consent: true), context: model.context)
        let owner = UUID()
        XCTAssertEqual(model.claim(owner: owner)?.kind, .publicProfiles)
        model.dismiss(owner: owner)
        model.observe(try connection("private"), context: model.context)  // Delayed pre-consent response.
        model.observe(try connection("public"), context: model.context)
        XCTAssertNil(model.claim(owner: owner))
    }

    func testSupersededPendingCelebrationShowsOnlyTheLatestStage() throws {
        let model = feedback()
        model.observe(try connection("pending"), context: model.context)
        model.observe(try connection("private"), context: model.context)
        model.observe(try connection("public"), context: model.context)
        let owner = UUID()
        XCTAssertEqual(model.claim(owner: owner)?.kind, .publicProfiles)
        model.dismiss(owner: owner)
        XCTAssertNil(model.claim(owner: owner))
    }

    func testBlockedOrRemovedConnectionsClearFeedbackAndStaleSnapshotsCannotCancelFreshFeedback() throws {
        let model = feedback()
        model.observe(try connection("pending"), context: model.context)
        let stale = model.revision
        model.observe(try connection("private"), context: model.context)
        model.observeSnapshot([], context: model.context, revision: stale)
        let owner = UUID()
        XCTAssertNotNil(model.claim(owner: owner))
        model.observe(try connection("blocked"), context: model.context)
        XCTAssertNil(model.presented)
        XCTAssertNil(model.claim(owner: owner))
        model.observe(try connection("private", id: "removed"), context: model.context, allowNew: true)
        model.observeSnapshot([], context: model.context, revision: model.revision)
        XCTAssertNil(model.claim(owner: owner))
    }

    func testScopeChangesAndSignOutRejectPreviousAccountResults() throws {
        let model = feedback()
        let previous = model.context
        model.observe(try connection("private"), context: previous, allowNew: true)
        model.bind(accountID: "another-person", server: "https://other.invalid", preview: true)
        model.observe(try connection("public"), context: previous, allowNew: true)
        XCTAssertNil(model.claim(owner: UUID()))
        let next = model.context
        model.clear()
        model.observe(try connection("public"), context: next, allowNew: true)
        XCTAssertNil(model.claim(owner: UUID()))
    }

    func testReceiptsSurviveRelaunchWithoutStoringPeerIdentity() throws {
        let name = "ConnectionCelebrationsTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = ConnectionCelebrations(defaults: defaults, haptic: {})
        model.bind(accountID: "account", server: "https://test.invalid")
        model.observeSnapshot([try connection("pending")], context: model.context, revision: model.revision)
        model.observe(try connection("private"), context: model.context)
        let owner = UUID()
        XCTAssertNotNil(model.claim(owner: owner))
        model.dismiss(owner: owner)
        let restored = ConnectionCelebrations(defaults: defaults, haptic: {})
        restored.bind(accountID: "account", server: "https://test.invalid")
        restored.observeSnapshot(
            [try connection("private")], context: restored.context, revision: restored.revision)
        XCTAssertNil(restored.claim(owner: owner))
        restored.observe(try connection("public"), context: restored.context)
        XCTAssertEqual(restored.claim(owner: owner)?.kind, .publicProfiles)
        let stored = String(describing: defaults.persistentDomain(forName: name))
        XCTAssertFalse(stored.contains("MUST STAY HIDDEN"))
        XCTAssertFalse(stored.contains("private-peer"))
    }

    func testRealEncounterAndProfileSharingModelsEmitTheirConfirmedMilestones() async throws {
        ChatPreview.resetProfileSharing(mode: "peer-agreed")
        defer { ChatPreview.resetProfileSharing() }
        let feedback = ConnectionCelebrations(haptic: {})
        let session = SessionModel(celebrations: feedback)
        session.enterTownPreview()
        let encounters = EncountersModel(session: session)
        await encounters.refresh()
        await encounters.decide("preview-chance", decision: .accepted)
        let owner = UUID()
        XCTAssertEqual(feedback.claim(owner: owner)?.kind, .privateChat)
        feedback.dismiss(owner: owner)
        let chat = ChatConversationModel(chatID: "preview-chance", session: session)
        await chat.run()
        await chat.shareProfiles()
        XCTAssertEqual(feedback.claim(owner: owner)?.kind, .publicProfiles)
        feedback.dismiss(owner: owner)
        await chat.stop()
    }
}
