import Foundation

/// Memory-only validity for one server locator, measured from request start on two clocks.
public struct DiscoveryTokenValidity: Sendable, Equatable {
    public let token: DiscoveryToken
    private let requestStartedAt: Date
    private let requestStartedUptime: TimeInterval
    private let lifetime: TimeInterval
    private let sessionLifetime: TimeInterval

    public init(lease: DiscoveryLease, requestStartedAt: Date, requestStartedUptime: TimeInterval) throws {
        token = try lease.validatedToken()
        guard requestStartedUptime.isFinite, requestStartedUptime >= 0,
            requestStartedAt.timeIntervalSinceReferenceDate.isFinite
        else { throw APIError.invalidResponse }
        self.requestStartedAt = requestStartedAt
        self.requestStartedUptime = requestStartedUptime
        lifetime = max(0, (Double(lease.expiresAt) - Double(lease.serverTime)) / 1_000 - 10)
        sessionLifetime = max(0, (Double(lease.sessionExpiresAt) - Double(lease.serverTime)) / 1_000 - 10)
    }

    public func remaining(at date: Date = Date(), uptime: TimeInterval) -> TimeInterval {
        remaining(lifetime: lifetime, at: date, uptime: uptime)
    }

    public func sessionRemaining(at date: Date = Date(), uptime: TimeInterval) -> TimeInterval {
        remaining(lifetime: sessionLifetime, at: date, uptime: uptime)
    }

    private func remaining(lifetime: TimeInterval, at date: Date, uptime: TimeInterval) -> TimeInterval {
        let wallAge = date.timeIntervalSince(requestStartedAt)
        let uptimeAge = uptime - requestStartedUptime
        guard wallAge.isFinite, uptimeAge.isFinite, uptime.isFinite, wallAge >= 0, uptimeAge >= 0 else {
            return 0
        }
        return max(0, lifetime - max(wallAge, uptimeAge))
    }
}

/// Not Codable: an authenticated walk is never restored from a plain preferences checkpoint.
public struct AuthenticatedRadioPermit: Sendable, Equatable {
    public let validity: DiscoveryTokenValidity
    public let consent: DiscoveryConsent
    public var token: DiscoveryToken { validity.token }

    public init(validity: DiscoveryTokenValidity, consent: PocketTestWindow) {
        self.init(validity: validity, consent: DiscoveryConsent(window: consent))
    }

    public init(validity: DiscoveryTokenValidity, consent: DiscoveryConsent) {
        self.validity = validity
        self.consent = consent
    }

    public func remaining(at date: Date = Date(), uptime: TimeInterval) -> TimeInterval {
        min(validity.remaining(at: date, uptime: uptime), consent.remaining(at: date, uptime: uptime))
    }

    /// Rotation replaces the locator, never the user's consent.
    public func rotating(to validity: DiscoveryTokenValidity) -> Self {
        Self(validity: validity, consent: consent)
    }
}

/// Event-driven background work only. No timer schedules another networking pass.
public struct BackgroundUploadPolicy: Sendable {
    public static let budgetSeconds: TimeInterval = 6
    public static let maximumReports = 3
    public static let cooldown: TimeInterval = 10
    private var lastAttemptUptime: TimeInterval?

    public init() {}

    public mutating func begin(at uptime: TimeInterval) -> Bool {
        guard uptime.isFinite, uptime >= 0 else { return false }
        if let lastAttemptUptime, uptime - lastAttemptUptime < Self.cooldown { return false }
        lastAttemptUptime = uptime
        return true
    }
}
