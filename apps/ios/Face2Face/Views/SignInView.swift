import Face2FaceCore
import SwiftUI

struct SignInView: View {
    @State private var model: SignInModel
    private let session: SessionModel

    init(session: SessionModel, passkeys: PasskeyAuthorizer) {
        self.session = session
        _model = State(initialValue: SignInModel(session: session, passkeys: passkeys))
    }

    var body: some View {
        Form {
            ServerSection(session: session)
            switch model.step {
            case .details: DetailsSection(model: model)
            case .code(let purpose): CodeSection(model: model, purpose: purpose)
            }
            if let notice = model.notice {
                Section { Text(notice).foregroundStyle(.secondary) }
            }
        }
        .disabled(model.activity.isBusy)
        .activityAlert(model.activity)
    }
}

private struct DetailsSection: View {
    @Bindable var model: SignInModel

    var body: some View {
        Section {
            Picker("Sign-in method", selection: $model.method) {
                Text("Email code").tag(SignInModel.Method.emailCode)
                Text("Password").tag(SignInModel.Method.password)
                Text("Create account").tag(SignInModel.Method.createAccount)
            }
            .pickerStyle(.segmented)
            TextField("Email", text: $model.email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if model.method != .emailCode {
                SecureField("Password", text: $model.password)
                    .textContentType(model.method == .createAccount ? .newPassword : .password)
            }
            if model.method == .createAccount {
                Text("Use at least 12 characters for your password.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button(submitTitle) { Task { await model.submitDetails() } }
            if model.method == .password {
                Button("Forgot password?") { Task { await model.forgotPassword() } }
            }
        }
        Section {
            Button("Sign in with a passkey") { Task { await model.signInWithPasskey() } }
        }
    }

    private var submitTitle: String {
        switch model.method {
        case .emailCode: "Email me a code"
        case .password: "Sign in"
        case .createAccount: "Create account"
        }
    }
}

private struct CodeSection: View {
    @Bindable var model: SignInModel
    let purpose: EmailCodePurpose

    var body: some View {
        Section {
            TextField("6-digit code", text: $model.code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
            if purpose == .passwordReset {
                SecureField("New password", text: $model.newPassword)
                    .textContentType(.newPassword)
            }
            Button(purpose == .passwordReset ? "Reset password" : "Continue") {
                Task { await model.submitCode() }
            }
            Button("Send a new code") { Task { await model.resendCode() } }
            Button("Back") { model.backToDetails() }
        }
    }
}
