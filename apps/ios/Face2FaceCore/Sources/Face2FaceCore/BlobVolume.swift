import Foundation

/// A rounded volume with the same front silhouette as a seeded 2D avatar.
public struct BlobVolume: Sendable {
    public struct Vector: Sendable {
        public let x: Float
        public let y: Float
        public let z: Float
    }

    public struct UV: Sendable {
        public let u: Float
        public let v: Float
    }

    public let positions: [Vector]
    public let normals: [Vector]
    public let textureCoordinates: [UV]
    public let indices: [UInt32]
    public static let depth: Float = 0.62

    public init(avatar: BlobAvatar) {
        let rings = 20
        let samplesPerCurve = 8
        var outline: [(Float, Float)] = []
        var start = avatar.start
        for curve in avatar.curves {
            for sample in 0..<samplesPerCurve {
                let t = Double(sample) / Double(samplesPerCurve)
                let s = 1 - t
                let x =
                    s * s * s * start.x + 3 * s * s * t * curve.control1.x
                    + 3 * s * t * t * curve.control2.x + t * t * t * curve.end.x
                let y =
                    s * s * s * start.y + 3 * s * s * t * curve.control1.y
                    + 3 * s * t * t * curve.control2.y + t * t * t * curve.end.y
                outline.append((Float(2 * (x - 0.5)), Float(2 * (0.5 - y))))
            }
            start = curve.end
        }

        var positions: [Vector] = []
        var normals: [Vector] = []
        var uv: [UV] = []
        for ring in 0...rings {
            let angle = Float(ring) / Float(rings) * .pi
            for (x, y) in outline {
                let point = Vector(x: x * sin(angle), y: y * sin(angle), z: Self.depth * cos(angle))
                let nx = point.x
                let ny = point.y
                let nz = point.z / (Self.depth * Self.depth)
                let length = sqrt(nx * nx + ny * ny + nz * nz)
                positions.append(point)
                normals.append(Vector(x: nx / length, y: ny / length, z: nz / length))
                uv.append(UV(u: (point.x + 1) / 2, v: (1 - point.y) / 2))
            }
        }
        var indices: [UInt32] = []
        let count = outline.count
        for ring in 0..<rings {
            for index in 0..<count {
                let next = (index + 1) % count
                let a = UInt32(ring * count + index)
                let b = UInt32((ring + 1) * count + index)
                let c = UInt32(ring * count + next)
                let d = UInt32((ring + 1) * count + next)
                indices += [a, c, b, c, d, b]
            }
        }
        self.positions = positions
        self.normals = normals
        textureCoordinates = uv
        self.indices = indices
    }
}
