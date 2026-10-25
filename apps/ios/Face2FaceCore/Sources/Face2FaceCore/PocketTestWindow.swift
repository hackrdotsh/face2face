import Foundation

/// Non-secret consent metadata only. Never contains radio tokens, peers, or auth credentials.
public struct PocketTestWindow: Codable, Sendable, Equatable, Identifiable {
    public static let duration: TimeInterval = 300
    public let id: UUID
    public let startedAt: Date
    public let startedUptime: TimeInterval

    public init(at date: Date = Date(), uptime: TimeInterval) {
        id = UUID()
        startedAt = date
        startedUptime = uptime
    }

    /// Check on every radio callback: a suspended app cannot rely on an expiry timer firing.
    /// Both clocks must be valid. Moving the wall clock backwards cannot extend the test.
    public func remaining(at date: Date = Date(), uptime: TimeInterval) -> TimeInterval {
        let wallAge = date.timeIntervalSince(startedAt)
        let uptimeAge = uptime - startedUptime
        guard startedUptime.isFinite, startedUptime >= 0,
            uptime.isFinite, wallAge.isFinite, uptimeAge.isFinite,
            wallAge >= 0, uptimeAge >= 0
        else { return 0 }
        return max(0, Self.duration - max(wallAge, uptimeAge))
    }
}
