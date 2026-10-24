import Face2FaceCore
import SwiftUI

enum SignInField: Hashable {
    case email, password, code, newPassword
}

struct SignInView: View {
    @State private var model: SignInModel
    let contentVisible: Bool
    let focusedField: FocusState<SignInField?>.Binding
    let onClose: () -> Void

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
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 12) {
                Text(model.step == .details ? "Hey, you." : "Check your inbox")
                    .font(.system(.title, design: .rounded, weight: .heavy))
                    .accessibilityAddTraits(.isHeader)
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
            .modifier(entrance(0))

            switch model.step {
            case .details: details
            case .code(let purpose): codeEntry(purpose)
            }
        }
        .disabled(model.activity.isBusy)
        .onChange(of: model.activity.errorMessage) { _, error in
            if let error { AccessibilityNotification.Announcement(error).post() }
        }
    }

    private var details: some View {
        Group {
            Picker("Sign-in method", selection: $model.method) {
                Text("Email code").tag(SignInModel.Method.emailCode)
                Text("Password").tag(SignInModel.Method.password)
                Text("Create account").tag(SignInModel.Method.createAccount)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("signInMethod")
            .modifier(entrance(1))

            field("Email", symbol: "envelope") {
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
            .modifier(entrance(2))

            if model.method != .emailCode {
                field("Password", symbol: "lock") {
                    SecureField("Your password", text: $model.password)
                        .textContentType(model.method == .createAccount ? .newPassword : .password)
                        .focused(focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(submitDetails)
                        .accessibilityLabel("Password")
                        .accessibilityIdentifier("passwordField")
                }
                .modifier(entrance(3))
            }
            if model.method == .createAccount {
                Text("Use at least 12 characters.")
                    .font(.footnote)
                    .foregroundStyle(MeadowPalette.secondaryInk)
                    .modifier(entrance(3))
            }

            feedback.modifier(entrance(4))
            primaryButton(submitTitle, action: submitDetails).modifier(entrance(5))

            VStack(spacing: 12) {
                if model.method == .password {
                    Button("Forgot password?") {
                        focusedField.wrappedValue = nil
                        Task { await model.forgotPassword() }
                    }
                    .frame(minHeight: 44)
                }
                Button("Sign in with a passkey") {
                    focusedField.wrappedValue = nil
                    Task { await model.signInWithPasskey() }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .font(.footnote.weight(.semibold))
            .modifier(entrance(6))
        }
    }

    private func codeEntry(_ purpose: EmailCodePurpose) -> some View {
        Group {
            field("6-digit code", symbol: "number") {
                TextField("000000", text: $model.code)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .focused(focusedField, equals: .code)
                    .accessibilityLabel("6-digit code")
                    .accessibilityIdentifier("codeField")
            }
            .modifier(entrance(2))
            if purpose == .passwordReset {
                field("New password", symbol: "lock") {
                    SecureField("New password", text: $model.newPassword)
                        .textContentType(.newPassword)
                        .focused(focusedField, equals: .newPassword)
                        .accessibilityLabel("New password")
                }
                .modifier(entrance(3))
            }
            feedback.modifier(entrance(4))
            primaryButton(purpose == .passwordReset ? "Reset password" : "Continue") {
                focusedField.wrappedValue = nil
                Task { await model.submitCode() }
            }
            .modifier(entrance(5))
            HStack {
                Button("Send a new code") { Task { await model.resendCode() } }
                Spacer()
                Button("Back") {
                    focusedField.wrappedValue = nil
                    model.backToDetails()
                }
            }
            .font(.footnote.weight(.semibold))
            .frame(minHeight: 44)
            .modifier(entrance(6))
        }
    }

    @ViewBuilder private var feedback: some View {
        if let notice = model.notice {
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
        case .emailCode: "Email me a code"
        case .password: "Sign in"
        case .createAccount: "Create account"
        }
    }

    private func submitDetails() {
        focusedField.wrappedValue = nil
        Task { await model.submitDetails() }
    }

    private func entrance(_ order: Int) -> FormEntrance {
        FormEntrance(visible: contentVisible, order: order, lastOrder: 6)
    }

    private func field<Content: View>(
        _ label: String, symbol: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(.caption, design: .rounded, weight: .bold))
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(MeadowPalette.secondaryInk).accessibilityHidden(
                    true)
                content().font(.body).tint(MeadowPalette.ink)
            }
            .padding(15)
            .frame(minHeight: 52)
            .background(MeadowPalette.field, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(MeadowPalette.fieldBorder, lineWidth: 1).allowsHitTesting(false)
            }
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Text(title)
                if model.activity.isBusy {
                    ProgressView().tint(MeadowPalette.accentInk)
                } else {
                    Image(systemName: "arrow.right").accessibilityHidden(true)
                }
                Spacer(minLength: 0)
            }
            .font(.system(.headline, design: .rounded, weight: .heavy))
            .foregroundStyle(MeadowPalette.accentInk)
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 16).fill(MeadowPalette.accent)
                    .shadow(color: MeadowPalette.accentShadow, radius: 0, y: 4)
            }
        }
        .buttonStyle(MeadowPressStyle())
        .accessibilityValue(model.activity.isBusy ? "Loading" : "")
        .accessibilityIdentifier("accountSubmit")
    }
}
