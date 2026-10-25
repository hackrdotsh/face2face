import Foundation

/// When a plaza resident's status bubble shows. Each resident waits a different random-looking
/// gap, so bubbles rarely appear together. The same seed and time always give the same answer.
public enum TownStatusBubble {
    public static let shownDuration: TimeInterval = 4
    public static let gap: ClosedRange<TimeInterval> = 8...20
    static let fadeDuration: TimeInterval = 0.3

    /// 0 while hidden and 1 while fully shown, easing between them at each end.
    public static func visibility(seed: String, time: TimeInterval) -> Double {
        guard time.isFinite, time > 0 else { return 0 }
        var hash = stableHash(seed)
        var cycleStart: TimeInterval = 0
        while true {
            hash = nextRandom(hash)
            let shownAt = cycleStart + gap.lowerBound + (gap.upperBound - gap.lowerBound) * unitInterval(hash)
            let hiddenAt = shownAt + shownDuration
            if time < shownAt { return 0 }
            if time < hiddenAt {
                return min(1, (time - shownAt) / fadeDuration, (hiddenAt - time) / fadeDuration)
            }
            cycleStart = hiddenAt
        }
    }

    /// FNV-1a, because `String.hashValue` changes between launches.
    static func stableHash(_ text: String) -> UInt64 {
        text.utf8.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
    }

    /// SplitMix64.
    static func nextRandom(_ state: UInt64) -> UInt64 {
        var mixed = state &+ 0x9e37_79b9_7f4a_7c15
        mixed = (mixed ^ (mixed >> 30)) &* 0xbf58_476d_1ce4_e5b9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94d0_49bb_1331_11eb
        return mixed ^ (mixed >> 31)
    }

    static func unitInterval(_ value: UInt64) -> Double {
        Double(value >> 11) / Double(UInt64(1) << 53)
    }
}
