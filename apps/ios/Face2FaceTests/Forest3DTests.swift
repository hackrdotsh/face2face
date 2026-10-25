import RealityKit
import XCTest

@testable import Face2Face

@available(iOS 18.0, *)
@MainActor
final class Forest3DTests: XCTestCase {
    func testForestHasPinesSeededBlobsAndAnOrthographicCamera() throws {
        let world = try Forest3DWorld()
        let entities = descendants(world.root)
        XCTAssertEqual(entities.filter { $0.name == "forest-pine" }.count, 240)
        XCTAssertEqual(entities.filter { $0.name == "forest-blob" }.count, 3)
        XCTAssertEqual(entities.filter { $0.name == "blob-eye" }.count, 6)
        XCTAssertNotNil(world.camera.components[OrthographicCameraComponent.self])
    }

    func testDayAndNightUpdateWithoutRebuildingTheWorld() throws {
        let world = try Forest3DWorld()
        let lights = descendants(world.root).filter { $0.name == "firefly" }
        XCTAssertTrue(lights.allSatisfy { !$0.isEnabled })
        world.configure(dark: true, viewport: CGSize(width: 420, height: 912), bottomInset: 130)
        XCTAssertTrue(lights.allSatisfy(\.isEnabled))
        world.configure(dark: false, viewport: CGSize(width: 420, height: 912), bottomInset: 130)
        XCTAssertTrue(lights.allSatisfy { !$0.isEnabled })
    }

    func testInvalidFrameTimeCannotMoveTheCameraOrBlobs() throws {
        let world = try Forest3DWorld()
        let initialCamera = world.camera.position
        let blobs = descendants(world.root).filter { $0.name == "forest-blob" }
        let initialPositions = blobs.map(\.position)
        world.update(delta: .nan)
        world.update(delta: .infinity)
        XCTAssertEqual(world.camera.position, initialCamera)
        XCTAssertEqual(blobs.map(\.position), initialPositions)
    }

    func testPineBoughsKeepThreeDistinctMaterialBands() throws {
        let world = try Forest3DWorld()
        let boughs = descendants(world.root).compactMap { $0 as? ModelEntity }.filter {
            $0.name.hasPrefix("needles-")
        }
        XCTAssertEqual(boughs.count, 240 * 3)
        XCTAssertTrue(boughs.allSatisfy { $0.model?.materials.count == 3 })
    }

    func testMeetingBlobsShowWaveBubblesAndRingsThenContinue() throws {
        let world = try Forest3DWorld(initialTime: 4)
        let bubbles = descendants(world.root).filter { $0.name == "greeting-bubble" }
        let rings = descendants(world.root).filter { $0.name == "greeting-halo" }
        XCTAssertEqual(bubbles.filter(\.isEnabled).count, 2)
        XCTAssertEqual(rings.filter(\.isEnabled).count, 2)
        for _ in 0..<20 { world.update(delta: 0.1) }
        XCTAssertTrue(bubbles.allSatisfy { !$0.isEnabled })
        XCTAssertTrue(rings.allSatisfy { !$0.isEnabled })
    }

    func testFirefliesFollowTheForestTileNotTheCamera() throws {
        let world = try Forest3DWorld()
        let entities = descendants(world.root)
        let firefly = try XCTUnwrap(entities.first { $0.name == "firefly" })
        let pine = try XCTUnwrap(entities.first { $0.name == "forest-pine" })
        XCTAssertTrue(firefly.parent === pine.parent)
        let forest = try XCTUnwrap(firefly.parent)
        let before = forest.position.z
        let localPosition = firefly.position
        world.update(delta: 0.1)
        XCTAssertEqual(forest.position.z - before, 0.065, accuracy: 0.001)
        XCTAssertLessThan(abs(firefly.position.z - localPosition.z), 0.02)
        XCTAssertFalse(firefly.parent === world.camera)
    }

    func testMainBlobWalksAwayAndTurnsTowardTheOtherBlobToGreet() throws {
        let walking = try Forest3DWorld()
        let walkers = descendants(walking.root).filter { $0.name == "forest-blob" }
        XCTAssertLessThan(walkers[0].orientation.act([0, 0, 1]).z, -0.9)
        XCTAssertGreaterThan(walkers[1].orientation.act([0, 0, 1]).z, 0.9)
        let greeting = try Forest3DWorld(initialTime: 4)
        let greeters = descendants(greeting.root).filter { $0.name == "forest-blob" }
        XCTAssertGreaterThan(greeters[0].orientation.act([0, 0, 1]).x, 0.8)
        XCTAssertLessThan(greeters[1].orientation.act([0, 0, 1]).x, -0.8)
    }

    private func descendants(_ entity: Entity) -> [Entity] {
        [entity] + entity.children.flatMap(descendants)
    }
}
