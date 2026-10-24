import SwiftUI

/// A repeating, top-down meadow. Only the scenery moves; the form stays still.
struct MeadowScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var startedAt = Date()
    @State private var elapsed: TimeInterval = 0
    var isMoving: Bool

    private let tileHeight: CGFloat = 640
    private var running: Bool { isMoving && !reduceMotion && scenePhase == .active }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { timeline in
            let time = elapsed + (running ? timeline.date.timeIntervalSince(startedAt) : 0)
            Canvas { context, size in
                drawMeadow(context: context, size: size, distance: time * 12)
            }
        }
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [MeadowPalette.grass, MeadowPalette.grass.opacity(0)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 270)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: running) { oldValue, newValue in
            if oldValue { elapsed += Date().timeIntervalSince(startedAt) }
            if newValue { startedAt = Date() }
        }
    }

    private func drawMeadow(context: GraphicsContext, size: CGSize, distance: Double) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(MeadowPalette.grass))
        let offset = CGFloat(distance.truncatingRemainder(dividingBy: Double(tileHeight)))
        let tileCount = Int(ceil(size.height / tileHeight)) + 1
        for tile in -1..<tileCount {
            let origin = CGFloat(tile) * tileHeight + offset
            drawPath(context: context, width: size.width, origin: origin, height: tileHeight)
        }
        for tile in -1..<tileCount {
            let origin = CGFloat(tile) * tileHeight + offset
            drawPlants(context: context, size: size, origin: origin)
        }
    }

    private func drawPath(context: GraphicsContext, width: CGFloat, origin: CGFloat, height: CGFloat) {
        var path = Path()
        let center = width / 2
        path.move(to: CGPoint(x: center, y: origin))
        path.addCurve(
            to: CGPoint(x: center, y: origin + height / 2),
            control1: CGPoint(x: center + 120, y: origin + height / 6),
            control2: CGPoint(x: center + 120, y: origin + height / 3))
        path.addCurve(
            to: CGPoint(x: center, y: origin + height),
            control1: CGPoint(x: center - 120, y: origin + height * 2 / 3),
            control2: CGPoint(x: center - 120, y: origin + height * 5 / 6))
        context.stroke(path, with: .color(MeadowPalette.pathEdge), style: StrokeStyle(lineWidth: 94))
        context.stroke(path, with: .color(MeadowPalette.path), style: StrokeStyle(lineWidth: 86))
    }

    private func drawPlants(context: GraphicsContext, size: CGSize, origin: CGFloat) {
        // Two staggered rows of trees on each bank keep the winding path open.
        for row in 0..<8 {
            for column in 0..<4 {
                let index = row * 4 + column
                let localY = CGFloat(row) * tileHeight / 8 + CGFloat((index * 29) % 37) + 12
                let bank: CGFloat = column.isMultiple(of: 2) ? -1 : 1
                let depth = CGFloat(column / 2)
                let distance = 96 + depth * 64 + CGFloat((row * 13 + column * 7) % 18)
                let point = CGPoint(
                    x: pathCenter(at: localY, width: size.width) + bank * distance,
                    y: origin + localY)
                guard point.x > -60, point.x < size.width + 60,
                    point.y > -80, point.y < size.height + 80
                else { continue }
                drawTree(
                    context: context, at: point,
                    scale: 0.64 + CGFloat((index * 7) % 6) * 0.07,
                    light: index.isMultiple(of: 3))
            }
        }
        for index in 0..<14 {
            let left = index.isMultiple(of: 2)
            let x = size.width * (left ? 0.2 : 0.8) + CGFloat((index * 17) % 43 - 21)
            let y = origin + CGFloat(index * 47)
            var grass = Path()
            grass.move(to: CGPoint(x: x - 4, y: y + 3))
            grass.addLine(to: CGPoint(x: x - 6, y: y - 2))
            grass.move(to: CGPoint(x: x, y: y + 3))
            grass.addLine(to: CGPoint(x: x + 2, y: y - 4))
            context.stroke(
                grass, with: .color(MeadowPalette.grassDetail),
                style: StrokeStyle(lineWidth: 2, lineCap: .round))
            if index.isMultiple(of: 3) {
                drawFlower(context: context, at: CGPoint(x: x + 12, y: y + 22))
            }
        }
    }

    private func pathCenter(at y: CGFloat, width: CGFloat) -> CGFloat {
        let half = tileHeight / 2
        let progress = y.truncatingRemainder(dividingBy: half) / half
        let bend: CGFloat = y < half ? 360 : -360
        return width / 2 + bend * progress * (1 - progress)
    }

    private func drawTree(context: GraphicsContext, at point: CGPoint, scale: CGFloat, light: Bool) {
        var context = context
        context.translateBy(x: point.x, y: point.y)
        context.scaleBy(x: scale, y: scale)
        context.fill(
            Path(ellipseIn: CGRect(x: -27, y: 32, width: 72, height: 24)),
            with: .color(MeadowPalette.treeShade.opacity(0.14)))
        context.fill(
            Path(roundedRect: CGRect(x: -5, y: 12, width: 10, height: 32), cornerRadius: 4),
            with: .color(MeadowPalette.trunk))
        var crown = Path()
        crown.move(to: CGPoint(x: -28, y: 20))
        crown.addCurve(
            to: CGPoint(x: -30, y: -19), control1: CGPoint(x: -52, y: 17),
            control2: CGPoint(x: -50, y: -12))
        crown.addCurve(
            to: CGPoint(x: 8, y: -45), control1: CGPoint(x: -32, y: -48),
            control2: CGPoint(x: -4, y: -57))
        crown.addCurve(
            to: CGPoint(x: 34, y: -14), control1: CGPoint(x: 31, y: -51),
            control2: CGPoint(x: 48, y: -29))
        crown.addCurve(
            to: CGPoint(x: 20, y: 25), control1: CGPoint(x: 57, y: 4),
            control2: CGPoint(x: 42, y: 32))
        crown.addQuadCurve(to: CGPoint(x: -28, y: 20), control: CGPoint(x: -3, y: 40))
        context.fill(crown, with: .color(MeadowPalette.treeShade))
        context.translateBy(x: -3, y: -7)
        context.fill(crown, with: .color(light ? MeadowPalette.treeLight : MeadowPalette.tree))
        context.fill(
            Path(ellipseIn: CGRect(x: -23, y: -33, width: 17, height: 10)),
            with: .color(MeadowPalette.paper.opacity(0.22)))
    }

    private func drawFlower(context: GraphicsContext, at point: CGPoint) {
        for petal in 0..<5 {
            let angle = Double(petal) * .pi * 2 / 5
            let rect = CGRect(
                x: point.x + cos(angle) * 4 - 3, y: point.y + sin(angle) * 4 - 3,
                width: 6, height: 6)
            context.fill(Path(ellipseIn: rect), with: .color(MeadowPalette.flower))
        }
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)),
            with: .color(MeadowPalette.flowerCenter))
    }

}
