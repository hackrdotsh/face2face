import Foundation

public struct User: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let email: String
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
