import Face2FaceCore
import SwiftUI

/// Always a seeded blob. Existing server photos are not deleted or downloaded by this view.
struct AvatarView: View {
    let avatar: Avatar
    let session: SessionModel
    var side: CGFloat = 40

    var body: some View {
        AnimatedBlobView(seed: avatar.seed)
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

struct AnimatedBlobView: View {
    let seed: String
    var reaction = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active))
            { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let reduced = reduceMotion
                let play = BlobPlayMotion(seed: seed).pose(at: time, reducedMotion: reduced)
                BlobGlyph(seed: seed, pose: reduced ? nil : BlobIdleMotion(seed: seed)?.pose(at: time))
                    .scaleEffect(x: play.xScale, y: play.yScale, anchor: .bottom)
                    .rotationEffect(.degrees(play.tilt), anchor: .bottom)
                    .offset(y: -height * play.lift)
                    .keyframeAnimator(initialValue: CGFloat.zero, trigger: reaction) { content, value in
                        content.offset(y: reduced ? 0 : -value * height)
                            .rotationEffect(.degrees(reduced ? 0 : Double(value) * 30))
                    } keyframes: { _ in
                        SpringKeyframe(0.23, duration: 0.2, spring: .bouncy)
                        SpringKeyframe(0, duration: 0.65, spring: .bouncy)
                    }
            }
        }
        .accessibilityHidden(true)
    }
}

struct BlobPortrait: View {
    let seed: String
    var prominent = false
    @State private var hello = 0

    var body: some View {
        VStack(spacing: 12) {
            Button {
                hello += 1
            } label: {
                ZStack {
                    Circle().fill(MeadowPalette.accent.opacity(0.35))
                    Circle().strokeBorder(
                        MeadowPalette.glassEdge, style: StrokeStyle(lineWidth: 1, dash: [4, 6])
                    )
                    .padding(8)
                    AnimatedBlobView(seed: seed, reaction: hello).padding(16)
                }
                .frame(width: prominent ? 164 : 124, height: prominent ? 164 : 124)
            }
            .buttonStyle(MeadowPressStyle())
            .accessibilityLabel("Say hello to your blob")
            .accessibilityHint("Your blob does a little happy jump")
            .accessibilityIdentifier("profileBlob")
            Text("A little you. A lot of personality.")
                .font(.subheadline.weight(.semibold))
            Text("Tap your blob to say hello.")
                .font(.caption).foregroundStyle(MeadowPalette.secondaryInk)
        }
        .frame(maxWidth: .infinity)
    }
}
