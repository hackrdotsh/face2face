import Foundation

/// A pointed canopy with flared branch tips and a recessed, darker underside.
public struct PineCrown: Sendable {
    public let positions: [SIMD3<Float>]
    public let normals: [SIMD3<Float>]
    public let indices: [UInt32]
    /// 0: foliage, 1: upper tips, 2: underside.
    public let faceMaterials: [UInt32]

    public init(branches: Int = 9) {
        let count = min(12, max(6, branches)) * 2
        let apex = SIMD3<Float>(0, 1, 0)
        var shoulder: [SIMD3<Float>] = []
        var rim: [SIMD3<Float>] = []
        var underside: [SIMD3<Float>] = []
        for index in 0..<count {
            let angle = Float(index) / Float(count) * 2 * .pi
            let tip = index.isMultiple(of: 2)
            shoulder.append([cos(angle) * 0.36, 0.59, sin(angle) * 0.36])
            let radius: Float = tip ? 1 : 0.78
            rim.append([cos(angle) * radius, tip ? 0.02 : 0.16, sin(angle) * radius])
            underside.append([cos(angle) * 0.48, 0.12, sin(angle) * 0.48])
        }
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var materials: [UInt32] = []
        func triangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, material: UInt32) {
            let u = b - a
            let v = c - a
            let cross = SIMD3<Float>(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x)
            let length = sqrt(cross.x * cross.x + cross.y * cross.y + cross.z * cross.z)
            let normal = cross / max(length, 0.00001)
            let start = UInt32(positions.count)
            positions += [a, b, c]
            normals += [normal, normal, normal]
            indices += [start, start + 1, start + 2]
            materials.append(material)
        }
        for index in 0..<count {
            let next = (index + 1) % count
            triangle(apex, shoulder[next], shoulder[index], material: 1)
            triangle(shoulder[index], rim[next], rim[index], material: 0)
            triangle(shoulder[index], shoulder[next], rim[next], material: 0)
            triangle(rim[index], underside[next], underside[index], material: 2)
            triangle(rim[index], rim[next], underside[next], material: 2)
            triangle(underside[index], underside[next], [0, 0.12, 0], material: 2)
        }
        self.positions = positions
        self.normals = normals
        self.indices = indices
        faceMaterials = materials
    }
}
