import SwiftUI

@MainActor
struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var accountTransition
    @State private var model = AppModel()
    @State private var showingConnection = false
    @State private var showingLogin = false
    @FocusState private var focusedField: AccountField?

    private enum AccountField: Hashable {
        case name, email, password
    }

    private var showingAccount: Bool { showingLogin || model.user != nil }

    var body: some View {
        GeometryReader { geometry in
            let contentHeight = showingAccount ? geometry.size.height - 44 : geometry.size.height * 2 / 3
            ZStack {
                MeadowScene(
                    isMoving: focusedField == nil && !showingConnection,
                    encounterBottomInset: geometry.safeAreaInsets.bottom + 104
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        toolbar
                        welcome
                            .padding(.top, 32)
                        Spacer(minLength: 110)
                        if showingAccount {
                            accountCard
                                .transition(.opacity)
                        } else {
                            loginButton
                                .transition(.opacity)
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
        .preferredColorScheme(.light)
        .task { await model.restoreSession() }
        .onChange(of: model.errorMessage) { _, error in
            if let error { AccessibilityNotification.Announcement(error).post() }
        }
        .onChange(of: model.user != nil) { _, signedIn in
            if !signedIn { showingLogin = false }
        }
        .sheet(isPresented: $showingConnection) {
            ConnectionView(model: model)
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
                showingConnection = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 44, height: 44)
                    .background(MeadowPalette.paper, in: Circle())
            }
            .accessibilityLabel("Connection settings")
            .accessibilityIdentifier("connectionSettings")
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
        Button {
            withAnimation(accountAnimation) { showingLogin = true }
        } label: {
            Text("Login")
                .font(.system(.headline, design: .rounded, weight: .heavy))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        }
        .background { accountBackground(expanded: false) }
        .buttonStyle(MeadowPressStyle())
        .accessibilityIdentifier("loginStart")
        .disabled(model.isBusy)
    }

    private var accountAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.5, dampingFraction: 0.86)
    }

    private func accountBackground(expanded: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: expanded ? 32 : 16)
            .fill(expanded ? MeadowPalette.paper : MeadowPalette.accent)
        return Group {
            if reduceMotion {
                shape
            } else {
                shape.matchedGeometryEffect(id: "accountSurface", in: accountTransition, anchor: .bottom)
            }
        }
        .shadow(
            color: expanded ? MeadowPalette.ink.opacity(0.08) : MeadowPalette.accentShadow,
            radius: 0, y: expanded ? 6 : 4
        )
        .shadow(color: MeadowPalette.ink.opacity(expanded ? 0.08 : 0), radius: 24, y: 12)
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let user = model.user {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Hey, \(user.name).")
                        .font(.system(.title, design: .rounded, weight: .heavy))
                        .accessibilityAddTraits(.isHeader)
                    Label("You’re signed in", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                    Text("Nearby discovery isn’t available yet.")
                        .font(.subheadline)
                        .foregroundStyle(MeadowPalette.secondaryInk)
                }
                errorMessage
                primaryButton("Sign out", symbol: "arrow.right") {
                    Task { await model.signOut() }
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Text(model.createAccount ? "Join the adventure" : "Hey, you.")
                        .font(.system(.title, design: .rounded, weight: .heavy))
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    Button {
                        focusedField = nil
                        withAnimation(accountAnimation) {
                            showingLogin = false
                            model.createAccount = false
                            model.errorMessage = nil
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(.subheadline, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(MeadowPalette.field, in: Circle())
                    }
                    .buttonStyle(MeadowPressStyle())
                    .accessibilityLabel("Back to welcome")
                    .accessibilityIdentifier("loginBack")
                    .disabled(model.isBusy)
                }

                VStack(alignment: .leading, spacing: 16) {
                    if model.createAccount {
                        field("Name", symbol: "person") {
                            TextField("Your name", text: $model.name)
                                .textContentType(.name)
                                .focused($focusedField, equals: .name)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .email }
                                .accessibilityLabel("Name")
                                .accessibilityIdentifier("nameField")
                        }
                    }
                    field("Email", symbol: "envelope") {
                        TextField("you@example.com", text: $model.email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                            .accessibilityLabel("Email")
                            .accessibilityIdentifier("emailField")
                    }
                    field("Password", symbol: "lock") {
                        SecureField("Your password", text: $model.password)
                            .textContentType(model.createAccount ? .newPassword : .password)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit(authenticate)
                            .accessibilityLabel("Password")
                            .accessibilityIdentifier("passwordField")
                    }
                    if model.createAccount {
                        Text("Use at least 12 characters.")
                            .font(.footnote)
                            .foregroundStyle(MeadowPalette.secondaryInk)
                    }
                }
                .disabled(model.isBusy)

                errorMessage

                primaryButton(
                    model.createAccount ? "Create account" : "Sign in", symbol: "arrow.right",
                    action: authenticate)

                Button {
                    focusedField = nil
                    model.createAccount.toggle()
                    model.errorMessage = nil
                } label: {
                    Text(model.createAccount ? "Already a member? " : "New around here? ")
                        .foregroundStyle(MeadowPalette.secondaryInk)
                        + Text(model.createAccount ? "Sign in" : "Create account")
                        .foregroundStyle(MeadowPalette.ink)
                        .bold()
                }
                .font(.footnote)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("accountModeToggle")
                .disabled(model.isBusy)
            }
        }
        .padding(24)
        .background { accountBackground(expanded: true) }
        .overlay {
            RoundedRectangle(cornerRadius: 32)
                .strokeBorder(.white.opacity(0.8), lineWidth: 2)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var errorMessage: some View {
        if let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(MeadowPalette.errorInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("authError")
        }
    }

    private func field<Content: View>(
        _ label: String, symbol: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(.caption, design: .rounded, weight: .bold))
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(MeadowPalette.secondaryInk)
                    .accessibilityHidden(true)
                content()
                    .font(.body)
                    .tint(MeadowPalette.ink)
            }
            .padding(15)
            .frame(minHeight: 52)
            .background(MeadowPalette.field, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(MeadowPalette.fieldBorder, lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }

    private func primaryButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Text(title)
                if model.isBusy {
                    ProgressView().tint(MeadowPalette.ink)
                } else {
                    Image(systemName: symbol)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
            }
            .font(.system(.headline, design: .rounded, weight: .heavy))
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(MeadowPalette.accent)
                    .shadow(color: MeadowPalette.accentShadow, radius: 0, y: 4)
            }
        }
        .buttonStyle(MeadowPressStyle())
        .accessibilityValue(model.isBusy ? "Loading" : "")
        .accessibilityIdentifier("accountSubmit")
        .disabled(model.isBusy)
    }

    private func authenticate() {
        focusedField = nil
        Task { await model.authenticate() }
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
