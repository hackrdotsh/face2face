import RealityKit
import simd

@available(iOS 18.0, *)
@MainActor
enum Town3DGeometry {
    static func lathe(_ profile: [SIMD2<Float>], segments: Int = 64) throws -> MeshResource {
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for band in 0..<(profile.count - 1) {
            let start = profile[band]
            let end = profile[band + 1]
            let slope = simd_normalize(SIMD2(end.y - start.y, start.x - end.x))
            let offset = UInt32(vertices.count)
            for step in 0...segments {
                let angle = Float(step) / Float(segments) * 2 * .pi
                for point in [start, end] {
                    vertices.append([point.x * cos(angle), point.y, point.x * sin(angle)])
                    normals.append([slope.x * cos(angle), slope.y, slope.x * sin(angle)])
                }
                if step < segments {
                    let i = offset + UInt32(step * 2)
                    indices += [i, i + 1, i + 2, i + 1, i + 3, i + 2]
                }
            }
        }
        return try mesh("turned-stone", vertices: vertices, normals: normals, indices: indices)
    }

    static func canopyStripe(width: Float) throws -> MeshResource {
        let profile: [SIMD2<Float>] = [
            [-0.9, 2.08], [-0.65, 2.07], [-0.35, 2.01], [-0.05, 1.9], [0.25, 1.77], [0.52, 1.7],
        ]
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for (index, point) in profile.enumerated() {
            let before = profile[max(0, index - 1)]
            let after = profile[min(profile.count - 1, index + 1)]
            let normal = simd_normalize(SIMD3<Float>(0, after.x - before.x, before.y - after.y))
            vertices += [[-width / 2, point.y, point.x], [width / 2, point.y, point.x]]
            normals += [normal, normal]
            if index < profile.count - 1 {
                let i = UInt32(index * 2)
                indices += [i, i + 2, i + 1, i + 1, i + 2, i + 3]
            }
        }
        return try mesh("canvas-stripe", vertices: vertices, normals: normals, indices: indices)
    }

    static func scallop(width: Float) throws -> MeshResource {
        var outline: [SIMD2<Float>] = [[-width / 2, 0], [width / 2, 0]]
        for step in 0...12 {
            let angle = Float(step) / 12 * .pi
            outline.append([cos(angle) * width / 2, -0.09 - sin(angle) * 0.1])
        }
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        let faces: [(Float, SIMD3<Float>)] = [(0.015, [0, 0, 1]), (-0.015, [0, 0, -1])]
        for (depth, normal) in faces {
            let offset = UInt32(vertices.count)
            vertices += outline.map { [$0.x, $0.y, depth] }
            normals += Array(repeating: normal, count: outline.count)
            for index in 1..<(outline.count - 1) {
                let triangle = [offset, offset + UInt32(index + 1), offset + UInt32(index)]
                indices += depth > 0 ? triangle : Array(triangle.reversed())
            }
        }
        return try mesh("canvas-scallop", vertices: vertices, normals: normals, indices: indices)
    }

    static func waterArc(angle: Float) throws -> MeshResource {
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        let radial = SIMD3<Float>(cos(angle), 0, sin(angle))
        let sideways = SIMD3<Float>(-sin(angle), 0, cos(angle))
        for step in 0...24 {
            let t = Float(step) / 24
            let center = radial * (0.04 + 0.61 * t) + SIMD3<Float>(0, 0.77 + 0.42 * t - t * t, 0)
            let tangent = simd_normalize(radial * 0.61 + SIMD3<Float>(0, 0.42 - 2 * t, 0))
            let normalUp = simd_normalize(simd_cross(tangent, sideways))
            for side in 0...8 {
                let turn = Float(side) / 8 * 2 * .pi
                let normal = normalUp * cos(turn) + sideways * sin(turn)
                vertices.append(center + normal * (0.016 - t * 0.005))
                normals.append(normal)
                if step < 24, side < 8 {
                    let i = UInt32(step * 9 + side)
                    indices += [i, i + 9, i + 1, i + 1, i + 9, i + 10]
                }
            }
        }
        return try mesh("fountain-stream", vertices: vertices, normals: normals, indices: indices)
    }

    private static func mesh(
        _ name: String, vertices: [SIMD3<Float>], normals: [SIMD3<Float>], indices: [UInt32]
    ) throws -> MeshResource {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffers.Positions(vertices)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }
}
