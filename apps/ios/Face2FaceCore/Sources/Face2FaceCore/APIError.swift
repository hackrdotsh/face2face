import Foundation

public enum APIError: Error, LocalizedError, Equatable {
    case invalidServerURL
    case insecureServerURL
    case unauthenticated
    case invalidCredentials
    case emailNotVerified
    case invalidCode
    case onboardingRequired
    case invalidFields([String: String])
    case rateLimited
    case invalidResponse
    case server(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL: "Enter the API's base URL without a path, query, or credentials."
        case .insecureServerURL: "Use an HTTPS API URL. HTTP is only allowed in debug builds."
        case .unauthenticated: "Sign in to continue."
        case .invalidCredentials: "Check your email and password, then try again."
        case .emailNotVerified: "Verify your email to continue. We sent you a new code."
        case .invalidCode: "That code is wrong or expired. Check it or request a new one."
        case .onboardingRequired: "Finish setting up your profile to continue."
        case .invalidFields: "Check the highlighted fields, then try again."
        case .rateLimited: "Too many attempts. Wait a minute and try again."
        case .invalidResponse: "The API returned an unexpected response."
        case .server(400): "Check what you entered, then try again."
        case .server(let status): "The API returned HTTP \(status). Try again."
        }
    }
}

struct ServerErrorBody: Decodable {
    let error: String?
    let code: String?
    let fields: [String: String]?
}

extension APIError {
    static func from(status: Int, body: Data) -> APIError {
        let decoded = try? JSONDecoder().decode(ServerErrorBody.self, from: body)
        switch (status, decoded?.error ?? decoded?.code) {
        case (400, "invalid_fields"): return .invalidFields(decoded?.fields ?? [:])
        case (400, "INVALID_OTP"), (400, "OTP_EXPIRED"), (403, "TOO_MANY_ATTEMPTS"): return .invalidCode
        case (401, "INVALID_EMAIL_OR_PASSWORD"): return .invalidCredentials
        case (403, "EMAIL_NOT_VERIFIED"): return .emailNotVerified
        case (403, "onboarding_required"): return .onboardingRequired
        case (429, _): return .rateLimited
        default: return .server(status)
        }
    }
}
