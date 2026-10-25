import Foundation

/// Decorative personality, never live presence. Kept separate from the cross-client idle fixtures.
public struct BlobPlayMotion: Sendable {
    public struct Pose: Sendable {
        public let xScale: Double
        public let yScale: Double
        public let lift: Double
        public let tilt: Double
    }

    private let phase: Double

    public init(seed: String) {
        phase = BlobIdleMotion(seed: seed)?.phase ?? 0
    }

    public func pose(at time: TimeInterval, reducedMotion: Bool = false) -> Pose {
        guard !reducedMotion, time.isFinite else {
            return Pose(xScale: 1, yScale: 1, lift: 0, tilt: 0)
        }
        let cycle = time * 1.8 + phase * 2 * .pi
        let hop = pow(max(0, sin(cycle)), 3)
        let squash = sin(cycle * 2) * 0.055
        return Pose(xScale: 1 + squash, yScale: 1 - squash, lift: hop * 0.095, tilt: sin(cycle * 0.55) * 7)
    }
}
