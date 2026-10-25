import Face2FaceCore
import SwiftUI

struct TownResidentPose {
    let point: CGPoint
    let facingForward: Bool
    let standing: Bool
}

/// Shared by scenery and interactive residents, so drawings and hit targets stay aligned.
enum TownResidentMotion {
    static func pose(slot: Int, time: TimeInterval) -> TownResidentPose {
        let routes: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 199, y: 106), CGPoint(x: 199, y: 184)),
            (CGPoint(x: 362, y: 309), CGPoint(x: 362, y: 369)),
            (CGPoint(x: 199, y: 454), CGPoint(x: 199, y: 503)),
        ]
        let index = min(max(0, slot), routes.count - 1)
        let route = routes[index]
        let safeTime = time.isFinite ? max(0, time) : 0
        let phase = (safeTime / (12 + Double(index) * 3) + Double(index) * 0.27)
            .truncatingRemainder(dividingBy: 2)
        let progress = min(1, max(0, phase < 1 ? phase * 1.2 : (2 - phase) * 1.2))
        return TownResidentPose(
            point: CGPoint(
                x: route.0.x + (route.1.x - route.0.x) * progress,
                y: route.0.y + (route.1.y - route.0.y) * progress),
            facingForward: phase < 1,
            standing: progress == 0 || progress == 1)
    }
}

struct TownFriendNPC: View {
    let friend: PublicTownFriend
    let session: SessionModel
    let pose: TownResidentPose
    let time: TimeInterval

    var body: some View {
        ZStack(alignment: .topLeading) {
            Ellipse().fill(MeadowPalette.ink.opacity(0.1)).frame(width: 28, height: 6)
                .position(x: 36, y: 39)
            let play = BlobPlayMotion(seed: friend.avatar.seed).pose(at: time)
            BlobGlyph(
                seed: friend.avatar.seed, pose: BlobIdleMotion(seed: friend.avatar.seed)?.pose(at: time)
            )
            .frame(width: 44, height: 44)
            .scaleEffect(x: play.xScale, y: play.yScale)
            .rotationEffect(.degrees(play.tilt))
            .offset(y: -play.lift * 44)
            .position(x: 36, y: 21)
            Text(friend.name.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? friend.name)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(MeadowPalette.ink)
                .lineLimit(1)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(MeadowPalette.paper.opacity(0.96), in: Capsule())
                .overlay(Capsule().strokeBorder(MeadowPalette.accentShadow.opacity(0.55)))
                .frame(maxWidth: 72)
                .position(x: 36, y: 49)
            if let statusMessage = friend.statusMessage {
                TownSpeechBubble(text: statusMessage, seed: friend.userId, time: time)
                    .position(x: 36, y: -24)
            }
        }
        .frame(width: 72, height: 64)
        .accessibilityHidden(true)
    }
}
