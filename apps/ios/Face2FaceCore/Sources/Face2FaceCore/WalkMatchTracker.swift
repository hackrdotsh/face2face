import Foundation

/// Counts the matches recorded during one walk. Each walk starts a new lease, so every
/// match ID it sees is new. Retries and rotated tokens repeat a match ID and count once.
public struct WalkMatchTracker: Sendable {
    public static let limit = 50
    public private(set) var matchIds: [String] = []

    public init() {}

    /// Returns true when the receipt is a match this walk had not seen.
    @discardableResult
    public mutating func ingest(_ receipt: ObservationReceipt) -> Bool {
        guard receipt.status == .recorded, let matchId = receipt.matchId,
            !matchIds.contains(matchId), matchIds.count < Self.limit
        else { return false }
        matchIds.append(matchId)
        return true
    }
}
