import Face2FaceCore
import RealityKit
import XCTest

@testable import Face2Face

@available(iOS 18.0, *)
@MainActor
final class Town3DTests: XCTestCase {
    func testStripedCanopiesLeaveTheCountersVisible() throws {
        for cafe in [false, true] {
            let stall = try Town3DAssets.marketStall(cafe: cafe)
            let canopy = try XCTUnwrap(stall.children.first { $0.name == "stall-canopy" })
            let counter = try XCTUnwrap(stall.children.first { $0.name == "stall-counter" })
            XCTAssertEqual(canopy.children.count, 24)
            XCTAssertEqual(canopy.children.filter { $0.name == "canvas-cream" }.count, 12)
            let roofBounds = canopy.visualBounds(relativeTo: stall)
            let counterBounds = counter.visualBounds(relativeTo: stall)
            let roofEdge = TownProjection.screen([0, roofBounds.min.y, roofBounds.max.z])
            let counterEdge = TownProjection.screen([0, counterBounds.max.y, counterBounds.max.z])
            XCTAssertGreaterThan(counterEdge.y - roofEdge.y, 25)
        }
    }

    func testFountainWaterSitsInsideTheRim() throws {
        let fountain = try Town3DAssets.fountain()
        let basin = try XCTUnwrap(fountain.children.first { $0.name == "stone-cut" })
        let water = try XCTUnwrap(fountain.children.first { $0.name == "water" })
        let rim = basin.visualBounds(relativeTo: fountain)
        let surface = water.visualBounds(relativeTo: fountain)
        XCTAssertLessThan(surface.max.y, rim.max.y)
        XCTAssertLessThan(surface.extents.x, rim.extents.x)
        XCTAssertEqual(fountain.children.filter { $0.name == "water-stream" }.count, 4)
        for child in fountain.children {
            let bounds = child.visualBounds(relativeTo: fountain)
            for axis in 0..<3 {
                XCTAssertTrue(bounds.min[axis].isFinite)
                XCTAssertTrue(bounds.max[axis].isFinite)
            }
        }
    }

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
                let expected = TownPlazaLayout.resident(slot: slot, time: time).point
                let actual = TownProjection.screen(entity.position)
                XCTAssertEqual(actual.x, expected.x, accuracy: 0.001)
                XCTAssertEqual(actual.y, expected.y, accuracy: 0.001)
            }
        }
    }

    func testTreesSurroundThePlazaWithoutBlockingItsEntrances() throws {
        let world = try Town3DWorld()
        let trees = world.root.children.filter { $0.name == "forest-pine" }
        let points: [TownProjection.Point] = trees.map { TownProjection.screen($0.position) }
        let perimeter = points.filter { point in
            let outsideSides = point.x < 25 || point.x > 375
            let outsideEnds = point.y < 135 || point.y > 548
            return outsideSides || outsideEnds
        }
        XCTAssertGreaterThanOrEqual(perimeter.count, 30)
        XCTAssertTrue(perimeter.contains { $0.x < 25 && $0.y > 200 && $0.y < 500 })
        XCTAssertTrue(perimeter.contains { $0.x > 375 && $0.y > 200 && $0.y < 500 })
        XCTAssertTrue(perimeter.contains { $0.y < 135 })
        XCTAssertTrue(perimeter.contains { $0.y > 548 })
        XCTAssertFalse(perimeter.contains { $0.x > 170 && $0.x < 230 })
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
