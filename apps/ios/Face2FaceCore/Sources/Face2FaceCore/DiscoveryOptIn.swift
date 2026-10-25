import Foundation

/// A preference, not a credential. It can only resume discovery for the same account and API.
public struct DiscoveryOptIn: Codable, Sendable, Equatable {
    public let id: UUID
    public let accountID: String
    public let server: String

    public init(accountID: String, server: URL) {
        id = UUID()
        self.accountID = accountID
        self.server = server.absoluteString
    }

    public func matches(accountID: String, server: URL) -> Bool {
        self.accountID == accountID && self.server == server.absoluteString
    }
}

/// Memory-only authorization. Stopping discards it; it never extends a token's lifetime.
public struct DiscoveryConsent: Sendable, Equatable {
    public let id: UUID
    private let window: PocketTestWindow?

    public init(untilStopped id: UUID) {
        self.id = id
        window = nil
    }

    public init(window: PocketTestWindow) {
        id = window.id
        self.window = window
    }

    public func remaining(at date: Date, uptime: TimeInterval) -> TimeInterval {
        window?.remaining(at: date, uptime: uptime) ?? .infinity
    }
}
