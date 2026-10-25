import Face2FaceCore
import SwiftUI

/// Chooses the screen for the current session phase. Screens own their models; this view owns shared services.
struct RootView: View {
    @AppStorage("appearance") private var appearance = AppAppearance.system
    @State private var session = SessionModel()
    @State private var passkeys = PasskeyAuthorizer()
    @State private var discovery = ConnectedDiscoveryModel.backgroundWalk
    @State private var companion = BlobCompanionModel.shared
    @AppStorage(BlobSurface.signalPreferenceKey) private var islandSignalEnabled = false
    @AppStorage(CampfireStore.preferenceKey) private var campfireEnabled = false
    @State private var incomingSurfaceURL: URL?
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
        .onOpenURL { url in
            guard url == BlobSurface.townURL || url == BlobSurface.connectionsURL else { return }
            // Retain cold-launch/widget routes until authentication and onboarding resolve.
            incomingSurfaceURL = url
        }
        .sensoryFeedback(.success, trigger: discovery.matchCount) { previous, current in
            DiscoveryMatchFeedback.shouldPlay(
                previousCount: previous, currentCount: current,
                isActive: scenePhase == .active && discovery.isApplicationActive)
        }
        .onChange(of: session.phase) {
            refreshCompanion()
            Task { await CampfireWidgetModel.shared.refresh(session: session) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshCompanion()
                Task { await CampfireWidgetModel.shared.refresh(session: session) }
            }
        }
        .onChange(of: islandSignalEnabled, initial: true) {
            discovery.radio.setSignalEnabled(islandSignalEnabled)
            publishSignal()
        }
        .onChange(of: discovery.radio.signalSample) { publishSignal() }
        .onChange(of: discovery.discoveryState) { publishSignal() }
        .onChange(of: companion.session?.id) { publishSignal(force: true) }
        .onChange(of: campfireEnabled) {
            if campfireEnabled {
                Task { await CampfireWidgetModel.shared.refresh(session: session, force: true) }
            } else {
                CampfireWidgetModel.shared.clear(.disabled)
            }
        }
    }

    private func publishSignal(force: Bool = false) {
        let signal: BlobSignal
        if !islandSignalEnabled || !discovery.isEnabled {
            signal = .off
        } else if discovery.discoveryState == .paused {
            signal = BlobSignal(mode: .paused)
        } else if discovery.radio.signalSample.levels.isEmpty {
            signal = BlobSignal(mode: .waiting)
        } else {
            signal = BlobSignal(mode: .receiving, sample: discovery.radio.signalSample)
        }
        companion.updateSignal(signal, force: force)
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
            TownView(
                account: account, session: session, passkeys: passkeys,
                incomingSurfaceURL: $incomingSurfaceURL)
        }
    }
}
