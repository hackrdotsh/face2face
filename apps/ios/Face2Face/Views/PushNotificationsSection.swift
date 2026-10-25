import SwiftUI

struct PushNotificationsSection: View {
    let session: SessionModel
    @State private var push = PushNotifications.shared
    @State private var retrying = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Section("Notifications") {
            LabeledContent("Permission", value: push.permission)
            LabeledContent("Apple registration", value: push.appleRegistration)
            LabeledContent("Server registration", value: push.serverRegistration)
            Text(push.serverSetup).font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("pushServerSetup")
            if let error = push.setupError {
                Text(error).font(.footnote).foregroundStyle(MeadowPalette.errorInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pushSetupError")
            }
            Text(
                "App: \(Bundle.main.bundleIdentifier ?? "Unknown") · \(PushNotifications.environment.rawValue)"
            )
            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Button(retrying ? "Checking notification setup…" : "Retry notification setup") {
                Task {
                    guard case .ready(let account) = session.phase else { return }
                    retrying = true
                    defer { retrying = false }
                    await push.start(for: account, session: session, force: true)
                    await push.refreshStatus(session: session)
                }
            }
            .disabled(retrying || session.isTownPreview || !signedIn)
            .accessibilityIdentifier("pushRetrySetup")
            Button("Open iOS notification settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Text(
                "Messages alert you outside the conversation you are reading. Push also requires a push-enabled signing team and matching server APNs configuration. No device tokens are shown here."
            )
            .font(.footnote).foregroundStyle(.secondary)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await push.refreshStatus(session: session)
        }
    }

    private var signedIn: Bool {
        if case .ready = session.phase { return true }
        return false
    }
}
