import SwiftUI

struct CampfireSettingsSection: View {
    let session: SessionModel
    @AppStorage(CampfireStore.preferenceKey) private var enabled = false
    @State private var model = CampfireWidgetModel.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Section {
            let snapshot = CampfireStore.read()
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active))
            { timeline in
                CampfireScene(
                    ownSeed: seed, guests: Array(snapshot.guests.prefix(6)),
                    time: reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                )
                .frame(height: 164)
                .background(
                    Color(red: 0.035, green: 0.095, blue: 0.12), in: RoundedRectangle(cornerRadius: 24))
            }
            .accessibilityLabel("Campfire widget artwork preview. Not live attendance.")
            Toggle("Friends in campfire widget", isOn: $enabled)
                .disabled(!isSignedIn || session.isTownPreview)
                .accessibilityIdentifier("campfireWidgetToggle")
            Text(model.message).font(.footnote).foregroundStyle(.secondary)
            if enabled {
                Button("Refresh widget friends") {
                    Task { await model.refresh(session: session, force: true) }
                }
                .disabled(model.isRefreshing)
                .accessibilityIdentifier("refreshCampfireWidget")
            }
        } header: {
            Text("Around the campfire")
        } footer: {
            Text(
                "Opt in to show accepted connections on your widgets. Only mutually public friends get names and their own blobs; private friends stay anonymous. The campfire is symbolic, not who's nearby or online. Snapshots expire after 15 minutes without a refresh. Add face2face from the widget gallery; use the arrows to see every friend."
            )
        }
    }

    private var isSignedIn: Bool {
        if case .ready = session.phase { return true }
        return false
    }

    private var seed: String {
        if case .ready(let account) = session.phase { return account.user.avatar.seed }
        return BlobSurface.previewSeed
    }
}
