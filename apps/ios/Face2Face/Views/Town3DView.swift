import Face2FaceCore
import RealityKit
import SwiftUI

struct TownScene: View {
    var isMoving = true
    var visitors: [PublicTownFriend] = []
    var badges: [TownDestination: Int] = [:]
    var session: SessionModel?
    var onSelect: ((TownDestination) -> Void)?
    var onSelectFriend: ((PublicTownFriend) -> Void)?
    @AppStorage("forest3DEnabled") private var scenery3DEnabled = true

    var body: some View {
        Group {
            if #available(iOS 18.0, *), scenery3DEnabled {
                TownRealityScene(
                    isMoving: isMoving, visitors: visitors, badges: badges, session: session,
                    onSelect: onSelect,
                    onSelectFriend: onSelectFriend)
            } else {
                TownCanvasScene(
                    isMoving: isMoving, visitors: visitors, badges: badges, session: session,
                    onSelect: onSelect,
                    onSelectFriend: onSelectFriend)
            }
        }
    }
}

@available(iOS 18.0, *)
private struct TownRealityScene: View {
    let isMoving: Bool
    let visitors: [PublicTownFriend]
    let badges: [TownDestination: Int]
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
                    isMoving: isMoving, visitors: visitors, badges: badges, session: session,
                    onSelect: onSelect,
                    onSelectFriend: onSelectFriend)
            } else {
                let scale = min(geometry.size.width / 400, geometry.size.height / 640)
                let origin = CGPoint(
                    x: (geometry.size.width - 400 * scale) / 2, y: (geometry.size.height - 640 * scale) / 2)
                ZStack(alignment: .topLeading) {
                    RealityView { content in
                        do {
                            let world = try Town3DWorld()
                            try world.updateVisitors(visitors)
                            world.configure(dark: colorScheme == .dark, viewport: geometry.size)
                            world.update(time: sceneTime(at: Date()))
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
                            world?.update(time: sceneTime(at: Date()))
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
                            let frame = TownPlazaLayout.frame(for: place)
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
                            .frame(width: frame.width * scale, height: frame.height * scale)
                            .position(
                                x: origin.x + frame.midX * scale,
                                y: origin.y + frame.midY * scale
                            )
                            .accessibilityLabel(place.title)
                            .accessibilityValue(TownUnreadCount.spoken(badges[place] ?? 0))
                            .accessibilityHint("Opens \(place.title.lowercased())")
                            .accessibilityIdentifier("town-\(place.rawValue)")
                        }
                    }
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { timeline in
                        let time = sceneTime(at: timeline.date)
                        ZStack(alignment: .topLeading) {
                            if session != nil, let onSelectFriend, !visitors.isEmpty {
                                ForEach(Array(visitors.prefix(3).enumerated()), id: \.element.id) {
                                    index, friend in
                                    let pose = TownPlazaLayout.resident(slot: index, time: time)
                                    Button {
                                        onSelectFriend(friend)
                                    } label: {
                                        VStack {
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
                                        .overlay(alignment: .top) {
                                            if let statusMessage = friend.statusMessage {
                                                TownSpeechBubble(
                                                    text: statusMessage, seed: friend.userId, time: time
                                                )
                                                .offset(y: -44)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .scaleEffect(scale)
                                    .position(
                                        x: origin.x + pose.point.x * scale,
                                        y: origin.y + (pose.point.y - 4) * scale
                                    )
                                    .accessibilityLabel("\(friend.name), public friend")
                                    .accessibilityValue(friend.statusMessage.map { "Status: \($0)" } ?? "")
                                    .accessibilityHint(
                                        "Opens their public profile. Not live location or online status."
                                    )
                                    .accessibilityIdentifier("town-friend-\(friend.id)")
                                }
                            }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .onChange(of: time, initial: true) { _, time in world?.update(time: time) }
                    }
                }
            }
        }
        .onChange(of: running) { old, new in
            if old { elapsed += Date().timeIntervalSince(startedAt) }
            if new { startedAt = Date() }
        }
    }

    private func sceneTime(at date: Date) -> TimeInterval {
        reduceMotion ? 0 : elapsed + (running ? date.timeIntervalSince(startedAt) : 0)
    }
}
