import Face2FaceCore
import SwiftUI

struct AccountView: View {
    let account: Account
    @Bindable var session: SessionModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MeadowScene(
                    isMoving: !session.activity.isBusy,
                    encounterBottomInset: geometry.safeAreaInsets.bottom + 104
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        ProfilePhotoEditor(avatar: account.user.avatar, session: session)
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
                            Task {
                                await session.signOut()
                                if case .signedOut = session.phase { dismiss() }
                            }
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
                    .disabled(session.activity.isBusy || session.isTownPreview)
                    .padding(24)
                    .background {
                        MeadowGlass(shape: RoundedRectangle(cornerRadius: 32))
                            .shadow(color: MeadowPalette.shadow.opacity(0.12), radius: 16, y: 6)
                    }
                    .frame(maxWidth: 440)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            }
        }
        .foregroundStyle(MeadowPalette.ink)
        .fontDesign(.rounded)
        .accessibilityIdentifier("accountHome")
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
