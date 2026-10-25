import Testing

@testable import Face2FaceCore

@Test func townCameraAndHitTargetsUseTheSameCoordinates() {
    for x in stride(from: 0.0, through: 400, by: 40) {
        for y in stride(from: 0.0, through: 640, by: 40) {
            for height in [0.0, 0.5, 2.0] {
                let point = TownProjection.screen(TownProjection.world(x: x, y: y, elevation: height))
                #expect(abs(point.x - x) < 0.0001)
                #expect(abs(point.y - y) < 0.0001)
            }
        }
    }
}

@Test func townProjectionPutsGroundFartherDownThanRoofs() {
    let ground = TownProjection.world(x: 110, y: 200)
    let roof = ground + SIMD3<Float>(0, 2, 0)
    #expect(TownProjection.screen(roof).y < TownProjection.screen(ground).y)
    #expect(TownProjection.screen(roof).x == TownProjection.screen(ground).x)
}
