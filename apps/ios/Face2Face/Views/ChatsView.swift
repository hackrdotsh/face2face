import Face2FaceCore
import SwiftUI

struct ChatRoute: Hashable, Identifiable { let id: String }

struct ChatsView: View {
    let session: SessionModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var chats: [ChatSummary] = []
    @State private var loading = true
    @State private var error: String?
    @State private var generation = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Pull up a chair.", systemImage: "cup.and.saucer.fill")
                        .font(.system(.title, design: .rounded, weight: .bold))
                    Text("A little conversation goes a long way.")
                        .font(.subheadline).foregroundStyle(MeadowPalette.secondaryInk)
                    if session.isTownPreview {
                        Text("Preview · sample conversations").font(.caption).foregroundStyle(
                            MeadowPalette.secondaryInk
                        )
                        .accessibilityIdentifier("chatsPreviewLabel")
                    }
                    if loading && chats.isEmpty {
                        ProgressView("Finding your table…").frame(maxWidth: .infinity).padding(32)
                    } else if let error {
                        Text(error).foregroundStyle(MeadowPalette.errorInk)
                        Button("Try again") { Task { await reload() } }.buttonStyle(.bordered)
                    } else if chats.isEmpty {
                        ContentUnavailableView(
                            "Your table is waiting", systemImage: "cup.and.saucer",
                            description: Text(
                                "When you both accept a connection, your conversation will appear here."))
                    } else {
                        ForEach(chats) { chat in
                            NavigationLink(value: ChatRoute(id: chat.id)) {
                                HStack(spacing: 14) {
                                    ChatIdentityAvatar(chat: chat, session: session, side: 44)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(chat.title).font(.headline)
                                        Text(
                                            chat.lastMessage?.text
                                                ?? (chat.lastMessage?.image == nil
                                                    ? "Say a little hello." : "Photo")
                                        )
                                        .font(.subheadline).foregroundStyle(MeadowPalette.secondaryInk)
                                        .lineLimit(2)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    if chat.unreadCount > 0 {
                                        Text(chat.unreadCount > 99 ? "99+" : String(chat.unreadCount))
                                            .font(.caption.weight(.bold)).padding(8)
                                            .background(MeadowPalette.accent, in: Circle())
                                            .foregroundStyle(MeadowPalette.accentInk)
                                            .accessibilityLabel("\(chat.unreadCount) unread messages")
                                    }
                                    Image(systemName: "chevron.right").font(.caption.weight(.bold))
                                }
                                .padding(18).background(
                                    MeadowPalette.paper, in: RoundedRectangle(cornerRadius: 24))
                            }
                            .buttonStyle(MeadowPressStyle())
                            .accessibilityIdentifier("chat-\(chat.id)")
                        }
                    }
                }
                .padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .refreshable { await reload() }
            .background(MeadowPalette.grass.ignoresSafeArea())
            .navigationTitle("Connections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(for: ChatRoute.self) { route in
                ChatConversationView(chatID: route.id, session: session)
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else {
                    chats = []
                    generation += 1
                    return
                }
                await reload()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    await reload()
                }
            }
        }
        .foregroundStyle(MeadowPalette.ink).fontDesign(.rounded)
    }

    @MainActor private func reload() async {
        generation += 1
        let request = generation
        loading = true
        error = nil
        defer { if request == generation { loading = false } }
        do {
            let result: [ChatSummary]
            #if DEBUG
                if session.isTownPreview {
                    result = try ChatPreview.chats()
                } else {
                    result = try await session.client().chats()
                }
            #else
                result = try await session.client().chats()
            #endif
            guard request == generation, !Task.isCancelled else { return }
            chats = result
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            chats = []
            self.error = "Couldn't load your conversations. Please try again."
        }
    }
}

struct ChatIdentityAvatar: View {
    let chat: ChatSummary?
    let session: SessionModel
    var side: CGFloat = 36
    var body: some View {
        Group {
            if let friend = chat?.connection.publicTownFriend {
                AvatarView(avatar: friend.avatar, session: session, side: side)
            } else {
                Image(systemName: "person.fill.questionmark")
                    .font(.system(size: side * 0.42)).foregroundStyle(MeadowPalette.accentInk)
                    .frame(width: side, height: side).background(MeadowPalette.accent, in: Circle())
            }
        }.accessibilityHidden(true)
    }
}
