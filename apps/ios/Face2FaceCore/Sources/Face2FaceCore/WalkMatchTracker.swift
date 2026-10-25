import Foundation

/// Counts the receipts with one status during one walk, matches by default. Each walk starts
/// a new lease, so every match ID it sees is new. Retries and rotated tokens repeat a match ID
/// and count once.
public struct WalkMatchTracker: Sendable {
    public static let limit = 50
    public private(set) var matchIds: [String] = []

    public let status: ObservationReceipt.Status

    public init(counting status: ObservationReceipt.Status = .recorded) {
        self.status = status
    }

    /// Returns true when the receipt is one this walk had not seen.
    @discardableResult
    public mutating func ingest(_ receipt: ObservationReceipt) -> Bool {
        guard receipt.status == status, let matchId = receipt.matchId,
            !matchIds.contains(matchId), matchIds.count < Self.limit
        else { return false }
        matchIds.append(matchId)
        return true
    }
}
