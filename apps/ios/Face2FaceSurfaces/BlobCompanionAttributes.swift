import ActivityKit
import Foundation

/// Only decorative artwork and a deadline cross the app/extension boundary.
/// No account IDs, credentials, discovery observations, photos or location.
struct BlobCompanionAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let endsAt: Date
    }

    let seed: String
}

enum BlobSurface {
    static let townURL = URL(string: "face2face://town")!
    static let previewSeed = "AAAAAAAAAAAAAAAAAAAAAA"
    static let sessionDuration: TimeInterval = 60 * 60

    /// A stable decorative visitor for the UTC day, unrelated to any account.
    static func dailySeed(at date: Date) -> String {
        let day = Int64(floor(date.timeIntervalSince1970 / 86_400))
        let bytes = (0..<16).map { index in
            UInt8(truncatingIfNeeded: (day &* 73) &+ Int64(index * 37))
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
