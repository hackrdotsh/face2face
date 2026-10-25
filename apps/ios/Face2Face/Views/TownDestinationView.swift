import Face2FaceCore
import SwiftUI

/// Working, read-only destinations while each building's interior is designed separately.
struct TownDestinationView: View {
    let destination: TownDestination
    let session: SessionModel
    @Environment(\.dismiss) private var dismiss
    @State private var forums: [TownForum] = []
    @State private var connections: [TownConnection] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        Group {
            if destination == .connections {
                ChatsView(session: session)
            } else if destination == .forums {
                ForumsView(session: session)
            } else {
                readOnlyDestination
            }
        }
    }

    private var readOnlyDestination: some View {
        NavigationStack {
            Group {
                if session.isTownPreview {
                    ContentUnavailableView(
                        "Town preview", systemImage: destination.symbol,
                        description: Text(
                            "This is where your \(destination.title.lowercased()) will appear. Sign in to load your real data."
                        ))
                } else if loading {
                    ProgressView("Opening \(destination.title.lowercased())…")
                } else if let error {
                    VStack(spacing: 20) {
                        ContentUnavailableView(
                            "Couldn't load this place", systemImage: "wifi.exclamationmark",
                            description: Text(error))
                        Button("Try again") { Task { await load() } }.buttonStyle(.borderedProminent)
                    }
                } else if destination == .forums {
                    if forums.isEmpty {
                        ContentUnavailableView(
                            "A place for your interests", systemImage: "pin",
                            description: Text("Forums appear here for the interests on your profile."))
                    } else {
                        List(forums) { forum in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(forum.interestName.capitalized).font(.headline)
                                Text("\(forum.upcomingPostCount) upcoming events").foregroundStyle(.secondary)
                            }.padding(.vertical, 6)
                        }.refreshable { await load() }
                    }
                } else if connections.isEmpty {
                    ContentUnavailableView(
                        destination == .connections ? "Your table is waiting" : "A new hello is ahead",
                        systemImage: destination.symbol,
                        description: Text(
                            destination == .connections
                                ? "When you both accept a connection, you'll find it here."
                                : "New pending encounters will appear here. The people in the town are just scenery."
                        ))
                } else {
                    List(connections) { connection in
                        VStack(alignment: .leading, spacing: 5) {
                            // The server keeps this nil until both participants go public.
                            Text(
                                connection.publicTownFriend?.name
                                    ?? (connection.isPending ? "A new hello" : "Anonymous connection")
                            )
                            .font(.headline)
                            Text(
                                connection.sharedInterests.isEmpty
                                    ? "No shared interests listed"
                                    : connection.sharedInterests.joined(separator: " · ")
                            )
                            .foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                    }.refreshable { await load() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(destination.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
        }
        .fontDesign(.rounded)
    }

    @MainActor private func load() async {
        guard !session.isTownPreview else {
            loading = false
            return
        }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let client = try session.client()
            if destination == .forums {
                forums = try await client.townForums()
            } else {
                let all = try await client.townConnections()
                connections = all.filter { destination == .connections ? $0.isFriend : $0.isPending }
            }
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}
