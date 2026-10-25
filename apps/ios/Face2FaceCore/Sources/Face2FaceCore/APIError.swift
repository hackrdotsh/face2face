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
    case interestLimitReached
    case invalidResponse
    case forumCancelled, forumEventOver, forumNotAuthor
    case chanceEnded, chanceAlreadyAnswered, connectionChanged
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
        case .interestLimitReached: "You can pick up to 10 interests. Remove one to add another."
        case .invalidResponse: "The API returned an unexpected response."
        case .forumCancelled: "This event was cancelled. You can still leave an existing RSVP."
        case .forumEventOver: "This event has finished, so it can't accept new RSVPs."
        case .forumNotAuthor: "Only the person who posted this event can change it."
        case .chanceEnded: "This chance has ended. Refresh to see the latest chances."
        case .chanceAlreadyAnswered: "Your answer is already saved. Check the latest status."
        case .connectionChanged: "This chance changed while you were answering. Check its latest status."
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
        case (409, "not_pending"): return .chanceEnded
        case (409, "already_decided"): return .chanceAlreadyAnswered
        case (409, "conflict"): return .connectionChanged
        case (409, "post_cancelled"): return .forumCancelled
        case (409, "event_over"): return .forumEventOver
        case (403, "not_author"): return .forumNotAuthor
        case (400, "invalid_fields"): return .invalidFields(decoded?.fields ?? [:])
        case (400, "INVALID_OTP"), (400, "OTP_EXPIRED"), (403, "TOO_MANY_ATTEMPTS"): return .invalidCode
        case (401, "INVALID_EMAIL_OR_PASSWORD"): return .invalidCredentials
        case (403, "EMAIL_NOT_VERIFIED"): return .emailNotVerified
        case (403, "onboarding_required"): return .onboardingRequired
        case (409, "too_many_interests"): return .interestLimitReached
        case (429, _): return .rateLimited
        default: return .server(status)
        }
    }
}
