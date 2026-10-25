import Face2FaceCore
import SwiftUI

private enum EncounterConfirmation {
    case decline(String)
    case block(String)
    var isDecline: Bool {
        if case .decline = self { return true }
        return false
    }
    var title: String { isDecline ? "Let this chance pass?" : "Block this connection?" }
    var buttonTitle: String { isDecline ? "Decline chance" : "Block connection" }
    var message: String {
        isDecline
            ? "This closes the chance. We don't send the other person a declined notification, and your identity stays hidden."
            : "This ends the chance and prevents future connection chances with this person."
    }
}

struct RecentlyEncounteredView: View {
    let session: SessionModel
    @State private var model: EncountersModel
    @State private var confirmation: EncounterConfirmation?
    @State private var showingChats = false
    @State private var path: [ChatRoute] = []
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize

    init(session: SessionModel) {
        self.session = session
        _model = State(initialValue: EncountersModel(session: session))
    }
    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        introduction
                        if model.isPreview {
                            Label("Preview · sample connection chances", systemImage: "paintbrush.pointed")
                                .font(.caption).foregroundStyle(MeadowPalette.secondaryInk)
                                .accessibilityIdentifier("encountersPreviewLabel")
                        }
                        if let id = model.newlyConnectedID { readyCard(id) }
                        if let error = model.error {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(error, systemImage: "exclamationmark.circle").font(.subheadline)
                                    .foregroundStyle(MeadowPalette.errorInk).accessibilityIdentifier(
                                        "encountersError")
                                Button("Refresh chances") { Task { await model.refresh() } }
                                    .font(.subheadline.weight(.bold)).frame(minHeight: 44)
                                    .disabled(model.busyID != nil)
                            }
                        }
                        if let notice = model.notice {
                            Text(notice).font(.footnote).foregroundStyle(MeadowPalette.secondaryInk)
                                .accessibilityIdentifier("encountersNotice")
                        }
                        if model.loading && model.chances.isEmpty && model.newlyConnectedID == nil {
                            ProgressView("Gathering your little hellos…").frame(maxWidth: .infinity).padding(
                                36)
                        } else if model.chances.isEmpty && model.error == nil && model.newlyConnectedID == nil
                        {
                            emptyState
                        } else if !model.chances.isEmpty {
                            Text(
                                "\(model.chances.count) \(model.chances.count == 1 ? "chance" : "chances") to say hello"
                            )
                            .font(.subheadline.weight(.semibold)).foregroundStyle(MeadowPalette.secondaryInk)
                            ForEach(model.chances) { chance in chanceCard(chance) }
                        }
                        Text("Town visitors are decorative representations, not a live nearby-person list.")
                            .font(.caption).foregroundStyle(MeadowPalette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
                }
                .refreshable { await model.refresh() }
            }
            .background(MeadowPalette.grass.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ChatRoute.self) { route in
                ChatConversationView(chatID: route.id, session: session)
                    .onAppear { model.openedChat(route.id) }
            }
            .sheet(isPresented: $showingChats) { ChatsView(session: session) }
            .task(id: scenePhase) {
                guard scenePhase == .active else {
                    model.clearVisibleData()
                    return
                }
                await model.refresh()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                    await model.refresh()
                }
            }
            .onDisappear { model.clearVisibleData() }
            .alert(
                confirmation?.title ?? "Confirm",
                isPresented: Binding(
                    get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
                presenting: confirmation
            ) { action in
                Button(action.buttonTitle, role: .destructive) {
                    Task {
                        switch action {
                        case .decline(let id): await model.decide(id, decision: .declined)
                        case .block(let id): await model.block(id)
                        }
                    }
                }
                Button(action.isDecline ? "Keep chance" : "Cancel", role: .cancel) {}
            } message: { action in
                Text(action.message)
            }
        }
        .foregroundStyle(MeadowPalette.ink).fontDesign(.rounded)
        .connectionCelebrations(
            session.celebrations,
            available: path.isEmpty && !showingChats && confirmation == nil)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "arrow.left").font(.headline).frame(width: 44, height: 44)
                    .background(MeadowPalette.paper, in: Circle())
            }.accessibilityLabel("Close recently encountered").accessibilityIdentifier("encountersBack")
            Text("Recently Encountered").font(.headline).lineLimit(2)
                .accessibilityIdentifier("encountersTitle")
            Spacer(minLength: 0)
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise").font(.headline).frame(width: 44, height: 44)
                    .background(MeadowPalette.paper, in: Circle())
            }
            .disabled(model.loading || model.busyID != nil).accessibilityLabel("Refresh chances")
            .accessibilityIdentifier("encountersRefresh")
        }.buttonStyle(MeadowPressStyle()).padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "hand.wave.fill").font(.system(size: 24))
                .frame(width: 58, height: 58).background(
                    MeadowPalette.accent, in: RoundedRectangle(cornerRadius: 20)
                )
                .foregroundStyle(MeadowPalette.accentInk).rotationEffect(.degrees(-7)).accessibilityHidden(
                    true)
            Text("Some hellos\nstart small.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold)).tracking(-0.5)
            Text("See what you share, then choose. A private chat opens only when you both accept.")
                .font(.subheadline).foregroundStyle(MeadowPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showingChats = true
            } label: {
                Label("Your Conversations", systemImage: "bubble.left.and.bubble.right")
                    .font(.subheadline.weight(.bold)).frame(minHeight: 44)
            }.accessibilityIdentifier("encountersChats")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "leaf").font(.system(size: 32)).foregroundStyle(MeadowPalette.treeShade)
            Text("A new hello is ahead").font(.title3.weight(.bold)).accessibilityIdentifier(
                "encountersEmpty")
            Text(
                "No chances waiting right now. With discovery enabled and shared interests, new chances can appear here. They last up to 24 hours."
            )
            .font(.subheadline).foregroundStyle(MeadowPalette.secondaryInk).multilineTextAlignment(.center)
            Text("Already connected? You'll find your chats at the café.")
                .font(.footnote).foregroundStyle(MeadowPalette.secondaryInk).multilineTextAlignment(.center)
        }.padding(26).frame(maxWidth: .infinity).background(
            MeadowPalette.paper, in: RoundedRectangle(cornerRadius: 28))
    }

    private func readyCard(_ id: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("A mutual hello", systemImage: "checkmark.seal.fill").font(.headline)
            Text("You both accepted. Your private conversation is ready—no profile reveal required.")
                .font(.subheadline).foregroundStyle(MeadowPalette.secondaryInk)
            NavigationLink(value: ChatRoute(id: id)) {
                Label("Open conversation", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(MeadowPalette.accent, in: Capsule()).foregroundStyle(MeadowPalette.accentInk)
            }.buttonStyle(MeadowPressStyle()).accessibilityIdentifier("encounterOpenChat")
        }
        .padding(22).background(MeadowPalette.paper, in: RoundedRectangle(cornerRadius: 26))
        .accessibilityElement(children: .contain)
    }

    private func chanceCard(_ chance: TownConnection) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if let avatar = chance.avatar {
                        AvatarView(avatar: avatar, session: session, side: 48)
                    } else {
                        Image(systemName: "person.fill.questionmark").font(.system(size: 23))
                            .frame(width: 48, height: 48).background(
                                MeadowPalette.path, in: RoundedRectangle(cornerRadius: 17))
                    }
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("A little in common").font(.headline).accessibilityIdentifier("chance-\(chance.id)")
                    Text("Their name and answer stay private.").font(.caption).foregroundStyle(
                        MeadowPalette.secondaryInk)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if model.busyID == chance.id {
                    ProgressView().accessibilityLabel("Saving your answer")
                } else {
                    Menu {
                        Button("Block connection", systemImage: "hand.raised", role: .destructive) {
                            confirmation = .block(chance.id)
                        }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44)
                    }
                    .disabled(model.busyID != nil).accessibilityLabel("Chance options")
                    .accessibilityIdentifier("chanceOptions-\(chance.id)")
                }
            }
            if !chance.sharedInterests.isEmpty {
                ChipFlow(spacing: 8) {
                    ForEach(Array(chance.sharedInterests.enumerated()), id: \.offset) { _, interest in
                        Text(interest.capitalized).font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(MeadowPalette.field, in: Capsule())
                    }
                }
            } else {
                Text("No shared interests listed").font(.subheadline).foregroundStyle(
                    MeadowPalette.secondaryInk)
            }
            if let expiry = chance.expiryDate {
                Label(
                    "\(chance.you?.decision == .accepted ? "Waiting until" : "Answer by") \(expiry.formatted(date: .abbreviated, time: .shortened))",
                    systemImage: "clock"
                )
                .font(.caption).foregroundStyle(MeadowPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            }
            if chance.you?.decision == .accepted {
                VStack(alignment: .leading, spacing: 7) {
                    Label("You accepted", systemImage: "checkmark.circle.fill").font(
                        .subheadline.weight(.bold))
                    Text(
                        "Waiting for a mutual yes. We'll show a conversation here if you both accept before the chance closes."
                    )
                    .font(.footnote).foregroundStyle(MeadowPalette.secondaryInk)
                }.accessibilityIdentifier("waiting-\(chance.id)")
            } else if chance.you?.decision == .declined {
                Text("Your answer is saved. Refresh for the current status.").font(.footnote)
            } else if typeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    accept(chance)
                    decline(chance)
                }
            } else {
                HStack(spacing: 12) {
                    decline(chance)
                    accept(chance)
                }
            }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(MeadowPalette.paper, in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(MeadowPalette.glassEdge.opacity(0.5)))
    }
    private func accept(_ chance: TownConnection) -> some View {
        Button {
            Task { await model.decide(chance.id, decision: .accepted) }
        } label: {
            Label("Accept", systemImage: "checkmark").font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(MeadowPalette.accent, in: Capsule()).foregroundStyle(MeadowPalette.accentInk)
        }.buttonStyle(MeadowPressStyle()).disabled(model.busyID != nil)
            .opacity(model.busyID == nil ? 1 : 0.5).accessibilityIdentifier("accept-\(chance.id)")
    }
    private func decline(_ chance: TownConnection) -> some View {
        Button {
            confirmation = .decline(chance.id)
        } label: {
            Label("Decline", systemImage: "xmark").font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(MeadowPalette.field, in: Capsule())
        }.buttonStyle(MeadowPressStyle()).disabled(model.busyID != nil)
            .opacity(model.busyID == nil ? 1 : 0.5).accessibilityIdentifier("decline-\(chance.id)")
    }
}
