import Foundation

public enum EmailCodePurpose: String, Sendable {
    case signIn = "sign-in"
    case emailVerification = "email-verification"
    case passwordReset = "forget-password"
}

extension APIClient {
    public func sendSignInCode(email: String) async throws {
        _ = try await post(
            "api/auth/email-otp/send-verification-otp",
            ["email": email, "type": EmailCodePurpose.signIn.rawValue])
    }

    public func signIn(email: String, code: String) async throws {
        let response = try await post("api/auth/sign-in/email-otp", ["email": email, "otp": code])
        try await saveSessionToken(from: response)
    }

    public func signIn(email: String, password: String) async throws {
        let response = try await post("api/auth/sign-in/email", ["email": email, "password": password])
        try await saveSessionToken(from: response)
    }

    /// Creates a password account. The server emails a verification code; pass it to `verifyEmail`.
    public func createAccount(email: String, password: String) async throws {
        _ = try await post("api/auth/sign-up/email", ["name": "", "email": email, "password": password])
    }

    public func verifyEmail(email: String, code: String) async throws {
        let response = try await post("api/auth/email-otp/verify-email", ["email": email, "otp": code])
        try await saveSessionToken(from: response)
    }

    public func resendVerificationCode(email: String) async throws {
        _ = try await post(
            "api/auth/email-otp/send-verification-otp",
            ["email": email, "type": EmailCodePurpose.emailVerification.rawValue])
    }

    public func requestPasswordReset(email: String) async throws {
        _ = try await post("api/auth/email-otp/request-password-reset", ["email": email])
    }

    public func resetPassword(email: String, code: String, newPassword: String) async throws {
        _ = try await post(
            "api/auth/email-otp/reset-password", ["email": email, "otp": code, "password": newPassword])
    }

    public func signOut() async throws {
        _ = try await post("api/auth/sign-out", [String: String](), authenticated: true)
        try await clearSessionToken()
    }
}
