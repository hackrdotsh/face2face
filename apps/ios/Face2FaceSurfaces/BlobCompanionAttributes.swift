import ActivityKit
import Face2FaceCore
import Foundation

/// Only decorative artwork and a deadline cross the app/extension boundary.
/// No account IDs, credentials, discovery observations, photos or location.
struct BlobCompanionAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        let endsAt: Date
        var signal: BlobSignal = .off
        var pulse: Int = 0

        init(endsAt: Date, signal: BlobSignal = .off, pulse: Int = 0) {
            self.endsAt = endsAt
            self.signal = signal
            self.pulse = pulse
        }

        private enum CodingKeys: String, CodingKey { case endsAt, signal, pulse }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            endsAt = try values.decode(Date.self, forKey: .endsAt)
            signal = try values.decodeIfPresent(BlobSignal.self, forKey: .signal) ?? .off
            pulse = try values.decodeIfPresent(Int.self, forKey: .pulse) ?? 0
        }
    }

    let seed: String
}

enum BlobSurface {
    static let townURL = URL(string: "face2face://town")!
    static let connectionsURL = URL(string: "face2face://connections")!
    static let notificationsURL = URL(string: "face2face://notifications")!
    static let previewSeed = "AAAAAAAAAAAAAAAAAAAAAA"
    static let sessionDuration: TimeInterval = 60 * 60
    static let signalPreferenceKey = "islandSignalEnabled"

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

struct BlobSignal: Codable, Hashable, Sendable {
    enum Mode: String, Codable { case off, waiting, paused, receiving }
    var mode: Mode
    var sample = AnonymousSignalMeter.Sample()

    static let off = Self(mode: .off)

    var title: String {
        switch mode {
        case .off: "Just a little company"
        case .waiting: "Listening for a signal"
        case .paused: "Discovery paused"
        case .receiving:
            switch sample.levels.last ?? 0 {
            case 4: "Stronger Bluetooth signal"
            case 3: "Moderate Bluetooth signal"
            default: "Weaker Bluetooth signal"
            }
        }
    }

    var staleDate: Date? {
        sample.observedAt?.addingTimeInterval(AnonymousSignalMeter.freshness)
    }
}
