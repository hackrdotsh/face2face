import Foundation

/// A full conifer bough with a pointed crown, scalloped skirt, and overlapping leaf clusters.
public struct PineCrown: Sendable {
    public let positions: [SIMD3<Float>]
    public let normals: [SIMD3<Float>]
    public let indices: [UInt32]
    /// 0: foliage, 1: upper tips, 2: underside.
    public let faceMaterials: [UInt32]

    public init(branches: Int = 9) {
        let lobes = min(12, max(6, branches))
        let count = lobes * 6
        let profile: [(radius: Float, height: Float)] = [
            (0, 1), (0.12, 0.84), (0.32, 0.58), (0.58, 0.34),
            (0.82, 0.17), (1, 0.1), (0.98, 0.05), (0.48, 0.08),
        ]
        var mesh = Builder()
        var rings: [[Vertex]] = []
        for (ring, point) in profile.enumerated() {
            let before = profile[max(0, ring - 1)]
            let after = profile[min(profile.count - 1, ring + 1)]
            let slope = SIMD2(after.radius - before.radius, after.height - before.height)
            rings.append(
                (0..<count).map { index in
                    let angle = Float(index) / Float(count) * 2 * .pi
                    let scallop = 1 + (1 - point.height) * 0.045 * cos(angle * Float(lobes))
                    return Vertex(
                        point: [
                            cos(angle) * point.radius * scallop, point.height,
                            sin(angle) * point.radius * scallop,
                        ],
                        normal: Self.unit([-slope.y * cos(angle), slope.x, -slope.y * sin(angle)]))
                })
        }
        for ring in 0..<(rings.count - 1) {
            let material: UInt32 = ring < 1 ? 1 : (ring >= 5 ? 2 : 0)
            for index in 0..<count {
                let next = (index + 1) % count
                mesh.triangle(
                    rings[ring][index], rings[ring][next], rings[ring + 1][index], material: material)
                mesh.triangle(
                    rings[ring][next], rings[ring + 1][next], rings[ring + 1][index], material: material)
            }
        }
        for ring in 0..<2 {
            for index in 0..<lobes {
                let angle = (Float(index) + Float(ring) * 0.5) / Float(lobes) * 2 * .pi
                mesh.leafCluster(
                    angle: angle, radius: ring == 0 ? 0.88 : 0.57, height: ring == 0 ? 0.14 : 0.32)
            }
        }
        positions = mesh.positions
        normals = mesh.normals
        indices = mesh.indices
        faceMaterials = mesh.materials
    }

    private struct Vertex {
        let point: SIMD3<Float>
        let normal: SIMD3<Float>
    }

    private struct Builder {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var materials: [UInt32] = []

        mutating func triangle(_ a: Vertex, _ b: Vertex, _ c: Vertex, material: UInt32) {
            let u = b.point - a.point
            let v = c.point - a.point
            let cross = SIMD3<Float>(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x)
            guard cross.x * cross.x + cross.y * cross.y + cross.z * cross.z > 0.0000001 else { return }
            let start = UInt32(positions.count)
            positions += [a.point, b.point, c.point]
            normals += [a.normal, b.normal, c.normal]
            indices += [start, start + 1, start + 2]
            materials.append(material)
        }

        mutating func leafCluster(angle: Float, radius: Float, height: Float) {
            let radial = SIMD3<Float>(cos(angle), 0, sin(angle))
            let tangent = SIMD3<Float>(-sin(angle), 0, cos(angle))
            let center = radial * radius + SIMD3<Float>(0, height, 0)
            func vertex(_ row: Int, _ column: Int) -> Vertex {
                let latitude = Float(row) / 4 * .pi
                let longitude = Float(column) / 8 * 2 * .pi
                let unit = SIMD3<Float>(
                    sin(latitude) * cos(longitude), cos(latitude), sin(latitude) * sin(longitude))
                return Vertex(
                    point: center + tangent * unit.x * 0.16 + SIMD3<Float>(0, unit.y * 0.09, 0) + radial
                        * unit.z * 0.14,
                    normal: PineCrown.unit(
                        tangent * unit.x / 0.16 + SIMD3<Float>(0, unit.y / 0.09, 0) + radial * unit.z / 0.14))
            }
            for row in 0..<4 {
                for column in 0..<8 {
                    let a = vertex(row, column)
                    let b = vertex(row, column + 1)
                    let c = vertex(row + 1, column)
                    let d = vertex(row + 1, column + 1)
                    triangle(a, b, c, material: 0)
                    triangle(b, d, c, material: 0)
                }
            }
        }
    }

    private static func unit(_ vector: SIMD3<Float>) -> SIMD3<Float> {
        vector / max(sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z), 0.00001)
    }
}
