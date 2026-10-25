import Face2FaceCore
import SwiftUI

struct CompactPublicProfileView: View {
    let model: TownFriendsModel
    let session: SessionModel
    var onMessage: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Public Profile").font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark").font(.subheadline.weight(.bold))
                        .frame(width: 44, height: 44)
                        .background(MeadowPalette.paper, in: Circle())
                }
                .accessibilityLabel("Close profile")
                .accessibilityIdentifier("publicProfileClose")
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 8)
            ScrollView {
                Group {
                    if let message = model.error {
                        status(
                            "Couldn't check this profile", message: message, symbol: "wifi.exclamationmark",
                            retry: true)
                    } else if let friend = model.selectedProfile {
                        profile(friend)
                    } else if model.profileChecked {
                        status(
                            "Profile no longer available",
                            message: "This connection is no longer public or is no longer available.",
                            symbol: "person.crop.circle.badge.xmark", retry: false)
                    } else {
                        ProgressView("Checking public connection…")
                            .padding(48).frame(maxWidth: .infinity)
                    }
                }.padding(.horizontal, 24).padding(.bottom, 28)
            }
        }
        .background(MeadowPalette.grass.ignoresSafeArea())
        .foregroundStyle(MeadowPalette.ink)
        .fontDesign(.rounded)
        .task(id: model.selectedID) { await model.refresh() }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func profile(_ friend: PublicTownFriend) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 18) {
                AvatarView(avatar: friend.avatar, session: session, side: 76)
                    .padding(6).background(MeadowPalette.paper, in: Circle())
                VStack(alignment: .leading, spacing: 7) {
                    Text(friend.age.map { "\(friend.name), \($0)" } ?? friend.name)
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("publicProfileName")
                    Label("Public connection", systemImage: "person.2.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MeadowPalette.secondaryInk)
                }
            }
            if let statusMessage = friend.statusMessage {
                Label {
                    Text(statusMessage)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "text.bubble.fill").foregroundStyle(MeadowPalette.secondaryInk)
                }
                .font(.body.weight(.medium))
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MeadowPalette.paper, in: RoundedRectangle(cornerRadius: MeadowRadius.control))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Status: \(statusMessage)")
                .accessibilityIdentifier("publicProfileStatusMessage")
            }
            if !friend.interests.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("A few things they love").font(.subheadline.weight(.bold))
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 100), alignment: .leading)],
                        alignment: .leading, spacing: 8
                    ) {
                        ForEach(Array(friend.interests.enumerated()), id: \.offset) { _, interest in
                            Text(interest.capitalized)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .frame(maxWidth: .infinity)
                                .background(
                                    friend.sharedInterests.contains(interest)
                                        ? MeadowPalette.accent : MeadowPalette.paper,
                                    in: Capsule()
                                )
                                .foregroundStyle(
                                    friend.sharedInterests.contains(interest)
                                        ? MeadowPalette.accentInk : MeadowPalette.ink
                                )
                                .accessibilityLabel(
                                    "\(interest)\(friend.sharedInterests.contains(interest) ? ", shared interest" : "")"
                                )
                        }
                    }
                    if friend.interests.contains(where: friend.sharedInterests.contains) {
                        Text("Highlighted interests are ones you share.")
                            .font(.caption).foregroundStyle(MeadowPalette.secondaryInk)
                    }
                }
            }
            if let onMessage {
                Button {
                    onMessage(friend.id)
                } label: {
                    Label("Message", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(MeadowPalette.accent, in: Capsule())
                        .foregroundStyle(MeadowPalette.accentInk)
                }
                .buttonStyle(MeadowPressStyle())
                .accessibilityIdentifier("publicProfileMessage")
            }
            Text("A familiar face in your town—not a live location or online status.")
                .font(.footnote).foregroundStyle(MeadowPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            if model.isPreview {
                Text("Preview · sample public friend").font(.caption)
                    .foregroundStyle(MeadowPalette.secondaryInk)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MeadowPalette.paper.opacity(0.55), in: RoundedRectangle(cornerRadius: 28))
    }

    private func status(_ title: String, message: String, symbol: String, retry: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(MeadowPalette.secondaryInk)
            Text(title).font(.headline).multilineTextAlignment(.center)
                .accessibilityIdentifier("publicProfileStatus")
            Text(message).font(.subheadline).foregroundStyle(MeadowPalette.secondaryInk)
                .multilineTextAlignment(.center)
            if retry {
                Button("Try again") { Task { await model.refresh() } }
                    .padding(.horizontal, 18).frame(minHeight: 44)
                    .background(MeadowPalette.accent, in: Capsule())
                    .foregroundStyle(MeadowPalette.accentInk)
                    .accessibilityIdentifier("publicProfileRetry")
            }
        }.padding(.vertical, 32).frame(maxWidth: .infinity)
    }
}
