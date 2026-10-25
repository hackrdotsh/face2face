import Face2FaceCore
import SwiftUI

/// Chooses the screen for the current session phase. Screens own their models; this view owns shared services.
struct RootView: View {
    @AppStorage("appearance") private var appearance = AppAppearance.system
    @State private var session = SessionModel()
    @State private var passkeys = PasskeyAuthorizer()

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
