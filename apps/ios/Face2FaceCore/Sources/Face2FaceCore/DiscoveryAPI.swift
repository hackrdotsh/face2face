import Foundation

/// Opaque discovery locators are separate from the signed bearer credential in Keychain.
public struct DiscoveryLease: Codable, Sendable, Equatable {
    public let sessionId: String
    public let token: String
    public let expiresAt: Int64
    public let sessionExpiresAt: Int64
    public let serverTime: Int64

    public func validatedToken() throws -> DiscoveryToken {
        guard UUID(uuidString: sessionId) != nil,
            serverTime >= 0, serverTime <= 8_639_999_998_200_000,
            expiresAt > serverTime, expiresAt <= sessionExpiresAt,
            expiresAt - serverTime <= 300_000,
            sessionExpiresAt - serverTime <= 1_800_000
        else { throw APIError.invalidResponse }
        do { return try DiscoveryToken(identifier: token) } catch { throw APIError.invalidResponse }
    }

    /// Use server-relative lifetimes, with a request-latency safety margin, not device clock agreement.
    public func tokenDeadline(requestStartedAt: Date) -> Date {
        requestStartedAt.addingTimeInterval(max(0, (Double(expiresAt) - Double(serverTime)) / 1_000 - 10))
    }

    public func sessionDeadline(requestStartedAt: Date) -> Date {
        requestStartedAt.addingTimeInterval(
            max(0, (Double(sessionExpiresAt) - Double(serverTime)) / 1_000 - 10))
    }
}

/// A receipt never names the peer. `matchId` is opaque, shared by both phones, and stable for one pair of leases.
public struct ObservationReceipt: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable { case pending, recorded }
    public let status: Status
    public let matchId: String?

    public init(status: Status, matchId: String? = nil) {
        self.status = status
        self.matchId = matchId
    }
}

public struct PendingDiscoveryObservation: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let peerToken: DiscoveryToken
    public private(set) var attempts = 0
    public private(set) var nextAttemptAt: Date

    init(peerToken: DiscoveryToken, at date: Date) {
        id = UUID()
        self.peerToken = peerToken
        nextAttemptAt = date
    }

    mutating func failed(at date: Date, rateLimited: Bool) {
        attempts += 1
        nextAttemptAt = date.addingTimeInterval(rateLimited ? 60 : min(60, pow(2, Double(attempts))))
    }
}

/// Memory-only, scoped to one discovery session. Retries keep the original observation ID.
public struct DiscoveryOutbox: Sendable {
    public static let limit = 100
    public private(set) var pending: [PendingDiscoveryObservation] = []
    private var seen: Set<DiscoveryToken> = []

    public init() {}

    @discardableResult
    public mutating func enqueue(_ token: DiscoveryToken, at date: Date = Date()) -> Bool {
        guard !seen.contains(token), seen.count < Self.limit else { return false }
        seen.insert(token)
        pending.append(PendingDiscoveryObservation(peerToken: token, at: date))
        return true
    }

    public func nextReady(at date: Date = Date()) -> PendingDiscoveryObservation? {
        pending.first { $0.nextAttemptAt <= date }
    }

    public mutating func acknowledge(_ id: UUID) {
        pending.removeAll { $0.id == id }
    }

    /// Five attempts maximum, including rate-limited attempts. Returns false when discarded.
    @discardableResult
    public mutating func failed(_ id: UUID, at date: Date = Date(), rateLimited: Bool = false) -> Bool {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return false }
        pending[index].failed(at: date, rateLimited: rateLimited)
        if pending[index].attempts >= 5 {
            pending.remove(at: index)
            return false
        }
        return true
    }
}
