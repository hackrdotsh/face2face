import Face2FaceCore
import SwiftUI

/// Snapshot-safe artwork for widgets and Live Activities; animation clocks belong to the app.
struct BlobGlyph: View {
    let seed: String
    var pose: BlobIdleMotion.Pose?

    var body: some View {
        Canvas { context, size in
            let blob = BlobAvatar(seed: seed) ?? BlobAvatar(seed: [0])
            let side = min(size.width, size.height)
            context.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
            let shape = pose.map { blob.outline(breath: $0.breath) } ?? (blob.start, blob.curves)
            let point = { (point: BlobAvatar.Point) in CGPoint(x: point.x * side, y: point.y * side) }
            var outline = Path()
            outline.move(to: point(shape.0))
            for curve in shape.1 {
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
                let height = eye.height * (pose?.eyeOpenness ?? 1)
                let rect = CGRect(
                    x: (eye.x + (pose?.gaze ?? 0)) * side,
                    y: (eye.y + (eye.height - height) / 2) * side,
                    width: eye.width * side, height: height * side)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2),
                    with: .color(Color(hsl: blob.eyeColor)))
            }
        }
        .accessibilityHidden(true)
    }
}

extension Color {
    init(hsl: BlobAvatar.HSL) {
        let rgb = hsl.rgb
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
