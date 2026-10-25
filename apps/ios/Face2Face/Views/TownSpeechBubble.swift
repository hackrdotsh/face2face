import Face2FaceCore
import SwiftUI

/// A friend's status above their head in the plaza. It comes and goes on its own timing.
struct TownSpeechBubble: View {
    let text: String
    let seed: String
    let time: TimeInterval
    /// The plaza clock stops with Reduce Motion, so the bubble stays up instead.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let maxWidth: CGFloat = 132
    private static let tailSize = CGSize(width: 10, height: 6)

    var body: some View {
        let visibility = reduceMotion ? 1 : CGFloat(TownStatusBubble.visibility(seed: seed, time: time))
        VStack(spacing: -1) {
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(MeadowPalette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.tail)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(MeadowPalette.paper, in: RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9).strokeBorder(MeadowPalette.accentShadow.opacity(0.55)))
            SpeechBubbleTail()
                .fill(MeadowPalette.paper)
                .frame(width: Self.tailSize.width, height: Self.tailSize.height)
        }
        .frame(width: Self.maxWidth, height: 44, alignment: .bottom)
        .opacity(visibility)
        .scaleEffect(0.85 + 0.15 * visibility, anchor: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SpeechBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
