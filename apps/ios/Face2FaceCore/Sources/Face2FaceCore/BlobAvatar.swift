import Foundation

/// Blob avatar geometry from an avatar seed. The web client draws the same shape from the same
/// seed, and `docs/fixtures/blob-avatar.json` holds the expected output for both. Coordinates are
/// in a unit square.
public struct BlobAvatar: Equatable, Sendable {
    public struct Point: Codable, Equatable, Sendable {
        public let x: Double
        public let y: Double
    }

    /// One cubic Bézier segment, starting where the previous one ended.
    public struct Curve: Codable, Equatable, Sendable {
        public let control1: Point
        public let control2: Point
        public let end: Point
    }

    /// A vertical pill. `x` and `y` are its top-left corner.
    public struct Eye: Codable, Equatable, Sendable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double
    }

    public struct HSL: Codable, Equatable, Sendable {
        public let hue: Double
        public let saturation: Double
        public let lightness: Double

        /// Red, green, and blue from 0 to 1.
        public var rgb: (red: Double, green: Double, blue: Double) {
            let chroma = (1 - abs(2 * lightness - 1)) * saturation
            let sector = hue / 60
            let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
            let (red, green, blue): (Double, Double, Double) =
                switch sector {
                case ..<1: (chroma, second, 0)
                case ..<2: (second, chroma, 0)
                case ..<3: (0, chroma, second)
                case ..<4: (0, second, chroma)
                case ..<5: (second, 0, chroma)
                default: (chroma, 0, second)
                }
            let match = lightness - chroma / 2
            return (red + match, green + match, blue + match)
        }
    }

    public let start: Point
    public let curves: [Curve]
    public let eyes: [Eye]
    /// The top-left and bottom-right colors of a diagonal gradient.
    public let fill: [HSL]
    public let eyeColor: HSL

    private let angles: [Double]
    private let radii: [Double]

    private static let center = 0.5
    private static let minPointCount = 6
    private static let pointCountChoices = 3
    private static let minRadius = 0.34
    private static let radiusRange = 0.1
    private static let eyeWidth = 0.06
    private static let eyeHeight = 0.12
    private static let minEyeGap = 0.075
    private static let eyeGapRange = 0.03
    private static let minEyeTop = 0.39
    private static let eyeTopRange = 0.04
    private static let gazeRange = 0.04
    private static let gradientHueShift = 40
    private static let breatheAmplitude = 0.012

    /// Returns nil when the seed is not base64url.
    public init?(seed: String) {
        guard let bytes = Data(base64URLEncoded: seed) else { return nil }
        self.init(seed: [UInt8](bytes))
    }

    public init(seed: [UInt8]) {
        let rawByte = { (index: Int) -> Int in index < seed.count ? Int(seed[index]) : 0 }
        let byte = { (index: Int) -> Double in Double(rawByte(index)) / 255 }
        let pointCount = Self.minPointCount + rawByte(0) % Self.pointCountChoices
        let hue = (rawByte(1) * 256 + rawByte(2)) % 360
        let step = 2 * Double.pi / Double(pointCount)
        let rotation = byte(3) * step
        angles = (0..<pointCount).map { rotation + Double($0) * step - Double.pi / 2 }
        radii = (0..<pointCount).map { Self.minRadius + byte(4 + $0) * Self.radiusRange }
        let points = Self.points(angles: angles, radii: radii)
        let gap = Self.minEyeGap + byte(12) * Self.eyeGapRange
        let top = Self.minEyeTop + byte(13) * Self.eyeTopRange
        let gaze = (byte(14) - 0.5) * Self.gazeRange
        let eye = { (middle: Double) in
            Eye(x: middle - Self.eyeWidth / 2, y: top, width: Self.eyeWidth, height: Self.eyeHeight)
        }
        start = points[0]
        curves = Self.smoothClosedCurves(through: points)
        eyes = [eye(Self.center - gap + gaze), eye(Self.center + gap + gaze)]
        fill = [
            HSL(hue: Double(hue), saturation: 0.8, lightness: 0.82),
            HSL(hue: Double((hue + Self.gradientHueShift) % 360), saturation: 0.7, lightness: 0.68),
        ]
        eyeColor = HSL(hue: Double(hue), saturation: 0.4, lightness: 0.2)
    }

    /// The outline at a point in its breathing wave, in radians. A wave travels around the shape and
    /// pushes each point in or out.
    public func outline(breath: Double) -> (start: Point, curves: [Curve]) {
        let step = 2 * Double.pi / Double(radii.count)
        let swollen = radii.indices.map { index in
            radii[index] + Self.breatheAmplitude * sin(breath + 2 * Double(index) * step)
        }
        let points = Self.points(angles: angles, radii: swollen)
        return (points[0], Self.smoothClosedCurves(through: points))
    }

    private static func points(angles: [Double], radii: [Double]) -> [Point] {
        zip(angles, radii).map { angle, radius in
            Point(x: center + radius * cos(angle), y: center + radius * sin(angle))
        }
    }

    /// A closed Catmull-Rom spline through every point, as cubic Béziers.
    private static func smoothClosedCurves(through points: [Point]) -> [Curve] {
        let at = { (index: Int) in points[(index + points.count) % points.count] }
        return points.indices.map { index in
            let previous = at(index - 1)
            let current = at(index)
            let next = at(index + 1)
            let afterNext = at(index + 2)
            return Curve(
                control1: Point(
                    x: current.x + (next.x - previous.x) / 6, y: current.y + (next.y - previous.y) / 6),
                control2: Point(
                    x: next.x - (afterNext.x - current.x) / 6, y: next.y - (afterNext.y - current.y) / 6),
                end: next)
        }
    }
}
