import Face2FaceCore
import XCTest

@testable import Face2Face

@MainActor
final class ProfileSharingTests: XCTestCase {
    private func model(
        load: (@MainActor () async throws -> ChatSummary)? = nil,
        consent: (@MainActor () async throws -> TownConnection)? = nil
    ) -> ChatConversationModel {
        let session = SessionModel()
        session.enterTownPreview()
        return ChatConversationModel(chatID: "preview-private", session: session,
            loadSummary: load, recordProfileConsent: consent)
    }

    func testOneConsentWaitsAnonymouslyAndCannotBeRepeated() async throws {
        defer { ChatPreview.resetProfileSharing() }
        ChatPreview.resetProfileSharing()
        let model = model()
        await model.run()
        XCTAssertTrue(model.summary?.connection.canOfferProfileSharing == true)
        await model.shareProfiles()
        XCTAssertTrue(model.summary?.connection.hasChosenProfileSharing == true)
        XCTAssertFalse(model.summary?.connection.canOfferProfileSharing == true)
        XCTAssertEqual(model.summary?.title, "Anonymous connection")
        XCTAssertNil(model.summary?.connection.publicTownFriend)
        XCTAssertTrue(try ChatPreview.sharedPublicFriends().isEmpty)
        await model.shareProfiles()
        model.draft = "Still chatting anonymously"
        XCTAssertTrue(model.send(photo: nil))
        await model.stop()
        await model.run()
        XCTAssertTrue(model.summary?.connection.hasChosenProfileSharing == true)
        await model.stop()
    }

    func testSecondConsentRevealsProfileAndRefreshesTownWithNewVisitor() async throws {
        defer { ChatPreview.resetProfileSharing() }
        ChatPreview.resetProfileSharing(mode: "peer-agreed")
        let model = model()
        await model.run()
        let revision = PublicConnectionUpdates.shared.revision
        await model.shareProfiles()
        XCTAssertEqual(model.summary?.title, "Rowan")
        XCTAssertEqual(model.summary?.connection.status, "public")
        XCTAssertEqual(PublicConnectionUpdates.shared.revision, revision + 1)
        let friend = try XCTUnwrap(model.summary?.connection.publicTownFriend)
        let others = try ChatPreview.chats().compactMap { $0.connection.publicTownFriend }.filter { $0.id != friend.id }
        let town = TownFriendsModel(load: { others + [friend] })
        await town.refresh(preferredConnectionID: model.chatID)
        XCTAssertEqual(town.visitors.first?.id, model.chatID)
        town.openPublicConnection(model.chatID)
        XCTAssertNil(town.selectedProfile)
        await town.refresh()
        XCTAssertEqual(town.selectedProfile?.name, "Rowan")
        await model.stop()
    }

    func testPeerConsentIsPickedUpWithoutReopeningChat() async {
        defer { ChatPreview.resetProfileSharing() }
        ChatPreview.resetProfileSharing(mode: "peer-later")
        let model = model()
        await model.run()
        await model.shareProfiles()
        XCTAssertEqual(model.summary?.title, "Anonymous connection")
        await model.refreshConnection()
        XCTAssertEqual(model.summary?.title, "Rowan")
        await model.stop()
    }

    func testLostConsentReplyReconcilesWithoutPostingTwice() async {
        defer { ChatPreview.resetProfileSharing() }
        ChatPreview.resetProfileSharing()
        var posts = 0
        let model = model(consent: {
            posts += 1
            _ = try ChatPreview.shareProfiles(chatID: "preview-private")
            throw URLError(.timedOut)
        })
        await model.run()
        await model.shareProfiles()
        XCTAssertEqual(posts, 1)
        XCTAssertTrue(model.summary?.connection.hasChosenProfileSharing == true)
        XCTAssertNil(model.profileSharingError)
        XCTAssertEqual(model.summary?.title, "Anonymous connection")
        await model.stop()
    }

    func testFailedConsentStaysAnonymousAndCanStillSend() async {
        defer { ChatPreview.resetProfileSharing() }
        ChatPreview.resetProfileSharing()
        let model = model(consent: { throw URLError(.notConnectedToInternet) })
        await model.run()
        await model.shareProfiles()
        XCTAssertNotNil(model.profileSharingError)
        XCTAssertEqual(model.summary?.title, "Anonymous connection")
        XCTAssertTrue(model.summary?.connection.canOfferProfileSharing == true)
        model.draft = "No need to share"
        XCTAssertTrue(model.send(photo: nil))
        await model.stop()
    }

    func testBlockedRefreshClosesAndClearsIdentity() async throws {
        defer { ChatPreview.resetProfileSharing() }
        ChatPreview.resetProfileSharing(mode: "peer-agreed")
        var blocked = false
        let model = model(load: {
            if blocked { throw APIError.server(404) }
            return try XCTUnwrap(ChatPreview.chat("preview-private"))
        })
        await model.run()
        await model.shareProfiles()
        XCTAssertEqual(model.summary?.title, "Rowan")
        blocked = true
        await model.refreshConnection()
        XCTAssertEqual(model.state, .closed)
        XCTAssertNil(model.summary)
        await model.stop()
    }

    func testConsentReplyAfterStopCannotRestoreProfile() async throws {
        defer { ChatPreview.resetProfileSharing() }
        ChatPreview.resetProfileSharing(mode: "peer-agreed")
        var pending: CheckedContinuation<TownConnection, any Error>?
        let model = model(consent: { try await withCheckedThrowingContinuation { pending = $0 } })
        await model.run()
        let task = Task { await model.shareProfiles() }
        for _ in 0..<100 { if pending != nil { break }; await Task.yield() }
        XCTAssertNotNil(pending)
        await model.shareProfiles() // Duplicate tap must not start another POST.
        await model.stop()
        let connection = try ChatPreview.shareProfiles(chatID: "preview-private")
        pending?.resume(returning: connection)
        await task.value
        XCTAssertNil(model.summary)
        XCTAssertFalse(model.isSharingProfiles)
        XCTAssertEqual(model.state, .paused)
    }

    func testLatePrivateRefreshCannotOverwriteConsentReply() async throws {
        defer { ChatPreview.resetProfileSharing() }
        ChatPreview.resetProfileSharing(mode: "peer-agreed")
        let initial = try XCTUnwrap(ChatPreview.chat("preview-private"))
        var slow = false
        var pending: CheckedContinuation<ChatSummary, any Error>?
        let model = model(load: {
            if slow { return try await withCheckedThrowingContinuation { pending = $0 } }
            return initial
        })
        await model.run()
        slow = true
        let task = Task { await model.refreshConnection() }
        for _ in 0..<100 { if pending != nil { break }; await Task.yield() }
        XCTAssertNotNil(pending)
        await model.shareProfiles()
        pending?.resume(returning: initial)
        await task.value
        XCTAssertEqual(model.summary?.title, "Rowan")
        await model.stop()
    }
}
