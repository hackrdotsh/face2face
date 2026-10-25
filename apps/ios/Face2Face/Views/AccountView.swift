import Face2FaceCore
import SwiftUI

struct AccountView: View {
    let account: Account
    @Bindable var session: SessionModel
    @Environment(\.dismiss) private var dismiss
    @State private var passkeyEnrollment: PasskeyEnrollmentModel
    @State private var interests: InterestsModel

    init(account: Account, session: SessionModel, passkeys: PasskeyAuthorizer) {
        self.account = account
        self.session = session
        _passkeyEnrollment = State(initialValue: PasskeyEnrollmentModel(session: session, passkeys: passkeys))
        _interests = State(initialValue: InterestsModel(session: session))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MeadowScene(
                    isMoving: !session.activity.isBusy && !passkeyEnrollment.activity.isBusy,
                    encounterBottomInset: geometry.safeAreaInsets.bottom + 104
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        MeadowCard { profile }
                        MeadowCard { InterestsSection(model: interests) }.disabled(session.isTownPreview)
                        MeadowCard {
                            DiscoverySection(model: ConnectedDiscoveryModel.backgroundWalk, account: account)
                        }
                        .disabled(session.isTownPreview)
                        MeadowCard { passkeySection }.disabled(session.isTownPreview)
                    }
                    .disabled(
                        session.activity.isBusy || passkeyEnrollment.activity.isBusy
                    )
                    .frame(maxWidth: 440)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .foregroundStyle(MeadowPalette.ink)
        .fontDesign(.rounded)
        .activityAlert(passkeyEnrollment.activity)
        .accessibilityIdentifier("accountHome")
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var profile: some View {
        VStack(spacing: 18) {
            BlobPortrait(seed: account.user.avatar.seed)
            VStack(spacing: 6) {
                Text("Hey, \(account.user.name).")
                    .font(.system(.title, design: .rounded, weight: .heavy))
                    .accessibilityAddTraits(.isHeader)
                Text(account.user.email)
                    .font(.subheadline)
                    .foregroundStyle(MeadowPalette.secondaryInk)
                    .textSelection(.enabled)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            signOutButton
                .disabled(session.isTownPreview)
        }
        .frame(maxWidth: .infinity)
    }

    private var passkeySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            MeadowSectionHeader(title: "Passkey")
            if passkeyEnrollment.isEnrolled {
                Label("Passkey added", systemImage: "checkmark.shield")
            } else {
                Text("Use Face ID or Touch ID instead of typing a password.")
                    .font(.subheadline)
                    .foregroundStyle(MeadowPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                MeadowPrimaryButton(title: "Add a Passkey", symbol: "person.badge.key") {
                    Task { await passkeyEnrollment.addPasskey(for: account) }
                }
                .accessibilityIdentifier("addPasskey")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var signOutButton: some View {
        Button {
            Task {
                await session.signOut()
                if case .signedOut = session.phase { dismiss() }
            }
        } label: {
            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .frame(minHeight: 44)
                .background(MeadowPalette.field, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(MeadowPressStyle())
        .accessibilityIdentifier("homeSignOut")
    }
}
