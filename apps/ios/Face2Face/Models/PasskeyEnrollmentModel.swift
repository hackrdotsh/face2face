import Face2FaceCore
import Foundation
import Observation

@MainActor
@Observable
final class PasskeyEnrollmentModel {
    private(set) var isEnrolled = false
    let activity = Activity()

    private let session: SessionModel
    private let passkeys: PasskeyAuthorizer

    init(session: SessionModel, passkeys: PasskeyAuthorizer) {
        self.session = session
        self.passkeys = passkeys
    }

    func addPasskey(for account: Account) async {
        await activity.run {
            let client = try self.session.client()
            let challenge = try await client.passkeyRegistrationChallenge(userName: account.user.email)
            let registration = try await self.passkeys.register(challenge)
            try await client.registerPasskey(registration, for: challenge)
            self.isEnrolled = true
        }
    }
}
