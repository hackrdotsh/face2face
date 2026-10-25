import Foundation

/// Decorative crossings follow the original forest's four-second first hello and 16-second spacing.
public struct ForestPasserPose: Sendable {
    public let z: Float
    public let greetingProgress: Double?
    public var greetingStrength: Float {
        greetingProgress.map { Float(sin($0 * .pi)) } ?? 0
    }

    public static func at(time: Double, slot: Int) -> Self {
        guard time.isFinite, time >= 0, (0...1).contains(slot) else {
            return Self(z: -100, greetingProgress: nil)
        }
        let crossing = 4 + Double(slot) * 16
        let wrapped = (time - crossing + 16).truncatingRemainder(dividingBy: 32)
        let age = (wrapped + 32).truncatingRemainder(dividingBy: 32) - 16
        let progress = (age + 0.9) / 1.8
        return Self(z: 4 + Float(age) * 1.5, greetingProgress: (0...1).contains(progress) ? progress : nil)
    }
}
