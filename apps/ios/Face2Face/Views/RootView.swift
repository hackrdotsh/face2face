import Face2FaceCore
import SwiftUI

/// Chooses the screen for the current session phase. Screens own their models; this view owns shared services.
struct RootView: View {
    @AppStorage("appearance") private var appearance = AppAppearance.system
    @State private var session = SessionModel()
    @State private var passkeys = PasskeyAuthorizer()
    @State private var discovery = ConnectedDiscoveryModel.backgroundWalk
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            screen
                .navigationTitle("face2face")
                .toolbar(.hidden, for: .navigationBar)
                .activityAlert(session.activity)
        }
        .background { KeyboardDismissOnTap().frame(width: 0, height: 0) }
        .task {
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-town-preview") {
                    session.enterTownPreview()
                    return
                }
            #endif
            await session.restore()
        }
        .preferredColorScheme(appearance.colorScheme)
        .sensoryFeedback(.success, trigger: discovery.matchCount) { previous, current in
            DiscoveryMatchFeedback.shouldPlay(
                previousCount: previous, currentCount: current,
                isActive: scenePhase == .active && discovery.isApplicationActive)
        }
        .onChange(of: session.phase) { refreshCompanion() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshCompanion() }
        }
    }

    private func refreshCompanion() {
        guard let phase = session.phase else { return }
        if case .ready(let account) = phase {
            BlobCompanionModel.shared.refresh(seed: account.user.avatar.seed)
        } else {
            BlobCompanionModel.shared.stop()
        }
    }

    @ViewBuilder private var screen: some View {
        switch session.phase {
        case nil:
            ProgressView().accessibilityLabel("Loading")
        case .signedOut:
            ContentView(session: session, passkeys: passkeys)
        case .needsOnboarding(let account):
            OnboardingView(account: account, session: session)
        case .ready(let account):
            TownView(account: account, session: session, passkeys: passkeys)
        }
    }
}
