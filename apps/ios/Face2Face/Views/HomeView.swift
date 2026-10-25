import Face2FaceCore
import SwiftUI

struct HomeView: View {
    let account: Account
    private let session: SessionModel
    @State private var passkeyEnrollment: PasskeyEnrollmentModel
    @State private var showingSettings = false

    init(account: Account, session: SessionModel, passkeys: PasskeyAuthorizer) {
        self.account = account
        self.session = session
        _passkeyEnrollment = State(initialValue: PasskeyEnrollmentModel(session: session, passkeys: passkeys))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MeadowScene(
                    isMoving: !showingSettings && !session.activity.isBusy
                        && !passkeyEnrollment.activity.isBusy,
                    encounterBottomInset: geometry.safeAreaInsets.bottom + 104
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        MeadowHeader { showingSettings = true }
                            .padding(.bottom, 10)
                        profileCard
                        passkeyCard
                        discoveryCard
                    }
                    .frame(maxWidth: 440)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
        }
        .foregroundStyle(MeadowPalette.ink)
        .fontDesign(.rounded)
        .disabled(session.activity.isBusy || passkeyEnrollment.activity.isBusy)
        .activityAlert(passkeyEnrollment.activity)
        .sheet(isPresented: $showingSettings) { SettingsView(session: session) }
        .accessibilityIdentifier("accountHome")
    }

    private var initials: String {
        let letters = account.user.name.split(whereSeparator: \.isWhitespace).prefix(2)
            .compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    private var profileCard: some View {
        card {
            VStack(spacing: 18) {
                Text(initials)
                    .font(.system(.title2, design: .rounded, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: 68, height: 68)
                    .background(MeadowPalette.accent.opacity(0.35), in: Circle())
                    .accessibilityHidden(true)

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

                Button {
                    Task { await session.signOut() }
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
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
            .frame(maxWidth: .infinity)
        }
    }

    private var passkeyCard: some View {
        card {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: passkeyEnrollment.isEnrolled ? "checkmark.shield.fill" : "faceid")
                        .font(.system(size: 25, weight: .semibold))
                        .frame(width: 52, height: 52)
                        .background(
                            MeadowPalette.accent.opacity(0.25), in: RoundedRectangle(cornerRadius: 16)
                        )
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(passkeyEnrollment.isEnrolled ? "Passkey added" : "Easy sign-in")
                            .font(.system(.title3, design: .rounded, weight: .heavy))
                            .accessibilityAddTraits(.isHeader)
                        Text(
                            passkeyEnrollment.isEnrolled
                                ? "Use it the next time you sign in."
                                : "Use Face ID or Touch ID instead of typing a password."
                        )
                        .font(.subheadline)
                        .foregroundStyle(MeadowPalette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !passkeyEnrollment.isEnrolled {
                    Button {
                        Task { await passkeyEnrollment.addPasskey(for: account) }
                    } label: {
                        Text("Add a passkey")
                            .font(.system(.headline, design: .rounded, weight: .heavy))
                            .foregroundStyle(MeadowPalette.accentInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(MeadowPalette.accent, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(MeadowPressStyle())
                    .accessibilityIdentifier("addPasskey")
                }
            }
        }
    }

    private var discoveryCard: some View {
        card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "figure.2")
                    .font(.title2.weight(.semibold))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nearby")
                        .font(.system(.headline, design: .rounded, weight: .heavy))
                        .accessibilityAddTraits(.isHeader)
                    Text("Nearby discovery isn’t available yet.")
                        .font(.subheadline)
                        .foregroundStyle(MeadowPalette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                MeadowGlass(shape: RoundedRectangle(cornerRadius: 32))
                    .shadow(color: MeadowPalette.shadow.opacity(0.12), radius: 16, y: 6)
            }
    }
}
