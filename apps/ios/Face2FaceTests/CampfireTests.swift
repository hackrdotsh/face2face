import Face2FaceCore
import XCTest

@testable import Face2Face

@MainActor
final class CampfireTests: XCTestCase {
    func testAllFriendsAppearAcrossPagesWithoutDuplicates() {
        let guests = (0..<47).map {
            CampfireGuest(id: $0, name: "Friend \($0)", seed: BlobSurface.previewSeed, isAnonymous: true)
        }
        let snapshot = CampfireSnapshot(status: .ready, guests: guests)
        for size in [4, 6, 10] {
            let pages = (0..<snapshot.pageCount(size: size)).flatMap { snapshot.page($0, size: size) }
            XCTAssertEqual(pages.map(\.id), Array(0..<47))
            XCTAssertEqual(
                snapshot.page(-1, size: size), snapshot.page(snapshot.pageCount(size: size) - 1, size: size))
        }
    }

    func testOnlyAcceptedConnectionsAreIncludedAndPrivateIdentityIsIgnored() throws {
        let rows = ["public", "private", "pending", "blocked", "expired"].map { status in
            [
                "id": status, "status": status, "sharedInterests": [], "expiresAt": "2099-01-01T00:00:00Z",
                "them": [
                    "userId": "hidden-user", "name": "Should Only Be Public",
                    "avatar": ["seed": BlobSurface.previewSeed],
                ],
            ] as [String: Any]
        }
        let connections = try JSONDecoder().decode(
            [TownConnection].self, from: JSONSerialization.data(withJSONObject: rows))
        let guests = CampfireWidgetModel.guests(from: connections + connections)
        XCTAssertEqual(guests.count, 2)
        XCTAssertEqual(guests.filter(\.isAnonymous).map(\.name), ["Anonymous friend"])
        XCTAssertEqual(guests.filter { !$0.isAnonymous }.map(\.name), ["Should Only Be Public"])
        let encoded = String(decoding: try JSONEncoder().encode(guests), as: UTF8.self)
        XCTAssertFalse(encoded.contains("hidden-user"))
        XCTAssertFalse(encoded.contains("userId"))
        XCTAssertFalse(encoded.contains("connectionId"))
    }

    func testSnapshotExpiryAndClockRollbackHideAllFriends() {
        let now = Date()
        let snapshot = CampfireSnapshot(
            status: .ready,
            guests: [.init(id: 0, name: "Ava", seed: BlobSurface.previewSeed, isAnonymous: false)],
            updatedAt: now)
        XCTAssertEqual(snapshot.visible(at: now).guests.count, 1)
        XCTAssertEqual(snapshot.visible(at: snapshot.expiresAt).status, .expired)
        XCTAssertTrue(snapshot.visible(at: snapshot.expiresAt).guests.isEmpty)
        XCTAssertTrue(snapshot.visible(at: now.addingTimeInterval(-6)).guests.isEmpty)
    }

    func testSharedStoreClearingAndPageNavigation() {
        let name = "campfire-tests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let guests = (0..<9).map {
            CampfireGuest(id: $0, name: "Friend", seed: BlobSurface.previewSeed, isAnonymous: true)
        }
        CampfireStore.write(.init(status: .ready, guests: guests), defaults: defaults)
        CampfireStore.advance(by: 1, size: 4, defaults: defaults)
        XCTAssertEqual(CampfireStore.page(size: 4, defaults: defaults), 1)
        CampfireStore.advance(by: -1, size: 4, defaults: defaults)
        XCTAssertEqual(CampfireStore.page(size: 4, defaults: defaults), 0)
        CampfireStore.advance(by: -1, size: 4, defaults: defaults)
        XCTAssertEqual(CampfireStore.page(size: 4, defaults: defaults), 2)
        CampfireStore.clear(.signedOut, defaults: defaults)
        XCTAssertEqual(CampfireStore.read(defaults: defaults).status, .signedOut)
        XCTAssertTrue(CampfireStore.read(defaults: defaults).guests.isEmpty)
        XCTAssertEqual(CampfireStore.page(size: 4, defaults: defaults), 0)
    }
}
