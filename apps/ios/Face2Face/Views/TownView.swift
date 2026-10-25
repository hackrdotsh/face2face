import Face2FaceCore
import SwiftUI

/// The signed-in front door. The people in the scenery are decorative, not live encounters.
struct TownView: View {
    let account: Account
    let session: SessionModel
    let passkeys: PasskeyAuthorizer
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var destination: TownDestination?
    @State private var showingAccount = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if typeSize.isAccessibilitySize {
                ScrollView {
                    VStack(spacing: 12) {
                        TownScene(isMoving: false).frame(height: 320).accessibilityHidden(true)
                        ForEach(TownDestination.allCases) { place in
                            Button {
                                destination = place
                            } label: {
                                Label(place.title, systemImage: place.symbol)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(20)
                                    .background(MeadowPalette.paper, in: RoundedRectangle(cornerRadius: 20))
                            }
                            .accessibilityIdentifier("town-\(place.rawValue)")
                        }
                    }.padding(.horizontal, 20)
                }
            } else {
                TownScene(isMoving: destination == nil && !showingAccount) { place in destination = place }
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
        .sheet(isPresented: $showingAccount) {
            NavigationStack {
                HomeView(account: account, session: session, passkeys: passkeys)
                    .navigationTitle("Account")
                    .toolbar {
                        #if DEBUG
                            ToolbarItem(placement: .topBarLeading) {
                                Menu {
                                    NavigationLink("Walk test") {
                                        WalkDiscoveryView(model: ConnectedDiscoveryModel.backgroundWalk)
                                    }
                                    NavigationLink("Connected test") { ConnectedDiscoveryView() }
                                    NavigationLink("Pocket test") {
                                        PocketDiscoveryView(model: PocketDiscoveryModel.shared)
                                    }
                                    NavigationLink("Device test") { DiscoveryDiagnosticView() }
                                } label: {
                                    Label("Developer tools", systemImage: "hammer")
                                }
                            }
                        #endif
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingAccount = false }
                        }
                    }
            }
        }
        #if DEBUG
            .onAppear {
                if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-town-destination"),
                    ProcessInfo.processInfo.arguments.indices.contains(index + 1)
                {
                    destination = TownDestination(rawValue: ProcessInfo.processInfo.arguments[index + 1])
                }
            }
        #endif
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("FACE2FACE")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(MeadowPalette.secondaryInk)
                Text("Your little town")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            Button {
                showingAccount = true
            } label: {
                AvatarView(avatar: account.user.avatar, session: session, side: 42)
                    .padding(5)
                    .background(MeadowPalette.paper.opacity(0.85), in: Circle())
                    .overlay(Circle().strokeBorder(MeadowPalette.glassEdge.opacity(0.8)))
            }
            .accessibilityLabel("Account and settings")
            .accessibilityIdentifier("townAccount")
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

enum TownDestination: String, CaseIterable, Identifiable {
    case encounters, connections, forums
    var id: String { rawValue }
    var title: String {
        switch self {
        case .encounters: "Recently encountered"
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

struct TownScene: View {
    var isMoving = true
    var onSelect: ((TownDestination) -> Void)?
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
            ZStack(alignment: .topLeading) {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { timeline in
                    let time =
                        reduceMotion
                        ? 0 : elapsed + (running ? timeline.date.timeIntervalSince(startedAt) : 0)
                    Canvas { context, _ in
                        var world = context
                        world.translateBy(x: origin.x, y: origin.y)
                        world.scaleBy(x: scale, y: scale)
                        TownIllustration.draw(context: world, time: time)
                    }
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                }
                if let onSelect {
                    ForEach(TownDestination.allCases) { place in
                        Button {
                            onSelect(place)
                        } label: {
                            VStack {
                                Spacer(minLength: 0)
                                Text(place.title)
                                    .font(.system(.caption, design: .rounded, weight: .bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(MeadowPalette.paper.opacity(0.96), in: Capsule())
                                    .overlay(Capsule().strokeBorder(MeadowPalette.glassEdge.opacity(0.7)))
                                    .fixedSize(horizontal: true, vertical: false)
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
                        .accessibilityHint("Opens \(place.title.lowercased())")
                        .accessibilityIdentifier("town-\(place.rawValue)")
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
