import Face2FaceCore
import SwiftUI

/// Friends are symbolic seats, never live attendance or location. Widgets pass a fixed time.
struct CampfireScene: View {
    let ownSeed: String
    let guests: [CampfireGuest]
    var time: Double = 0
    var showsNames = true

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let seats = [CampfireGuest(id: -1, name: "You", seed: ownSeed, isAnonymous: false)] + guests
            let side = min(42.0, max(22, size.width / (guests.count > 6 ? 9 : 7)))
            ZStack {
                Canvas { context, size in
                    let center = CGPoint(x: size.width * 0.5, y: size.height * 0.56)
                    context.fill(
                        Path(
                            ellipseIn: CGRect(
                                x: center.x - size.width * 0.38, y: center.y - size.height * 0.3,
                                width: size.width * 0.76, height: size.height * 0.64)),
                        with: .radialGradient(
                            Gradient(colors: [.orange.opacity(0.23), .clear]), center: center, startRadius: 0,
                            endRadius: size.width * 0.36))
                    for index in 0..<18 {
                        let x = Double((index * 47 + 13) % 97) / 100 * size.width
                        let y = Double((index * 23 + 3) % 29) / 100 * size.height
                        context.fill(
                            Path(
                                ellipseIn: CGRect(
                                    x: x, y: y, width: index.isMultiple(of: 3) ? 2 : 1,
                                    height: index.isMultiple(of: 3) ? 2 : 1)),
                            with: .color(.white.opacity(0.3 + 0.15 * sin(time + Double(index)))))
                    }
                    for index in 0..<8 {
                        let x = Double(index) / 7 * size.width
                        let h = size.height * (0.18 + Double(index % 3) * 0.05)
                        var tree = Path()
                        tree.move(to: CGPoint(x: x, y: size.height * 0.94 - h))
                        tree.addLine(to: CGPoint(x: x - h * 0.35, y: size.height * 0.94))
                        tree.addLine(to: CGPoint(x: x + h * 0.35, y: size.height * 0.94))
                        tree.closeSubpath()
                        context.fill(tree, with: .color(Color(red: 0.07, green: 0.19, blue: 0.19)))
                    }
                }
                ZStack {
                    Capsule().fill(Color(red: 0.45, green: 0.24, blue: 0.15)).frame(width: 34, height: 7)
                        .rotationEffect(.degrees(22)).offset(y: 16)
                    Capsule().fill(Color(red: 0.62, green: 0.33, blue: 0.19)).frame(width: 34, height: 7)
                        .rotationEffect(.degrees(-22)).offset(y: 16)
                    FlameShape().fill(
                        LinearGradient(
                            colors: [.yellow, .orange, .red.opacity(0.85)], startPoint: .bottom,
                            endPoint: .top)
                    )
                    .frame(width: 25, height: 38).scaleEffect(
                        x: 1 + 0.06 * sin(time * 4), y: 1 + 0.08 * cos(time * 5), anchor: .bottom)
                    FlameShape().fill(Color(red: 1, green: 0.92, blue: 0.62)).frame(width: 11, height: 22)
                        .offset(y: 8)
                }
                .position(x: size.width * 0.5, y: size.height * 0.57)
                ForEach(Array(seats.enumerated()), id: \.element.id) { index, guest in
                    let angle = Double(index) / Double(seats.count) * 2 * .pi + .pi / 2
                    let play = BlobPlayMotion(seed: guest.seed).pose(at: time)
                    VStack(spacing: 0) {
                        BlobGlyph(
                            seed: guest.seed,
                            pose: time == 0 ? nil : BlobIdleMotion(seed: guest.seed)?.pose(at: time)
                        )
                        .frame(width: side, height: side)
                        .scaleEffect(x: time == 0 ? 1 : play.xScale, y: time == 0 ? 1 : play.yScale)
                        .rotationEffect(.degrees(time == 0 ? 0 : play.tilt))
                        .offset(y: time == 0 ? 0 : -play.lift * side)
                        if showsNames {
                            Text(
                                guest.isAnonymous
                                    ? "Friend"
                                    : guest.name.split(separator: " ").first.map(String.init) ?? guest.name
                            )
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8)).lineLimit(1).frame(width: side + 16)
                        }
                    }
                    .position(
                        x: size.width * (0.5 + 0.36 * cos(angle)), y: size.height * (0.49 + 0.32 * sin(angle))
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct FlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.43, y: rect.minY),
            control1: CGPoint(x: -rect.width * 0.3, y: rect.height * 0.78),
            control2: CGPoint(x: rect.width * 0.18, y: rect.height * 0.42))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.72, y: rect.height * 0.45),
            control1: CGPoint(x: rect.width * 0.92, y: rect.height * 0.12),
            control2: CGPoint(x: rect.width * 0.43, y: rect.height * 0.47))
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.width * 1.4, y: rect.height * 0.45),
            control2: CGPoint(x: rect.width * 1.1, y: rect.height * 0.95))
        path.closeSubpath()
        return path
    }
}
