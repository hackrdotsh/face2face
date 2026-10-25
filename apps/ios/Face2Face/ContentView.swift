import SwiftUI

@MainActor
struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var accountTransition
    @Bindable var session: SessionModel
    let passkeys: PasskeyAuthorizer
    @State private var showingSettings = false
    @State private var showingLogin = false
    @State private var formVisible = false
    @State private var isClosingForm = false
    /// The open card follows the matched surface only while it morphs, so keyboard and step changes move it like plain content.
    @State private var isMorphing = false
    @FocusState private var focusedField: SignInField?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Its own geometry ignores the keyboard, so opening it does not move the walker or the camera.
                GeometryReader { scene in
                    MeadowScene(
                        isMoving: !showingSettings, encounterBottomInset: scene.safeAreaInsets.bottom + 104
                    )
                    .ignoresSafeArea()
                }
                .ignoresSafeArea(.keyboard)

                ScrollView {
                    VStack(spacing: 0) {
                        toolbar
                        if showingLogin {
                            Spacer(minLength: 16)
                            accountCard.transition(
                                .asymmetric(
                                    insertion: .opacity,
                                    // The pill's matched surface carries the shrink, so the card's text leaves right away.
                                    removal: .opacity.animation(.easeOut(duration: 0.08))))
                            Spacer(minLength: 0)
                            // Balances the toolbar, the uneven paddings, and the uneven safe areas, so the card centers on the screen.
                            Color.clear.frame(
                                height: max(
                                    0, 24 + geometry.safeAreaInsets.top - geometry.safeAreaInsets.bottom))
                        } else {
                            welcome.padding(.top, 32).transition(.opacity)
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(maxWidth: 440)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: max(0, geometry.size.height - 44))
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                    .overlay {
                        if !showingLogin {
                            loginButton
                                .padding(
                                    .bottom, geometry.safeAreaInsets.top - geometry.safeAreaInsets.bottom
                                )
                                .transition(.opacity)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .foregroundStyle(MeadowPalette.ink)
        .fontDesign(.rounded)
        .sheet(isPresented: $showingSettings) {
            SettingsView(session: session)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            MeadowHeader {
                focusedField = nil
                showingSettings = true
            }
            #if DEBUG
                Button {
                    session.enterTownPreview()
                } label: {
                    Image(systemName: "map")
                        .frame(width: 44, height: 44)
                        .background(MeadowPalette.paper, in: Circle())
                }
                .accessibilityLabel("Skip to town (debug)")
                .buttonStyle(MeadowPressStyle())
                .font(.system(.subheadline, weight: .semibold))
            #endif
        }
    }

    private var welcome: some View {
        Text("A little hello.\nA new adventure.")
            .font(.system(.largeTitle, design: .rounded, weight: .heavy))
            .tracking(-1.2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var loginButton: some View {
        Button(action: openLogin) {
            Text("Get Started")
                .font(.system(.headline, design: .rounded, weight: .heavy))
                .frame(minWidth: 140)
                .padding(.horizontal, 30)
                .padding(.vertical, 18)
                .background { accountBackground(expanded: false) }
                .contentShape(Capsule())
        }
        .buttonStyle(MeadowPressStyle())
        .accessibilityIdentifier("loginStart")
        .disabled(session.activity.isBusy || isClosingForm)
    }

    private var accountAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.5, dampingFraction: 0.86)
    }

    private func accountBackground(expanded: Bool) -> some View {
        Group {
            if reduceMotion || (expanded && !isMorphing) {
                accountSurface(expanded: expanded)
            } else {
                accountSurface(expanded: expanded)
                    .matchedGeometryEffect(id: "accountSurface", in: accountTransition, anchor: .center)
            }
        }
        .shadow(color: MeadowPalette.shadow.opacity(0.12), radius: 16, y: 6)
    }

    @ViewBuilder
    private func accountSurface(expanded: Bool) -> some View {
        if expanded {
            MeadowGlass(shape: RoundedRectangle(cornerRadius: MeadowRadius.card))
        } else {
            MeadowGlass(shape: Capsule(), interactive: true)
        }
    }

    private var accountCard: some View {
        SignInView(
            session: session, passkeys: passkeys, contentVisible: formVisible,
            focusedField: $focusedField, onClose: closeLogin
        )
        .padding(MeadowRadius.cardInset)
        .background { accountBackground(expanded: true) }
    }

    private func openLogin() {
        guard !isClosingForm else { return }
        formVisible = false
        isMorphing = true
        withAnimation(accountAnimation, completionCriteria: .logicallyComplete) {
            showingLogin = true
        } completion: {
            isMorphing = false
            guard showingLogin else { return }
            formVisible = true
        }
    }

    private func closeLogin() {
        guard showingLogin, !isClosingForm else { return }
        isClosingForm = true
        let duration = FormEntrance.exitDuration(
            lastOrder: SignInView.lastEntranceOrder, reduceMotion: reduceMotion)
        Task {
            // The keyboard hides first, so its animation can't move the card or override the fade.
            focusedField = nil
            await Keyboard.waitUntilHidden()
            // Each row animates its own staggered exit, so a completion callback would fire before the last row is gone.
            formVisible = false
            try? await Task.sleep(for: .seconds(duration))
            guard isClosingForm else { return }
            // The matched surface has to render once before the card leaves for the morph to start from it.
            isMorphing = true
            try? await Task.sleep(for: .milliseconds(20))
            withAnimation(accountAnimation, completionCriteria: .logicallyComplete) {
                showingLogin = false
            } completion: {
                isClosingForm = false
                isMorphing = false
            }
        }
    }
}
