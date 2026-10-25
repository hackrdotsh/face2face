import Face2FaceCore
import SwiftUI

/// The person's photo as a circle, or their blob when there is none. Decorative.
struct AvatarView: View {
    let avatar: Avatar
    let session: SessionModel
    var side: CGFloat = 40

    var body: some View {
        content
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        if let photo = avatar.photo {
            AsyncImage(url: session.mediaURL(for: side > 128 ? photo.large : photo.thumb)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.secondary.opacity(0.15)
            }
            .clipShape(Circle())
        } else if let blob = BlobAvatar(seed: avatar.seed), let motion = BlobIdleMotion(seed: avatar.seed) {
            BlobAvatarView(blob: blob, motion: motion)
        } else {
            Circle().fill(.secondary.opacity(0.15))
        }
    }
}

struct BlobAvatarView: View {
    let blob: BlobAvatar
    let motion: BlobIdleMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)) {
            timeline in
            let pose = reduceMotion ? nil : motion.pose(at: timeline.date.timeIntervalSinceReferenceDate)
            Canvas { context, size in draw(in: &context, side: min(size.width, size.height), pose: pose) }
        }
    }

    private func draw(in context: inout GraphicsContext, side: CGFloat, pose: BlobIdleMotion.Pose?) {
        let shape = pose.map { blob.outline(breath: $0.breath) } ?? (start: blob.start, curves: blob.curves)
        let point = { (point: BlobAvatar.Point) in CGPoint(x: point.x * side, y: point.y * side) }
        var outline = Path()
        outline.move(to: point(shape.start))
        for curve in shape.curves {
            outline.addCurve(
                to: point(curve.end), control1: point(curve.control1), control2: point(curve.control2))
        }
        outline.closeSubpath()
        context.fill(
            outline,
            with: .linearGradient(
                Gradient(colors: blob.fill.map(Color.init(hsl:))), startPoint: .zero,
                endPoint: CGPoint(x: side, y: side)))
        let gaze = pose?.gaze ?? 0
        let openness = pose?.eyeOpenness ?? 1
        for eye in blob.eyes {
            let height = eye.height * openness
            let rect = CGRect(
                x: (eye.x + gaze) * side, y: (eye.y + (eye.height - height) / 2) * side,
                width: eye.width * side, height: height * side)
            context.fill(
                Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2),
                with: .color(Color(hsl: blob.eyeColor)))
        }
    }
}

extension Color {
    init(hsl: BlobAvatar.HSL) {
        let rgb = hsl.rgb
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
