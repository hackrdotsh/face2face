import Foundation
import Testing

@testable import Face2FaceCore

@Test private func restsAtTheStartOfEveryLoop() {
    let pose = BlobIdleMotion(seed: []).pose(at: 0)
    #expect(pose == BlobIdleMotion.Pose(breath: 0, gaze: 0, eyeOpenness: 1))
}

@Test private func breathesWithoutMovingTheOutlineFarFromRest() throws {
    let blob = try #require(BlobAvatar(seed: "AAECAwQFBgcICQoLDA0ODw"))
    let rest = BlobIdleMotion(seed: []).pose(at: 0).breath
    let swell = BlobIdleMotion(seed: []).pose(at: BlobIdleMotion.breathePeriod / 4).breath
    let moved = zip(blob.outline(breath: rest).curves, blob.outline(breath: swell).curves).map {
        hypot($0.end.x - $1.end.x, $0.end.y - $1.end.y)
    }
    #expect(moved.contains { $0 > 0.005 })
    #expect(moved.allSatisfy { $0 <= 0.024 + 1e-9 })
}

@Test private func blinksNearTheEndOfTheBlinkLoop() {
    let pose = BlobIdleMotion(seed: []).pose(at: BlobIdleMotion.blinkPeriod * 0.96)
    #expect(abs(pose.eyeOpenness - 0.1) < 1e-9)
}

@Test private func glancesBothWays() {
    let motion = BlobIdleMotion(seed: [])
    #expect(motion.pose(at: BlobIdleMotion.lookPeriod * 0.5).gaze < 0)
    #expect(motion.pose(at: BlobIdleMotion.lookPeriod * 0.75).gaze > 0)
}

@Test private func takesItsPhaseFromTheLastSeedByte() {
    let seed = [UInt8](repeating: 0, count: 15) + [255]
    #expect(BlobIdleMotion(seed: seed).phase == 1)
    #expect(BlobIdleMotion(seed: [UInt8](repeating: 0, count: 16)).phase == 0)
}
