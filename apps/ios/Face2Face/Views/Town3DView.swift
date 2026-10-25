import Face2FaceCore
import RealityKit
import SwiftUI

struct TownScene: View {
    var isMoving = true
    var visitors: [PublicTownFriend] = []
    var session: SessionModel?
    var onSelect: ((TownDestination) -> Void)?
    var onSelectFriend: ((PublicTownFriend) -> Void)?
    @AppStorage("forest3DEnabled") private var scenery3DEnabled = true

    var body: some View {
        Group {
            if #available(iOS 18.0, *), scenery3DEnabled {
                TownRealityScene(
                    isMoving: isMoving, visitors: visitors, session: session, onSelect: onSelect,
                    onSelectFriend: onSelectFriend)
            } else {
                TownCanvasScene(
                    isMoving: isMoving, visitors: visitors, session: session, onSelect: onSelect,
                    onSelectFriend: onSelectFriend)
            }
        }
    }
}

@available(iOS 18.0, *)
private struct TownRealityScene: View {
    let isMoving: Bool
    let visitors: [PublicTownFriend]
    let session: SessionModel?
    let onSelect: ((TownDestination) -> Void)?
    let onSelectFriend: ((PublicTownFriend) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var world: Town3DWorld?
    @State private var failed = false
    @State private var startedAt = Date()
    @State private var elapsed: TimeInterval = 0
    private var running: Bool { isMoving && !reduceMotion && scenePhase == .active }

    var body: some View {
        GeometryReader { geometry in
            if failed {
                TownCanvasScene(
                    isMoving: isMoving, visitors: visitors, session: session, onSelect: onSelect,
                    onSelectFriend: onSelectFriend)
            } else {
                let scale = min(geometry.size.width / 400, geometry.size.height / 640)
                let origin = CGPoint(
                    x: (geometry.size.width - 400 * scale) / 2, y: (geometry.size.height - 640 * scale) / 2)
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { timeline in
                    let time =
                        reduceMotion
                        ? 0 : elapsed + (running ? timeline.date.timeIntervalSince(startedAt) : 0)
                    ZStack(alignment: .topLeading) {
                        RealityView { content in
                            do {
                                let world = try Town3DWorld()
                                try world.updateVisitors(visitors)
                                world.configure(dark: colorScheme == .dark, viewport: geometry.size)
                                world.update(time: time)
                                content.camera = .virtual
                                content.add(world.root)
                                self.world = world
                            } catch {
                                print("3D town unavailable: \(error)")
                                failed = true
                            }
                        } update: { _ in
                            do {
                                try world?.updateVisitors(visitors)
                                world?.configure(dark: colorScheme == .dark, viewport: geometry.size)
                                world?.update(time: time)
                            } catch {
                                print("3D town unavailable: \(error)")
                                failed = true
                            }
                        } placeholder: {
                            TownCanvasScene(isMoving: false)
                        }
                        .realityViewCameraControls(.none)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                        .overlay(alignment: .top) {
                            LinearGradient(
                                colors: [MeadowPalette.grass, MeadowPalette.grass.opacity(0)],
                                startPoint: .top, endPoint: .bottom
                            )
                            .frame(height: 50)
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
                                            .padding(.horizontal, 12).padding(.vertical, 9)
                                            .background(MeadowPalette.paper.opacity(0.96), in: Capsule())
                                            .overlay(
                                                Capsule().strokeBorder(MeadowPalette.glassEdge.opacity(0.7))
                                            )
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
                        if let session, let onSelectFriend {
                            ForEach(Array(visitors.prefix(3).enumerated()), id: \.element.id) {
                                index, friend in
                                let pose = TownResidentMotion.pose(slot: index, time: time)
                                Button {
                                    onSelectFriend(friend)
                                } label: {
                                    VStack {
                                        HStack {
                                            Spacer()
                                            if friend.avatar.photo != nil {
                                                AvatarView(avatar: friend.avatar, session: session, side: 18)
                                                    .padding(2).background(MeadowPalette.paper, in: Circle())
                                            }
                                        }
                                        Spacer(minLength: 0)
                                        Text(
                                            friend.name.split(whereSeparator: \.isWhitespace).first.map(
                                                String.init) ?? friend.name
                                        )
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .lineLimit(1).padding(.horizontal, 7).padding(.vertical, 4)
                                        .background(MeadowPalette.paper.opacity(0.96), in: Capsule())
                                    }
                                    .frame(width: 76, height: 66)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .scaleEffect(scale)
                                .position(
                                    x: origin.x + pose.point.x * scale,
                                    y: origin.y + (pose.point.y - 4) * scale
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
        }
        .onChange(of: running) { old, new in
            if old { elapsed += Date().timeIntervalSince(startedAt) }
            if new { startedAt = Date() }
        }
    }
}
