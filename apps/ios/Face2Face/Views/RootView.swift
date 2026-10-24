import Face2FaceCore
import SwiftUI

/// Chooses the screen for the current session phase. Screens own their models; this view owns shared services.
struct RootView: View {
    @State private var session = SessionModel()
    @State private var passkeys = PasskeyAuthorizer()

    var body: some View {
        NavigationStack {
            screen
                .navigationTitle("face2face")
                .activityAlert(session.activity)
        }
        .task { await session.restore() }
    }

    @ViewBuilder private var screen: some View {
        switch session.phase {
        case nil:
            ProgressView().accessibilityLabel("Loading")
        case .signedOut:
            SignInView(session: session, passkeys: passkeys)
        case .needsOnboarding:
            OnboardingView(session: session)
        case .ready(let account):
            HomeView(account: account, session: session, passkeys: passkeys)
        }
    }
}
