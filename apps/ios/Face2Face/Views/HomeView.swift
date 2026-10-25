import Face2FaceCore
import SwiftUI

struct HomeView: View {
    let account: Account
    private let session: SessionModel
    @State private var passkeyEnrollment: PasskeyEnrollmentModel

    init(account: Account, session: SessionModel, passkeys: PasskeyAuthorizer) {
        self.account = account
        self.session = session
        _passkeyEnrollment = State(initialValue: PasskeyEnrollmentModel(session: session, passkeys: passkeys))
    }

    var body: some View {
        Form {
            Section("Account") {
                ProfilePhotoEditor(avatar: account.user.avatar, session: session)
                Text(account.user.name)
                Text(account.user.email).foregroundStyle(.secondary)
                Button("Sign out") { Task { await session.signOut() } }
            }
            Section("Passkey") {
                if passkeyEnrollment.isEnrolled {
                    Text("Passkey added. You can use it to sign in.")
                } else {
                    Text("Add a passkey to sign in with Face ID or Touch ID.").foregroundStyle(.secondary)
                    Button("Add a passkey") { Task { await passkeyEnrollment.addPasskey(for: account) } }
                }
            }
            Section {
                Text("Nearby discovery is not available yet.").foregroundStyle(.secondary)
            }
        }
        .disabled(session.activity.isBusy || passkeyEnrollment.activity.isBusy)
        .activityAlert(passkeyEnrollment.activity)
    }
}
