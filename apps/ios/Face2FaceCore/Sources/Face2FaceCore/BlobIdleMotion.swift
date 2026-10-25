import Foundation

/// A blob's idle loop: its outline breathes, and its eyes blink and glance side to side. The web
/// client runs the same timing.
public struct BlobIdleMotion: Equatable, Sendable {
    public struct Pose: Equatable, Sendable {
        /// Where the outline is in its breathing wave, in radians. Pass it to `BlobAvatar.outline`.
        public let breath: Double
        /// Horizontal eye shift in unit-square coordinates.
        public let gaze: Double
        /// Eye height, where 1 is fully open.
        public let eyeOpenness: Double
    }

    private struct Keyframe {
        let offset: Double
        let value: Double
    }

    public static let breathePeriod = 4.0
    public static let blinkPeriod = 5.0
    public static let lookPeriod = 8.0

    private static let closedEye = 0.1
    private static let glance = 0.025

    private static let blink = [
        Keyframe(offset: 0, value: 1), Keyframe(offset: 0.92, value: 1),
        Keyframe(offset: 0.96, value: closedEye),
        Keyframe(offset: 1, value: 1),
    ]
    private static let look = [
        Keyframe(offset: 0, value: 0), Keyframe(offset: 0.3, value: 0),
        Keyframe(offset: 0.38, value: -glance),
        Keyframe(offset: 0.58, value: -glance), Keyframe(offset: 0.66, value: glance),
        Keyframe(offset: 0.85, value: glance), Keyframe(offset: 0.93, value: 0),
        Keyframe(offset: 1, value: 0),
    ]

    /// Where the loop starts, from 0 to 1.
    public let phase: Double

    /// Returns nil when the seed is not base64url.
    public init?(seed: String) {
        guard let bytes = Data(base64URLEncoded: seed) else { return nil }
        self.init(seed: [UInt8](bytes))
    }

    public init(seed: [UInt8]) {
        phase = seed.count > 15 ? Double(seed[15]) / 255 : 0
    }

    public func pose(at time: TimeInterval) -> Pose {
        Pose(
            breath: 2 * Double.pi * progress(time, Self.breathePeriod),
            gaze: Self.value(of: Self.look, at: progress(time, Self.lookPeriod)),
            eyeOpenness: Self.value(of: Self.blink, at: progress(time, Self.blinkPeriod)))
    }

    private func progress(_ time: TimeInterval, _ period: Double) -> Double {
        let cycles = time / period + phase
        return cycles - cycles.rounded(.down)
    }

    /// Eases in and out between neighboring keyframes, like CSS `ease-in-out`.
    private static func value(of keyframes: [Keyframe], at progress: Double) -> Double {
        guard let next = keyframes.firstIndex(where: { $0.offset > progress }), next > 0 else {
            return keyframes.last?.value ?? 0
        }
        let from = keyframes[next - 1]
        let to = keyframes[next]
        let linear = (progress - from.offset) / (to.offset - from.offset)
        let eased = linear * linear * (3 - 2 * linear)
        return from.value + (to.value - from.value) * eased
    }
}
