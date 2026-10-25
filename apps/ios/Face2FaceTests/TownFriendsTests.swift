import Face2FaceCore
import XCTest

@testable import Face2Face

private func publicFriend(_ id: String) throws -> PublicTownFriend {
    let json = """
        {"id":"\(id)","status":"public","sharedInterests":["coffee"],"expiresAt":"2026-10-26T00:00:00Z",
         "them":{"userId":"user-\(id)","name":"Friend \(id)","age":24,"interests":["coffee"],
         "avatar":{"seed":"AAAAAAAAAAAAAAAAAAAAAA"}}}
        """
    let connection = try JSONDecoder().decode(TownConnection.self, from: Data(json.utf8))
    return try XCTUnwrap(connection.publicTownFriend)
}

private actor PendingFriends {
    private var started = false
    private var waiting: CheckedContinuation<Void, Never>?
    private var response: CheckedContinuation<[PublicTownFriend], Never>?
    func load() async -> [PublicTownFriend] {
        await withCheckedContinuation { continuation in
            response = continuation
            started = true
            waiting?.resume()
            waiting = nil
        }
    }
    func waitForStart() async {
        if started { return }
        await withCheckedContinuation { waiting = $0 }
    }
    func finish(_ friends: [PublicTownFriend]) {
        response?.resume(returning: friends)
        response = nil
    }
}

@MainActor
final class TownFriendsTests: XCTestCase {
    func testPublicProfileIsRecheckedAndDisappearsWhenRevoked() async throws {
        let friend = try publicFriend("one")
        var result = [friend]
        let model = TownFriendsModel(load: { result })
        await model.refresh()
        XCTAssertEqual(model.visitors, [friend])
        model.select(friend)
        XCTAssertNil(model.selectedProfile, "A cached NPC is not permission to show a profile")
        await model.refresh()
        XCTAssertEqual(model.selectedProfile, friend)
        result = []
        await model.refresh()
        XCTAssertNil(model.selectedProfile)
        XCTAssertTrue(model.visitors.isEmpty)
        XCTAssertTrue(model.profileChecked)
    }

    func testFailedRevalidationRemovesStaleFacesAndProfiles() async throws {
        let friend = try publicFriend("one")
        var fail = false
        let model = TownFriendsModel(load: {
            if fail { throw APIError.server(503) }
            return [friend]
        })
        await model.refresh()
        model.select(friend)
        await model.refresh()
        XCTAssertNotNil(model.selectedProfile)
        fail = true
        await model.refresh()
        XCTAssertNil(model.selectedProfile)
        XCTAssertTrue(model.visitors.isEmpty)
        XCTAssertNotNil(model.error)
    }

    func testLimitsVisitorsAndCannotOpenAnUnlistedConnection() async throws {
        let friends = try (0..<5).map { try publicFriend(String($0)) }
        let model = TownFriendsModel(load: { friends + [friends[0]] })
        await model.refresh()
        XCTAssertEqual(model.visitors.count, 3)
        XCTAssertEqual(Set(model.visitors.map(\.userId)).count, 3)
        let unlisted = try XCTUnwrap(friends.first { !model.visitors.contains($0) })
        model.select(unlisted)
        XCTAssertNil(model.selectedID)
    }

    func testBackgroundClearRejectsAnInflightResponse() async throws {
        let friend = try publicFriend("one")
        let source = PendingFriends()
        let model = TownFriendsModel(load: { await source.load() })
        let request = Task { await model.refresh() }
        await source.waitForStart()
        model.clearVisibleData()
        await source.finish([friend])
        await request.value
        XCTAssertTrue(model.visitors.isEmpty)
        XCTAssertNil(model.selectedProfile)
    }

    func testResidentMovementIsBoundedAndDeterministic() {
        for slot in 0..<3 {
            for time in [0.0, 5, 50, 10000, .nan, .infinity] {
                let pose = TownResidentMotion.pose(slot: slot, time: time)
                XCTAssertTrue(pose.point.x.isFinite && pose.point.y.isFinite)
                XCTAssertTrue((0...400).contains(pose.point.x))
                XCTAssertTrue((0...560).contains(pose.point.y))
            }
            XCTAssertEqual(
                TownResidentMotion.pose(slot: slot, time: 0).point,
                TownResidentMotion.pose(slot: slot, time: 0).point)
        }
    }
}
