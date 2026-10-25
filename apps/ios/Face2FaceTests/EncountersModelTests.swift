import Face2FaceCore
import XCTest

@testable import Face2Face

private actor PendingEncounters: EncounterRepository {
    private var started = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var response: CheckedContinuation<[TownConnection], Never>?
    func townConnections() async -> [TownConnection] {
        await withCheckedContinuation { value in
            response = value
            started = true
            waiter?.resume()
            waiter = nil
        }
    }
    func waitForStart() async {
        if started { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func finish(_ rows: [TownConnection]) {
        response?.resume(returning: rows)
        response = nil
    }
    func decideConnection(_ id: String, decision: ConnectionDecision) throws -> TownConnection {
        throw APIError.chanceEnded
    }
    func blockConnection(_ id: String) {}
}

@MainActor
final class EncountersModelTests: XCTestCase {
    func testOneAcceptanceWaitsAndCannotBeAnsweredTwice() async throws {
        let source = PreviewEncounterRepository()
        let model = EncountersModel(repository: source)
        await model.refresh()
        await model.decide("preview-decline", decision: .accepted)
        XCTAssertEqual(model.chances.first { $0.id == "preview-decline" }?.you?.decision, .accepted)
        XCTAssertNil(model.newlyConnectedID)
        await model.decide("preview-decline", decision: .accepted)
        await model.decide("preview-decline", decision: .declined)
        let count = await source.answerCount
        XCTAssertEqual(count, 1)
    }
    func testMutualAcceptanceMovesChanceToChatWithoutBecomingPublic() async {
        let source = PreviewEncounterRepository()
        let model = EncountersModel(repository: source)
        await model.refresh()
        await model.decide("preview-chance", decision: .accepted)
        XCTAssertEqual(model.newlyConnectedID, "preview-chance")
        XCTAssertFalse(model.chances.contains { $0.id == "preview-chance" })
        model.openedChat("preview-chance")
        await model.refresh()
        XCTAssertNil(model.newlyConnectedID)
    }
    func testDeclineRemovesTheChanceAndItDoesNotReappearOnRefresh() async {
        let source = PreviewEncounterRepository()
        let model = EncountersModel(repository: source)
        await model.refresh()
        await model.decide("preview-decline", decision: .declined)
        await model.refresh()
        XCTAssertFalse(model.chances.contains { $0.id == "preview-decline" })
        XCTAssertNil(model.newlyConnectedID)
        XCTAssertNotNil(model.notice)
    }
    func testPeerAcceptanceAppearsOnRefreshAndStaleChanceIsRemoved() async {
        let source = PreviewEncounterRepository(state: "peer-accepts")
        let model = EncountersModel(repository: source)
        await model.refresh()
        await model.refresh()
        XCTAssertEqual(model.newlyConnectedID, "preview-waiting")
        let stale = EncountersModel(repository: PreviewEncounterRepository(state: "stale"))
        await stale.refresh()
        await stale.decide("preview-chance", decision: .accepted)
        XCTAssertFalse(stale.chances.contains { $0.id == "preview-chance" })
        XCTAssertNotNil(stale.error)
    }
    func testLostAnswerResponseIsReconciledWithoutDuplicateSubmission() async {
        let source = PreviewEncounterRepository(state: "lost-response")
        let model = EncountersModel(repository: source)
        await model.refresh()
        await model.decide("preview-chance", decision: .accepted)
        XCTAssertEqual(model.newlyConnectedID, "preview-chance")
        XCTAssertNil(model.error)
        let count = await source.answerCount
        XCTAssertEqual(count, 1)
    }
    func testBackgroundClearRejectsAnInflightResponse() async throws {
        let rows = try await PreviewEncounterRepository().townConnections()
        let source = PendingEncounters()
        let model = EncountersModel(repository: source)
        let request = Task { await model.refresh() }
        await source.waitForStart()
        model.clearVisibleData()
        await source.finish(rows)
        await request.value
        XCTAssertTrue(model.chances.isEmpty)
        XCTAssertNil(model.newlyConnectedID)
    }
}
