import SwiftUI

@MainActor
struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var accountTransition
    @Bindable var session: SessionModel
    let passkeys: PasskeyAuthorizer
    @State private var showingSettings = false
    @State private var showingLogin = false
    @State private var formVisible = false
    @State private var isClosingForm = false
    @FocusState private var focusedField: SignInField?

    var body: some View {
        GeometryReader { geometry in
            let contentHeight = showingLogin ? geometry.size.height - 44 : geometry.size.height * 2 / 3
            ZStack {
                MeadowScene(
                    isMoving: focusedField == nil && !showingSettings,
                    encounterBottomInset: geometry.safeAreaInsets.bottom + 104
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        toolbar
                        welcome.padding(.top, 32)
                        Spacer(minLength: 110)
                        if showingLogin {
                            accountCard.transition(.opacity)
                        } else {
                            loginButton.transition(.opacity)
                        }
                    }
                    .frame(maxWidth: 440)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: max(0, contentHeight))
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .foregroundStyle(MeadowPalette.ink)
        .fontDesign(.rounded)
        .sheet(isPresented: $showingSettings) {
            SettingsView(session: session)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "figure.2")
                    .font(.system(size: 18, weight: .bold))
                Text("face2face")
                    .font(.system(.headline, design: .rounded, weight: .heavy))
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            Button {
                focusedField = nil
                showingSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 44, height: 44)
                    .background(MeadowPalette.paper, in: Circle())
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("appSettings")
        }
        .font(.system(.subheadline, weight: .semibold))
        .buttonStyle(MeadowPressStyle())
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
            Text("Login")
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
            if reduceMotion {
                accountSurface(expanded: expanded)
            } else {
                accountSurface(expanded: expanded)
                    .matchedGeometryEffect(id: "accountSurface", in: accountTransition, anchor: .bottom)
            }
        }
        .shadow(color: MeadowPalette.shadow.opacity(0.12), radius: 16, y: 6)
    }

    @ViewBuilder
    private func accountSurface(expanded: Bool) -> some View {
        if expanded {
            glassSurface(RoundedRectangle(cornerRadius: 32), interactive: false)
        } else {
            glassSurface(Capsule(), interactive: true)
        }
    }

    @ViewBuilder
    private func glassSurface<Surface: InsettableShape>(
        _ shape: Surface, interactive: Bool
    ) -> some View {
        if reduceTransparency {
            shape.fill(MeadowPalette.paper)
        } else if #available(iOS 26.0, *) {
            shape.fill(.clear)
                .glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                MeadowPalette.glassEdge.opacity(0.9), MeadowPalette.glassEdge.opacity(0.15),
                                MeadowPalette.glassEdge.opacity(0.6),
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
                }
        }
    }

    private var accountCard: some View {
        SignInView(
            session: session, passkeys: passkeys, contentVisible: formVisible,
            focusedField: $focusedField, onClose: closeLogin
        )
        .padding(24)
        .background { accountBackground(expanded: true) }
    }

    private func openLogin() {
        guard !isClosingForm else { return }
        formVisible = false
        withAnimation(accountAnimation, completionCriteria: .logicallyComplete) {
            showingLogin = true
        } completion: {
            guard showingLogin else { return }
            formVisible = true
        }
    }

    private func closeLogin() {
        guard showingLogin, !isClosingForm else { return }
        focusedField = nil
        isClosingForm = true
        let duration = FormEntrance.exitDuration(lastOrder: 6, reduceMotion: reduceMotion)
        withAnimation(.easeIn(duration: duration), completionCriteria: .logicallyComplete) {
            formVisible = false
        } completion: {
            guard isClosingForm else { return }
            withAnimation(accountAnimation, completionCriteria: .logicallyComplete) {
                showingLogin = false
            } completion: {
                isClosingForm = false
            }
        }
    }
}

struct MeadowPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
