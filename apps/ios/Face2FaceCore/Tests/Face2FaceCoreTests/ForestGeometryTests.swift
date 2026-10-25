import Foundation
import Testing

@testable import Face2FaceCore

@Test func pineCrownsHavePointedTipsLeafClustersAndSeparateUndersides() {
    for branches in [6, 8, 9, 10, 12] {
        let mesh = PineCrown(branches: branches)
        #expect(mesh.positions.count == mesh.normals.count)
        #expect(mesh.indices.count == mesh.positions.count)
        #expect(mesh.faceMaterials.count == mesh.indices.count / 3)
        #expect(Set(mesh.faceMaterials) == [0, 1, 2])
        #expect(mesh.positions.contains([0, 1, 0]))
        #expect(mesh.positions.count > branches * 100)
        #expect(mesh.positions.allSatisfy { $0.y >= 0 && $0.y <= 1 })
        #expect(mesh.positions.contains { abs($0.y - 0.05) < 0.001 })
        for normal in mesh.normals {
            let length = sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z)
            #expect(abs(length - 1) < 0.001)
        }
        #expect(mesh.indices.allSatisfy { $0 < mesh.positions.count })
    }
}

@Test func decorativeBlobGreetingsRepeatAndEndAfterTheCrossing() {
    let before = ForestPasserPose.at(time: 0, slot: 0)
    #expect(before.z < 4 && before.greetingProgress == nil)
    for (time, slot) in [(4.0, 0), (20.0, 1), (36.0, 0), (52.0, 1)] {
        let pose = ForestPasserPose.at(time: time, slot: slot)
        #expect(abs(pose.z - 4) < 0.001)
        #expect(abs(pose.greetingStrength - 1) < 0.001)
        #expect(ForestPasserPose.at(time: time + 1, slot: slot).greetingProgress == nil)
    }
    #expect(ForestPasserPose.at(time: .infinity, slot: 0).greetingProgress == nil)
    #expect(ForestPasserPose.at(time: .nan, slot: 0).greetingProgress == nil)
}
