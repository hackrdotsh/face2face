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
        } else if let blob = BlobAvatar(seed: avatar.seed) {
            BlobAvatarView(blob: blob)
        } else {
            Circle().fill(.secondary.opacity(0.15))
        }
    }
}

struct BlobAvatarView: View {
    let blob: BlobAvatar

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let point = { (point: BlobAvatar.Point) in CGPoint(x: point.x * side, y: point.y * side) }
            var outline = Path()
            outline.move(to: point(blob.start))
            for curve in blob.curves {
                outline.addCurve(
                    to: point(curve.end), control1: point(curve.control1), control2: point(curve.control2))
            }
            outline.closeSubpath()
            context.fill(
                outline,
                with: .linearGradient(
                    Gradient(colors: blob.fill.map(Color.init(hsl:))), startPoint: .zero,
                    endPoint: CGPoint(x: side, y: side)))
            for eye in blob.eyes {
                let rect = CGRect(
                    x: eye.x * side, y: eye.y * side, width: eye.width * side, height: eye.height * side)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: rect.width / 2),
                    with: .color(Color(hsl: blob.eyeColor)))
            }
        }
    }
}

extension Color {
    init(hsl: BlobAvatar.HSL) {
        let rgb = hsl.rgb
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
