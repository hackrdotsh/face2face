import Face2FaceCore
import SwiftUI

enum SignInField: Hashable {
    case email, password, code, newPassword
}

struct SignInView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: SignInModel
    let contentVisible: Bool
    let focusedField: FocusState<SignInField?>.Binding
    let onClose: () -> Void

    static let lastEntranceOrder = 4

    init(
        session: SessionModel, passkeys: PasskeyAuthorizer, contentVisible: Bool,
        focusedField: FocusState<SignInField?>.Binding, onClose: @escaping () -> Void
    ) {
        _model = State(initialValue: SignInModel(session: session, passkeys: passkeys))
        self.contentVisible = contentVisible
        self.focusedField = focusedField
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header.modifier(entrance(0))
            switch model.step {
            case .details: details
            case .code(let purpose): codeEntry(purpose)
            }
        }
        .disabled(model.activity.isBusy)
        .onChange(of: model.activity.errorMessage) { _, error in
            if let error { AccessibilityNotification.Announcement(error).post() }
        }
        .onChange(of: model.step) { _, step in
            if case .code = step { focusedField.wrappedValue = .code }
        }
        .onChange(of: model.codeRejections) { focusedField.wrappedValue = .code }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(.title, design: .rounded, weight: .heavy))
                    .contentTransition(.interpolate)
                    .accessibilityAddTraits(.isHeader)
                if case .code = model.step, let notice = model.notice {
                    Text(notice)
                        .font(.subheadline)
                        .foregroundStyle(MeadowPalette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(.subheadline, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(MeadowPalette.field, in: Circle())
            }
            .buttonStyle(MeadowPressStyle())
            .accessibilityLabel("Back to welcome")
            .accessibilityIdentifier("loginBack")
        }
    }

    private var title: String {
        switch model.step {
        case .code(.passwordReset): "Reset your password"
        case .code: "Check your inbox"
        case .details where model.method == .createAccount: "Create Account"
        case .details: "Hey, you."
        }
    }

    private var details: some View {
        Group {
            if model.method != .createAccount {
                MeadowSegmentedControl(
                    title: "Sign-in method",
                    selection: Binding(get: { model.method }, set: { switchMode(to: $0) }),
                    options: [(.emailCode, "Email Code"), (.password, "Password")]
                )
                .accessibilityIdentifier("signInMethod")
                .modifier(entrance(1))
                .transition(modeTransition)
            }

            VStack(alignment: .leading, spacing: 12) {
                MeadowField(label: "Email", symbol: "envelope") {
                    TextField("you@example.com", text: $model.email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused(focusedField, equals: .email)
                        .submitLabel(model.method == .emailCode ? .go : .next)
                        .onSubmit {
                            if model.method == .emailCode {
                                submitDetails()
                            } else {
                                focusedField.wrappedValue = .password
                            }
                        }
                        .accessibilityLabel("Email")
                        .accessibilityIdentifier("emailField")
                }

                if model.method != .emailCode {
                    MeadowField(
                        label: "Password", symbol: "lock",
                        accessory: model.method == .password
                            ? (
                                "Forgot Password?",
                                {
                                    focusedField.wrappedValue = nil
                                    Task { await model.forgotPassword() }
                                }
                            ) : nil
                    ) {
                        SecureField(
                            model.method == .createAccount ? "At least 12 characters" : "Your password",
                            text: $model.password
                        )
                        .textContentType(model.method == .createAccount ? .newPassword : .password)
                        .focused(focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(submitDetails)
                        .accessibilityLabel("Password")
                        .accessibilityIdentifier("passwordField")
                    }
                    .transition(modeTransition)
                }
            }
            .modifier(entrance(2))

            feedback.modifier(entrance(3))

            MeadowPrimaryButton(title: submitTitle, isBusy: model.activity.isBusy, action: submitDetails)
                .accessibilityIdentifier("accountSubmit")
                .modifier(entrance(3))

            detailsLinks.modifier(entrance(4))
        }
    }

    private var detailsLinks: some View {
        VStack(spacing: 4) {
            if model.method == .createAccount {
                linkButton("Sign In", before: "Already have an account? ") { switchMode(to: .emailCode) }
                    .accessibilityIdentifier("signInLink")
                    .transition(modeTransition)
            } else {
                linkButton("Create Account", before: "New here? ") { switchMode(to: .createAccount) }
                    .accessibilityIdentifier("createAccountLink")
                    .transition(modeTransition)
                linkButton("Sign In", after: " with a Passkey", symbol: "person.badge.key") {
                    Task { await model.signInWithPasskey() }
                }
                .transition(modeTransition)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var modeAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.86)
    }

    private var modeTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94, anchor: .top))
    }

    private func switchMode(to method: SignInModel.Method) {
        withAnimation(modeAnimation) { model.switchMethod(to: method) }
    }

    private func codeEntry(_ purpose: EmailCodePurpose) -> some View {
        Group {
            OneTimeCodeField(
                code: $model.code, focus: focusedField, focusValue: .code,
                rejections: model.codeRejections
            ) {
                if purpose == .passwordReset {
                    focusedField.wrappedValue = .newPassword
                } else {
                    Task { await model.submitCode() }
                }
            }
            .modifier(entrance(1))

            if purpose == .passwordReset {
                MeadowField(label: "New password", symbol: "lock") {
                    SecureField("At least 12 characters", text: $model.newPassword)
                        .textContentType(.newPassword)
                        .focused(focusedField, equals: .newPassword)
                        .submitLabel(.go)
                        .onSubmit(submitCode)
                        .accessibilityLabel("New password")
                }
                .modifier(entrance(2))
            }

            feedback.modifier(entrance(3))

            if purpose == .passwordReset {
                MeadowPrimaryButton(
                    title: "Reset Password", isBusy: model.activity.isBusy, action: submitCode
                )
                .accessibilityIdentifier("accountSubmit")
                .modifier(entrance(3))
            } else if model.activity.isBusy {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Checking code")
            }

            HStack {
                linkButton("Resend Code") { Task { await model.resendCode() } }
                Spacer()
                linkButton("Use a Different Email") {
                    focusedField.wrappedValue = nil
                    model.backToDetails()
                }
            }
            .modifier(entrance(4))
        }
    }

    @ViewBuilder private var feedback: some View {
        if case .details = model.step, let notice = model.notice {
            Text(notice).font(.footnote).foregroundStyle(MeadowPalette.secondaryInk)
        }
        if let error = model.activity.errorMessage {
            Label(error, systemImage: "exclamationmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(MeadowPalette.errorInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("authError")
        }
    }

    private var submitTitle: String {
        switch model.method {
        case .emailCode: "Email Me a Code"
        case .password: "Sign In"
        case .createAccount: "Create Account"
        }
    }

    private func submitDetails() {
        focusedField.wrappedValue = nil
        Task { await model.submitDetails() }
    }

    private func submitCode() {
        focusedField.wrappedValue = nil
        Task { await model.submitCode() }
    }

    /// A text button where only `title` is underlined; `before` and `after` are plain text around it.
    private func linkButton(
        _ title: String, before: String = "", after: String = "", symbol: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let text = Text("\(before)\(Text(title).underline())\(after)")
        return Button {
            if focusedField.wrappedValue != .code { focusedField.wrappedValue = nil }
            action()
        } label: {
            if let symbol {
                Label {
                    text
                } icon: {
                    Image(systemName: symbol)
                }
            } else {
                text
            }
        }
        .font(.system(.footnote, design: .rounded, weight: .bold))
        .foregroundStyle(MeadowPalette.ink)
        .frame(minHeight: 44)
        .buttonStyle(MeadowPressStyle())
    }

    private func entrance(_ order: Int) -> FormEntrance {
        FormEntrance(visible: contentVisible, order: order, lastOrder: Self.lastEntranceOrder)
    }
}
