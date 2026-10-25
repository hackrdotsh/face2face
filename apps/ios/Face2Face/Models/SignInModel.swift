import Face2FaceCore
import Foundation
import Observation

@MainActor
@Observable
final class SignInModel {
    enum Method: Hashable {
        case emailCode
        case password
        case createAccount
    }

    enum Step: Equatable {
        case details
        case code(EmailCodePurpose)
    }

    var method = Method.emailCode
    private(set) var step = Step.details
    var email = ""
    var password = ""
    var code = ""
    var newPassword = ""
    private(set) var notice: String?
    let activity = Activity()

    private let session: SessionModel
    private let passkeys: PasskeyAuthorizer

    init(session: SessionModel, passkeys: PasskeyAuthorizer) {
        self.session = session
        self.passkeys = passkeys
    }

    func submitDetails() async {
        await activity.run {
            let client = try self.session.client()
            switch self.method {
            case .emailCode:
                try await client.sendSignInCode(email: self.email)
                self.showCodeEntry(.signIn)
            case .password:
                try await self.signInWithPassword(client)
            case .createAccount:
                try await client.createAccount(email: self.email, password: self.password)
                self.showCodeEntry(.emailVerification)
            }
        }
    }

    func submitCode() async {
        guard case .code(let purpose) = step else { return }
        await activity.run {
            let client = try self.session.client()
            switch purpose {
            case .signIn:
                try await client.signIn(email: self.email, code: self.code)
            case .emailVerification:
                try await client.verifyEmail(email: self.email, code: self.code)
            case .passwordReset:
                try await client.resetPassword(
                    email: self.email, code: self.code, newPassword: self.newPassword)
                self.finishPasswordReset()
                return
            }
            self.clearSecrets()
            try await self.session.refreshAccount()
        }
    }

    func resendCode() async {
        guard case .code(let purpose) = step else { return }
        await activity.run {
            let client = try self.session.client()
            switch purpose {
            case .signIn: try await client.sendSignInCode(email: self.email)
            case .emailVerification: try await client.resendVerificationCode(email: self.email)
            case .passwordReset: try await client.requestPasswordReset(email: self.email)
            }
            self.notice = "We sent a new code to \(self.email)."
        }
    }

    func forgotPassword() async {
        await activity.run {
            try await self.session.client().requestPasswordReset(email: self.email)
            self.showCodeEntry(.passwordReset)
        }
    }

    func signInWithPasskey() async {
        await activity.run {
            let client = try self.session.client()
            let challenge = try await client.passkeySignInChallenge()
            let assertion = try await self.passkeys.signIn(challenge)
            try await client.signIn(with: assertion, for: challenge)
            try await self.session.refreshAccount()
        }
    }

    func backToDetails() {
        step = .details
        code = ""
        notice = nil
    }

    private func signInWithPassword(_ client: APIClient) async throws {
        do {
            try await client.signIn(email: email, password: password)
        } catch APIError.emailNotVerified {
            showCodeEntry(.emailVerification)
            notice = "Verify your email first. We sent a code to \(email)."
            return
        }
        clearSecrets()
        try await session.refreshAccount()
    }

    private func showCodeEntry(_ purpose: EmailCodePurpose) {
        code = ""
        notice = "Enter the 6-digit code we sent to \(email)."
        step = .code(purpose)
    }

    private func finishPasswordReset() {
        clearSecrets()
        method = .password
        step = .details
        notice = "Password updated. Sign in with your new password."
    }

    private func clearSecrets() {
        password = ""
        newPassword = ""
        code = ""
    }
}
