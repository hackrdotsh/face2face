import Foundation

/// Signed paths to square variants, relative to the API server. Show them as circles.
public struct ProfilePhoto: Codable, Sendable, Equatable {
    public let large: String
    public let thumb: String

    public init(large: String, thumb: String) {
        self.large = large
        self.thumb = thumb
    }
}

/// A photo, or a blob avatar drawn from `seed` when there is none.
public struct Avatar: Codable, Sendable, Equatable {
    public let seed: String
    public let photo: ProfilePhoto?
}

public struct User: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let email: String
    public let avatar: Avatar
}

public struct Account: Codable, Sendable, Equatable {
    public let user: User
    public let onboardingComplete: Bool
}

public enum SessionPhase: Equatable, Sendable {
    case signedOut
    case needsOnboarding(Account)
    case ready(Account)

    public init(account: Account?) {
        guard let account else {
            self = .signedOut
            return
        }
        self = account.onboardingComplete ? .ready(account) : .needsOnboarding(account)
    }
}
