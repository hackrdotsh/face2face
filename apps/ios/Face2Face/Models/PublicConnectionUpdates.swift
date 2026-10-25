import Observation

/// An opaque refresh hint, never a cached profile or evidence of online/physical presence.
@MainActor
@Observable
final class PublicConnectionUpdates {
    static let shared = PublicConnectionUpdates()
    private(set) var latestID: String?
    private(set) var revision = 0
    func confirmedPublic(_ id: String) {
        latestID = id
        revision += 1
    }
}
