import Face2FaceCore
import RealityKit
import XCTest

@testable import Face2Face

@available(iOS 18.0, *)
@MainActor
final class Town3DTests: XCTestCase {
    func testTownHasThreePlacesAndUsesTheMapCamera() throws {
        let world = try Town3DWorld()
        let names = world.root.children.map(\.name)
        for name in ["town-venue", "town-cafe", "town-board"] { XCTAssertTrue(names.contains(name)) }
        XCTAssertEqual(names.filter { $0.hasPrefix("town-blob-") }.count, 3)
        XCTAssertNotNil(world.camera.components[OrthographicCameraComponent.self])
        world.configure(dark: true, viewport: CGSize(width: 420, height: 800))
        XCTAssertEqual(world.camera.components[OrthographicCameraComponent.self]?.scale, 5)
    }

    func testResidentMeshesAndTapCoordinatesStayAligned() throws {
        let world = try Town3DWorld()
        for time in [0.0, 3.0, 15.0, 60.0] {
            world.update(time: time)
            for slot in 0..<3 {
                let entity = try XCTUnwrap(world.root.children.first { $0.name == "town-blob-\(slot)" })
                let expected = TownResidentMotion.pose(slot: slot, time: time).point
                let actual = TownProjection.screen(entity.position)
                XCTAssertEqual(actual.x, expected.x, accuracy: 0.001)
                XCTAssertEqual(actual.y, expected.y, accuracy: 0.001)
            }
        }
    }

    func testClearingPublicVisitorsRemovesTheirMeshes() throws {
        let world = try Town3DWorld()
        let friends = try (0..<4).map { index -> PublicTownFriend in
            let json = """
                {"id":"friend-\(index)","status":"public","sharedInterests":[],"expiresAt":"2026-12-01T00:00:00Z",
                 "them":{"userId":"person-\(index)","name":"Friend","avatar":{"seed":"AAAAAAAAAAAAAAAAAAAAAA"}}}
                """
            let connection = try JSONDecoder().decode(TownConnection.self, from: Data(json.utf8))
            return try XCTUnwrap(connection.publicTownFriend)
        }
        try world.updateVisitors(friends)
        XCTAssertEqual(world.publicVisitorCount, 3)
        let previous = world.root.children.filter { $0.name.hasPrefix("town-blob-") }
        try world.updateVisitors([])
        XCTAssertEqual(world.publicVisitorCount, 0)
        XCTAssertTrue(previous.allSatisfy { $0.parent == nil })
        XCTAssertEqual(world.root.children.filter { $0.name.hasPrefix("town-blob-") }.count, 3)
    }
}
