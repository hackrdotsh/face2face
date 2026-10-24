import Foundation

/// Separates this walk's new server records from previously loaded encounter history.
/// Server timestamps avoid assuming the phone's clock agrees with the API.
public struct WalkEncounterTracker: Sendable {
    private let baseline: [String: Int64]
    private let serverStartedAt: Int64
    public private(set) var encounters: [ServerEncounter] = []

    public init(baseline: [ServerEncounter], serverStartedAt: Int64) {
        self.baseline = Dictionary(
            baseline.map { ($0.id, $0.lastSeenAt) },
            uniquingKeysWith: max)
        self.serverStartedAt = serverStartedAt
    }

    /// Each account pair is revealed once per walk, including a genuinely updated existing pair.
    /// Poll retries, reordering, and unchanged historical receipts never create another reveal.
    @discardableResult
    public mutating func ingest(_ history: [ServerEncounter]) -> [ServerEncounter] {
        guard serverStartedAt >= 0 else { return [] }
        var additions: [ServerEncounter] = []
        for encounter in history {
            guard encounter.lastSeenAt >= serverStartedAt,
                encounter.lastSeenAt > (baseline[encounter.id] ?? -1)
            else { continue }
            if let index = encounters.firstIndex(where: { $0.id == encounter.id }) {
                if encounter.lastSeenAt >= encounters[index].lastSeenAt {
                    encounters[index] = encounter
                }
            } else if encounters.count < 50 {
                encounters.append(encounter)
                additions.append(encounter)
            }
        }
        encounters.sort {
            $0.lastSeenAt == $1.lastSeenAt ? $0.id < $1.id : $0.lastSeenAt > $1.lastSeenAt
        }
        return additions
    }
}
