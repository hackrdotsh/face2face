import Face2FaceCore
import SwiftUI

/// The signed-in front door. Public friend visitors are representations, not live presence.
struct TownView: View {
    let account: Account
    let session: SessionModel
    let passkeys: PasskeyAuthorizer
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var friends: TownFriendsModel
    @State private var publicConnections = PublicConnectionUpdates.shared
    @State private var inbox: NotificationsModel
    @State private var push = PushNotifications.shared
    @State private var cafeUnread = 0
    @State private var openedPreviewProfile = false
    @State private var openedLaunchRoutes = false
    @State private var destination: TownDestination?
    @State private var showingAccount = false
    @State private var showingSettings = false
    @State private var showingNotifications = false
    @State private var chatRoute: ChatRoute?
    @State private var queuedChat: ChatRoute?

    init(account: Account, session: SessionModel, passkeys: PasskeyAuthorizer) {
        self.account = account
        self.session = session
        self.passkeys = passkeys
        _friends = State(initialValue: TownFriendsModel(session: session))
        _inbox = State(initialValue: NotificationsModel(session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let error = friends.error, friends.selectedID == nil {
                HStack(spacing: 8) {
                    Text(error).font(.caption).accessibilityIdentifier("townFriendsError")
                    Button("Retry") { Task { await friends.refresh() } }.font(.caption.weight(.bold))
                        .accessibilityIdentifier("townFriendsRetry")
                }
                .foregroundStyle(MeadowPalette.secondaryInk)
                .padding(.horizontal, 24).padding(.vertical, 6)
            } else if !friends.visitors.isEmpty {
                Text(
                    friends.isPreview
                        ? "Preview · sample public friends" : "Public friends · tap a familiar face"
                )
                .font(.caption).foregroundStyle(MeadowPalette.secondaryInk)
                .padding(.horizontal, 24).padding(.bottom, 4)
            }
            if typeSize.isAccessibilitySize {
                ScrollView {
                    VStack(spacing: 12) {
                        TownScene(isMoving: false).frame(height: 320).accessibilityHidden(true)
                        ForEach(TownDestination.allCases) { place in placeRow(place) }
                        ForEach(friends.visitors) { friend in
                            Button {
                                friends.select(friend)
                            } label: {
                                HStack(spacing: 12) {
                                    AvatarView(avatar: friend.avatar, session: session, side: 40)
                                    Text(friend.name).font(.headline)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .padding(20).background(
                                    MeadowPalette.paper, in: RoundedRectangle(cornerRadius: 20))
                            }
                            .accessibilityLabel("\(friend.name), public friend")
                            .accessibilityValue(friend.statusMessage.map { "Status: \($0)" } ?? "")
                            .accessibilityIdentifier("town-friend-\(friend.id)")
                        }
                    }.padding(.horizontal, 20)
                }
            } else {
                TownScene(
                    isMoving: destination == nil && !showingAccount && !showingSettings
                        && !showingNotifications
                        && friends.selectedID == nil && chatRoute == nil,
                    visitors: friends.visitors, badges: [.connections: cafeUnread], session: session,
                    onSelect: { destination = $0 }, onSelectFriend: { friends.select($0) }
                )
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !typeSize.isAccessibilitySize {
                headerControls.padding(.trailing, 24).padding(.top, 12)
            }
        }
        .background(MeadowPalette.grass.ignoresSafeArea())
        .foregroundStyle(MeadowPalette.ink)
        .fontDesign(.rounded)
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .sheet(item: $destination) { place in
            TownDestinationView(destination: place, session: session)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(session: session)
        }
        .sheet(isPresented: $showingAccount) {
            NavigationStack {
                AccountView(account: account, session: session, passkeys: passkeys)
            }
        }
        .fullScreenCover(isPresented: $showingNotifications) {
            NotificationsView(session: session, model: inbox)
        }
        .fullScreenCover(item: $chatRoute) { route in
            NavigationStack { ChatConversationView(chatID: route.id, session: session) }
        }
        .sheet(
            isPresented: Binding(
                get: { friends.selectedID != nil },
                set: { if !$0 { friends.closeProfile() } }),
            onDismiss: {
                if let queuedChat {
                    chatRoute = queuedChat
                    self.queuedChat = nil
                }
            }
        ) {
            CompactPublicProfileView(
                model: friends, session: session,
                onMessage: { id in
                    queuedChat = ChatRoute(id: id)
                    friends.closeProfile()
                })
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else {
                friends.clearVisibleData()
                return
            }
            await friends.refresh(preferredConnectionID: publicConnections.latestID)
            #if DEBUG
                if !openedPreviewProfile, ProcessInfo.processInfo.arguments.contains("-town-friend-profile"),
                    let friend = friends.visitors.first
                {
                    openedPreviewProfile = true
                    friends.select(friend)
                }
            #endif
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                await friends.refresh(preferredConnectionID: publicConnections.latestID)
            }
        }
        .onDisappear {
            friends.clearVisibleData()
            friends.closeProfile()
        }
        .onChange(of: account.user.id) {
            friends.clearVisibleData()
            friends.closeProfile()
        }
        .onChange(of: publicConnections.revision) {
            Task { await friends.refresh(preferredConnectionID: publicConnections.latestID) }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await refreshBadges()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        .onChange(of: push.foregroundArrivals) { Task { await refreshBadges() } }
        .onChange(of: chatRoute == nil && destination == nil) { _, closed in
            if closed { Task { await refreshBadges() } }
        }
        .onChange(of: push.requestedChatID, initial: true) {
            guard let chatID = push.requestedChatID else { return }
            push.requestedChatID = nil
            Task { await openChat(chatID) }
        }
        .onChange(of: push.inboxRequested, initial: true) {
            guard push.inboxRequested else { return }
            push.inboxRequested = false
            showingNotifications = true
        }
        .task(id: account.user.id) {
            guard !session.isTownPreview else { return }
            await PushNotifications.shared.start(for: account, session: session)
            await ConnectedDiscoveryModel.backgroundWalk.restore(for: account)
        }
        #if DEBUG
            .onAppear {
                guard !openedLaunchRoutes else { return }
                openedLaunchRoutes = true
                if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-town-chat"),
                    ProcessInfo.processInfo.arguments.indices.contains(index + 1)
                {
                    chatRoute = ChatRoute(id: ProcessInfo.processInfo.arguments[index + 1])
                }
                if ProcessInfo.processInfo.arguments.contains("-town-notifications") {
                    showingNotifications = true
                }
                if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-town-destination"),
                    ProcessInfo.processInfo.arguments.indices.contains(index + 1)
                {
                    destination = TownDestination(rawValue: ProcessInfo.processInfo.arguments[index + 1])
                }
            }
        #endif
    }

    private func placeRow(_ place: TownDestination) -> some View {
        let unread = place == .connections ? cafeUnread : 0
        return Button {
            destination = place
        } label: {
            HStack {
                Label(place.title, systemImage: place.symbol)
                Spacer(minLength: 8)
                if unread > 0 { TownUnreadCount(count: unread) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(MeadowPalette.paper, in: RoundedRectangle(cornerRadius: 20))
        }
        .accessibilityValue(TownUnreadCount.spoken(unread))
        .accessibilityIdentifier("town-\(place.rawValue)")
    }

    private func refreshBadges() async {
        await inbox.refreshUnreadCount()
        if session.isTownPreview {
            cafeUnread = 1
            return
        }
        guard let chats = try? await session.client().chats() else { return }
        cafeUnread = chats.reduce(0) { $0 + $1.unreadCount }
    }

    /// Covers present one at a time, so anything already open closes before the chat opens.
    private func openChat(_ chatID: String) async {
        let covered = showingNotifications || destination != nil || chatRoute != nil
        showingNotifications = false
        destination = nil
        chatRoute = nil
        if covered { try? await Task.sleep(for: .milliseconds(500)) }
        chatRoute = ChatRoute(id: chatID)
    }

    /// The controls run down the trailing edge. Over the scene they float, so the town keeps its height;
    /// at accessibility sizes they sit beside the title instead of covering the list.
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("Your Little Town")
                .font(.system(.title, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 8)
            Spacer(minLength: 64)
            if typeSize.isAccessibilitySize { headerControls }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var headerControls: some View {
        VStack(spacing: 10) {
            Button {
                showingAccount = true
            } label: {
                AvatarView(avatar: account.user.avatar, session: session, side: 42)
                    .padding(5)
                    .background(MeadowPalette.paper.opacity(0.85), in: Circle())
                    .overlay(Circle().strokeBorder(MeadowPalette.glassEdge.opacity(0.8)))
            }
            .buttonStyle(MeadowPressStyle())
            .accessibilityLabel("Account")
            .accessibilityIdentifier("townAccount")
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(.headline, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(MeadowPalette.paper.opacity(0.85), in: Circle())
                    .overlay(Circle().strokeBorder(MeadowPalette.glassEdge.opacity(0.8)))
            }
            .buttonStyle(MeadowPressStyle())
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("appSettings")
            Button {
                showingNotifications = true
            } label: {
                Image(systemName: inbox.unreadCount > 0 ? "bell.fill" : "bell")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(MeadowPalette.paper.opacity(0.85), in: Circle())
                    .overlay(Circle().strokeBorder(MeadowPalette.glassEdge.opacity(0.8)))
                    .overlay(alignment: .topTrailing) {
                        if inbox.unreadCount > 0 {
                            TownUnreadCount(count: inbox.unreadCount).offset(x: 4, y: -4)
                        }
                    }
            }
            .buttonStyle(MeadowPressStyle())
            .accessibilityLabel("Notifications")
            .accessibilityValue(TownUnreadCount.spoken(inbox.unreadCount))
            .accessibilityIdentifier("townNotifications")
            DiscoveryButton(model: ConnectedDiscoveryModel.backgroundWalk, account: account) {
                showingAccount = true
            }
        }
    }
}

/// Turns discovery on or off with the same rules as the Account toggle.
private struct DiscoveryButton: View {
    @Bindable var model: ConnectedDiscoveryModel
    let account: Account
    let openAccount: () -> Void
    @State private var awaitsResult = false
    @State private var failure: String?

    private var isOn: Bool { model.isEnabled || model.isStarting }

    var body: some View {
        Button {
            if isOn {
                awaitsResult = false
                model.stop()
            } else {
                awaitsResult = true
                model.enable(for: account)
                // A failed save sets the message synchronously, maybe to its previous value.
                if !model.isEnabled, let message = model.errorMessage { report(message) }
            }
        } label: {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                DiscoveryBadge(state: model.discoveryState)
            }
        }
        .buttonStyle(MeadowPressStyle())
        .disabled((model.revocationPending && !model.isEnabled) || BluetoothDiscoveryService.isSimulator)
        .accessibilityHint("Turns discovery on or off")
        .accessibilityAddTraits(.isToggle)
        .accessibilityIdentifier("townDiscovery")
        .onChange(of: model.errorMessage) { _, message in
            if awaitsResult, let message { report(message) }
        }
        .onChange(of: model.discoveryState) { _, state in
            if state == .on { awaitsResult = false }
        }
        .alert(
            "Discovery could not start",
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }),
            presenting: failure
        ) { _ in
            Button("Open Account", action: openAccount)
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private func report(_ message: String) {
        awaitsResult = false
        failure = message
    }
}

private struct DiscoveryBadge: View {
    let state: ConnectedDiscoveryModel.DiscoveryState

    private var title: String {
        switch state {
        case .off: "Off"
        case .starting: "Starting"
        case .on: "On"
        case .paused: "Paused"
        }
    }

    private var symbol: String {
        switch state {
        case .off: "antenna.radiowaves.left.and.right.slash"
        case .starting, .on: "antenna.radiowaves.left.and.right"
        case .paused: "pause.circle"
        }
    }

    private var ink: Color {
        switch state {
        case .off: MeadowPalette.secondaryInk
        case .on: MeadowPalette.accentInk
        case .starting, .paused: MeadowPalette.ink
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(ink)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 44, height: 44)
            .background(
                state == .on ? MeadowPalette.accent : MeadowPalette.paper.opacity(0.85), in: Circle()
            )
            .overlay(Circle().strokeBorder(MeadowPalette.glassEdge.opacity(0.8)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Discovery")
            .accessibilityValue(title)
    }
}

enum TownDestination: String, CaseIterable, Identifiable {
    case encounters, connections, forums
    var id: String { rawValue }
    var title: String {
        switch self {
        case .encounters: "Recently Encountered"
        case .connections: "Connections"
        case .forums: "Forums"
        }
    }
    var symbol: String {
        switch self {
        case .encounters: "figure.walk"
        case .connections: "cup.and.saucer"
        case .forums: "pin"
        }
    }
    /// In the same 400 × 640 coordinate system as the artwork.
    var frame: CGRect {
        switch self {
        case .encounters: CGRect(x: 35, y: 84, width: 154, height: 180)
        case .connections: CGRect(x: 214, y: 251, width: 154, height: 183)
        case .forums: CGRect(x: 49, y: 441, width: 150, height: 126)
        }
    }
}

struct TownCanvasScene: View {
    var isMoving = true
    var visitors: [PublicTownFriend] = []
    var badges: [TownDestination: Int] = [:]
    var session: SessionModel?
    var onSelect: ((TownDestination) -> Void)?
    var onSelectFriend: ((PublicTownFriend) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var startedAt = Date()
    @State private var elapsed: TimeInterval = 0
    private var running: Bool { isMoving && !reduceMotion && scenePhase == .active }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 400, geometry.size.height / 640)
            let origin = CGPoint(
                x: (geometry.size.width - 400 * scale) / 2,
                y: (geometry.size.height - 640 * scale) / 2)
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { timeline in
                let time =
                    reduceMotion
                    ? 0 : elapsed + (running ? timeline.date.timeIntervalSince(startedAt) : 0)
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        let shore = origin.y + 590 * scale
                        context.fill(
                            Path(
                                CGRect(
                                    x: 0, y: shore, width: geometry.size.width,
                                    height: max(0, geometry.size.height - shore))),
                            with: .color(MeadowPalette.waterDeep))
                        var world = context
                        world.translateBy(x: origin.x, y: origin.y)
                        world.scaleBy(x: scale, y: scale)
                        let bottom = scale > 0 ? max(640, (geometry.size.height - origin.y) / scale) : 640
                        TownIllustration.draw(
                            context: world, time: time, friendCount: min(3, visitors.count),
                            waterBottom: bottom)
                    }
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                    if let onSelect {
                        ForEach(TownDestination.allCases) { place in
                            Button {
                                onSelect(place)
                            } label: {
                                VStack {
                                    Spacer(minLength: 0)
                                    TownPlaceLabel(title: place.title, unread: badges[place] ?? 0)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(MeadowPressStyle())
                            .frame(width: place.frame.width * scale, height: place.frame.height * scale)
                            .position(
                                x: origin.x + place.frame.midX * scale,
                                y: origin.y + place.frame.midY * scale
                            )
                            .accessibilityLabel(place.title)
                            .accessibilityValue(TownUnreadCount.spoken(badges[place] ?? 0))
                            .accessibilityHint("Opens \(place.title.lowercased())")
                            .accessibilityIdentifier("town-\(place.rawValue)")
                        }
                    }
                    if let session, let onSelectFriend {
                        ForEach(Array(visitors.prefix(3).enumerated()), id: \.element.id) { index, friend in
                            let pose = TownResidentMotion.pose(slot: index, time: time)
                            Button {
                                onSelectFriend(friend)
                            } label: {
                                TownFriendNPC(friend: friend, session: session, pose: pose, time: time)
                                    .scaleEffect(scale)
                                    .frame(width: max(44, 72 * scale), height: max(44, 64 * scale))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .position(
                                x: origin.x + pose.point.x * scale, y: origin.y + (pose.point.y + 8) * scale
                            )
                            .accessibilityLabel("\(friend.name), public friend")
                            .accessibilityHint(
                                "Opens their public profile. Not live location or online status."
                            )
                            .accessibilityIdentifier("town-friend-\(friend.id)")
                        }
                    }
                }
            }
        }
        .onChange(of: running) { old, new in
            if old { elapsed += Date().timeIntervalSince(startedAt) }
            if new { startedAt = Date() }
        }
    }
}

/// A small count pill for unseen notifications or unread messages.
struct TownUnreadCount: View {
    let count: Int

    static func spoken(_ count: Int) -> String {
        switch count {
        case 0: ""
        case 1: "1 new"
        default: "\(count) new"
        }
    }

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(MeadowPalette.paper)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20)
            .background(MeadowPalette.errorInk, in: Capsule())
            .overlay(Capsule().strokeBorder(MeadowPalette.paper, lineWidth: 2))
            .accessibilityHidden(true)
    }
}

/// The name tag over a town place, with an unread count when there is one.
struct TownPlaceLabel: View {
    let title: String
    var unread = 0

    var body: some View {
        Text(title)
            .font(.system(.caption, design: .rounded, weight: .bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(MeadowPalette.paper.opacity(0.96), in: Capsule())
            .overlay(Capsule().strokeBorder(MeadowPalette.glassEdge.opacity(0.7)))
            .overlay(alignment: .topTrailing) {
                if unread > 0 { TownUnreadCount(count: unread).offset(x: 6, y: -8) }
            }
            .fixedSize(horizontal: true, vertical: false)
    }
}
