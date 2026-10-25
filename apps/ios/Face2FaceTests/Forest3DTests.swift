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

    private func descendants(_ entity: Entity) -> [Entity] {
        [entity] + entity.children.flatMap(descendants)
    }
}
