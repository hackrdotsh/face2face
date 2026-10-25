import ActivityKit
import AppIntents
import Foundation

/// A user-driven, short Island animation; never starts an activity or turns on discovery.
struct WaveBlobIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Say hello to your blob"
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        await Self.wave()
        return .result()
    }

    private nonisolated static func wave() async {
        for activity in ActivityKit.Activity<BlobCompanionAttributes>.activities {
            guard activity.content.state.endsAt > Date() else { continue }
            var state = activity.content.state
            state.pulse += 1
            await activity.update(ActivityContent(state: state, staleDate: activity.content.staleDate))
        }
    }
}
