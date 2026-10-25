import Foundation

/// A short-lived, aggregate radio visualization. Not a distance estimate or a verified peer.
/// Never associates a sample with a device, token, account, or encounter.
public struct AnonymousSignalMeter: Sendable {
    public struct Sample: Codable, Hashable, Sendable {
        public let levels: [Int]
        public let observedAt: Date?

        public init(levels: [Int] = [], observedAt: Date? = nil) {
            self.levels = Array(levels.suffix(9)).map { min(4, max(0, $0)) }
            self.observedAt = observedAt
        }
    }

    public static let freshness: TimeInterval = 12
    private var smoothed: Double?
    private var lastPublished: TimeInterval?
    private var lastSeen: TimeInterval?
    private var levels: [Int] = []

    public init() {}

    public mutating func observe(rssi: Int, uptime: TimeInterval, date: Date) -> Sample? {
        // 127 means unavailable. Reject implausible values, not merely weak valid readings.
        guard (-127...20).contains(rssi), uptime.isFinite, uptime >= 0 else { return nil }
        if let lastSeen, uptime < lastSeen || uptime - lastSeen >= Self.freshness {
            self = Self()
        }
        lastSeen = uptime
        smoothed = smoothed.map { $0 * 0.65 + Double(rssi) * 0.35 } ?? Double(rssi)
        guard lastPublished.map({ uptime - $0 >= 3 }) ?? true else { return nil }
        lastPublished = uptime
        let value = smoothed ?? -100
        let level = value >= -60 ? 4 : value >= -73 ? 3 : value >= -86 ? 2 : 1
        levels = Array((levels + [level]).suffix(9))
        return Sample(levels: levels, observedAt: date)
    }

    public mutating func expire(uptime: TimeInterval) -> Sample? {
        guard let lastSeen, uptime.isFinite,
            uptime < lastSeen || uptime - lastSeen >= Self.freshness
        else { return nil }
        self = Self()
        return Sample()
    }
}
