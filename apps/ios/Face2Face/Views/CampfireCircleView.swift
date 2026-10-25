import Face2FaceCore
import SwiftUI

struct CampfireCircleView: View {
    let account: Account
    let session: SessionModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var guests: [CampfireGuest] = []
    @State private var page = 0
    @State private var loading = true
    @State private var error: String?
    @State private var generation = 0
    private let pageSize = 6

    private var snapshot: CampfireSnapshot {
        .init(status: .ready, ownSeed: account.user.avatar.seed, guests: guests)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("YOUR CIRCLE", systemImage: "flame.fill")
                        .font(.system(.caption, design: .rounded, weight: .heavy)).tracking(2)
                        .foregroundStyle(Color.orange.opacity(0.9))
                    Text("Good company.\nOne little fire.")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("A seat for everyone you've connected with.")
                        .foregroundStyle(.white.opacity(0.65))
                    if session.isTownPreview {
                        Label("Preview · sample friends", systemImage: "paintbrush.pointed")
                            .font(.caption).accessibilityIdentifier("campfirePreviewLabel")
                    }
                    if loading {
                        ProgressView("Gathering your circle…").tint(.mint).frame(maxWidth: .infinity).padding(
                            40)
                    } else if let error {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Couldn't gather your friends", systemImage: "wifi.exclamationmark").font(
                                .headline)
                            Text(error).font(.subheadline)
                            Button("Try again") { Task { await load() } }.buttonStyle(.borderedProminent)
                        }.accessibilityIdentifier("campfireError")
                    } else {
                        TimelineView(
                            .animation(
                                minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)
                        ) { timeline in
                            CampfireScene(
                                ownSeed: account.user.avatar.seed,
                                guests: snapshot.page(page, size: pageSize),
                                time: reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                            )
                            .frame(height: 260)
                        }
                        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 30))
                        if guests.isEmpty {
                            Text("Your fire is ready.").font(.title3.bold())
                            Text(
                                "Accepted connections will gather here. No one is shown as nearby or online."
                            )
                            .foregroundStyle(.white.opacity(0.65)).accessibilityIdentifier("campfireEmpty")
                        } else {
                            HStack {
                                Text("\(guests.count) friends in your circle").font(.headline)
                                Spacer()
                                Text("\(page + 1) / \(snapshot.pageCount(size: pageSize))").font(
                                    .caption.monospacedDigit())
                            }
                            ForEach(snapshot.page(page, size: pageSize)) { guest in
                                HStack {
                                    BlobGlyph(seed: guest.seed).frame(width: 32, height: 32)
                                    Text(guest.name).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    if guest.isAnonymous {
                                        Image(systemName: "lock.fill").font(.caption).accessibilityLabel(
                                            "Private connection")
                                    }
                                }
                                .padding(10).background(
                                    .white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
                            }
                            if snapshot.pageCount(size: pageSize) > 1 {
                                HStack {
                                    Button("Previous", systemImage: "chevron.left") { turn(-1) }
                                    Spacer()
                                    Button("Next", systemImage: "chevron.right") { turn(1) }
                                }.buttonStyle(.bordered).controlSize(.large)
                            }
                        }
                    }
                    Label(
                        "A symbolic gathering, not live attendance or location. Private connections keep their identity to themselves.",
                        systemImage: "lock.shield"
                    )
                    .font(.footnote).foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                    Text("Bring this fire to your Home Screen in Settings → Around the campfire.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.65))
                }
                .padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .refreshable { await load() }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.15, blue: 0.19), Color(red: 0.02, green: 0.07, blue: 0.09),
                    ], startPoint: .topLeading, endPoint: .bottomTrailing
                ).ignoresSafeArea()
            )
            .foregroundStyle(.white).fontDesign(.rounded)
            .navigationTitle("Around the campfire").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.tint(.mint) }
            }
            .task(id: "\(scenePhase)|\(account.user.id)|\(session.serverAddress)") {
                if scenePhase == .active {
                    await load()
                } else {
                    generation += 1
                    guests = []
                    loading = true
                }
            }
            .accessibilityIdentifier("campfireHome")
        }
        .preferredColorScheme(.dark)
    }

    private func turn(_ direction: Int) {
        let count = snapshot.pageCount(size: pageSize)
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.85))
        {
            page = (page + direction + count) % count
        }
    }

    @MainActor private func load() async {
        generation += 1
        let request = generation
        let address = session.serverAddress
        loading = true
        error = nil
        defer { if !Task.isCancelled, request == generation { loading = false } }
        do {
            let result: [CampfireGuest]
            #if DEBUG
                if session.isTownPreview {
                    let model = TownFriendsModel(session: session)
                    await model.refresh()
                    result = model.visitors.enumerated().map { index, friend in
                        CampfireGuest(
                            id: index, name: friend.name, seed: friend.avatar.seed, isAnonymous: false)
                    }
                } else {
                    result = CampfireWidgetModel.guests(from: try await session.client().townConnections())
                }
            #else
                result = CampfireWidgetModel.guests(from: try await session.client().townConnections())
            #endif
            guard !Task.isCancelled, request == generation, session.serverAddress == address,
                case .ready(let current) = session.phase, current.user.id == account.user.id
            else { return }
            guests = result
            page = min(page, snapshot.pageCount(size: pageSize) - 1)
        } catch {
            guard !Task.isCancelled, request == generation else { return }
            guests = []
            self.error = "Please check your connection and try again."
        }
    }
}
