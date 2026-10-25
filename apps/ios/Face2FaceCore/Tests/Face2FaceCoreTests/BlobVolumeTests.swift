import Foundation
import Testing

@testable import Face2FaceCore

@Test func blobVolumesAreFiniteBoundedAndIndexedForEverySilhouette() {
    for kind: UInt8 in 0...2 {
        let avatar = BlobAvatar(seed: [kind, 1, 24, 80, 255, 20, 180, 100, 255, 30, 200, 120])
        let mesh = BlobVolume(avatar: avatar)
        #expect(mesh.positions.count == 21 * avatar.curves.count * 8)
        #expect(mesh.positions.count == mesh.normals.count)
        #expect(mesh.positions.count == mesh.textureCoordinates.count)
        #expect(mesh.indices.count == 20 * avatar.curves.count * 8 * 6)
        #expect(mesh.indices.allSatisfy { $0 < mesh.positions.count })
        for (point, normal) in zip(mesh.positions, mesh.normals) {
            #expect(point.x.isFinite && point.y.isFinite && point.z.isFinite)
            #expect(abs(point.x) < 1 && abs(point.y) < 1 && abs(point.z) <= BlobVolume.depth)
            let length = sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z)
            #expect(abs(length - 1) < 0.0001)
        }
        #expect(mesh.textureCoordinates.allSatisfy { (0...1).contains($0.u) && (0...1).contains($0.v) })
    }
}

@Test func blobVolumeEquatorPreservesTheAvatarOutline() {
    let avatar = BlobAvatar(seed: [1, 0, 135, 29, 130, 216, 96, 190, 118, 230, 102, 32])
    let mesh = BlobVolume(avatar: avatar)
    let equator = 10 * avatar.curves.count * 8
    let first = mesh.positions[equator]
    #expect(abs(Double(first.x) - 2 * (avatar.start.x - 0.5)) < 0.0001)
    #expect(abs(Double(first.y) - 2 * (0.5 - avatar.start.y)) < 0.0001)
    #expect(abs(first.z) < 0.0001)
    #expect(mesh.positions.first?.z == BlobVolume.depth)
    #expect(mesh.positions.last?.z == -BlobVolume.depth)
}
