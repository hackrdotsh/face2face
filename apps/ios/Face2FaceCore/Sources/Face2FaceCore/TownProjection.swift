import Foundation

/// The orthographic town camera and its 400 × 640 interaction map share one scale.
public enum TownProjection {
    public struct Point: Sendable, Equatable {
        public let x: Double
        public let y: Double
    }

    public static let unitsPerPoint = 1.0 / 40
    public static let sinePitch = 18 / sqrt(18.0 * 18 + 14 * 14)
    public static let cosinePitch = 14 / sqrt(18.0 * 18 + 14 * 14)

    public static func world(x: Double, y: Double, elevation: Double = 0) -> SIMD3<Float> {
        SIMD3(
            Float((x - 200) * unitsPerPoint), Float(elevation),
            Float(((y - 320) * unitsPerPoint + elevation * cosinePitch) / sinePitch))
    }

    public static func screen(_ position: SIMD3<Float>) -> Point {
        Point(
            x: 200 + Double(position.x) / unitsPerPoint,
            y: 320 + (Double(position.z) * sinePitch - Double(position.y) * cosinePitch) / unitsPerPoint)
    }
}
