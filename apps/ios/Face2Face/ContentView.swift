import SwiftUI

@MainActor
struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = AppModel()
    @State private var scenePaused = false
    @State private var showingConnection = false
    @FocusState private var focusedField: AccountField?

    private enum AccountField: Hashable {
        case name, email, password
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MeadowScene(isMoving: !scenePaused && focusedField == nil && !showingConnection)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        toolbar
                        welcome
                            .padding(.top, 32)
                        Color.clear
                            .frame(height: max(110, geometry.size.height - 650))
                            .accessibilityHidden(true)
                        accountCard
                    }
                    .frame(maxWidth: 440)
                    .frame(maxWidth: .infinity)
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
            if !reduceMotion {
                Button {
                    scenePaused.toggle()
                } label: {
                    Image(systemName: scenePaused ? "play.fill" : "pause.fill")
                        .frame(width: 44, height: 44)
                        .background(MeadowPalette.paper, in: Circle())
                }
                .accessibilityLabel(scenePaused ? "Play scenery" : "Pause scenery")
                .accessibilityIdentifier("sceneryToggle")
            }
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
        VStack(spacing: 12) {
            Text("A little hello.\nA new adventure.")
                .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                .tracking(-1.2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                Text("Take the scenic route")
                Image(systemName: "sparkle")
            }
            .font(.system(.caption, design: .rounded, weight: .bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(MeadowPalette.paper, in: Capsule())
        }
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
                Text(model.createAccount ? "Join the adventure" : "Hey, you.")
                    .font(.system(.title, design: .rounded, weight: .heavy))
                    .accessibilityAddTraits(.isHeader)

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
        .background {
            RoundedRectangle(cornerRadius: 32)
                .fill(MeadowPalette.paper)
                .shadow(color: MeadowPalette.ink.opacity(0.08), radius: 0, y: 6)
                .shadow(color: MeadowPalette.ink.opacity(0.08), radius: 24, y: 12)
        }
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
