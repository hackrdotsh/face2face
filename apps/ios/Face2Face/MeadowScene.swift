import SwiftUI

/// A decorative walking scene. Greetings are animation, not recorded encounters.
struct MeadowScene: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var startedAt = Date()
    @State private var elapsed: TimeInterval = 0
    var isMoving: Bool

    private let tileHeight: CGFloat = 640
    private let walkingSpeed: CGFloat = 24
    private var running: Bool { isMoving && !reduceMotion && scenePhase == .active }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { timeline in
            let time = elapsed + (running ? timeline.date.timeIntervalSince(startedAt) : 0)
            Canvas { context, size in
                drawMeadow(context: context, size: size, time: time)
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

    private func drawMeadow(context: GraphicsContext, size: CGSize, time: TimeInterval) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(MeadowPalette.grass))
        let distance = time * Double(walkingSpeed)
        let offset = CGFloat(distance.truncatingRemainder(dividingBy: Double(tileHeight)))
        let playerY = min(460, size.height * 0.5)
        let cameraOffset = size.width / 2 - pathCenter(at: playerY - offset, width: size.width)
        var world = context
        world.translateBy(x: cameraOffset, y: 0)
        let tileCount = Int(ceil(size.height / tileHeight)) + 1
        for tile in -1..<tileCount {
            let origin = CGFloat(tile) * tileHeight + offset
            drawPath(context: world, width: size.width, origin: origin, height: tileHeight)
        }
        for tile in -1..<tileCount {
            let origin = CGFloat(tile) * tileHeight + offset
            drawPlants(context: world, size: size, origin: origin, cameraOffset: cameraOffset)
        }
        drawTravelers(
            context: context, size: size, time: time, playerY: playerY,
            offset: offset, cameraOffset: cameraOffset)
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

    private func drawPlants(
        context: GraphicsContext, size: CGSize, origin: CGFloat, cameraOffset: CGFloat
    ) {
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
                guard point.x + cameraOffset > -60, point.x + cameraOffset < size.width + 60,
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
        let position = (y.truncatingRemainder(dividingBy: tileHeight) + tileHeight)
            .truncatingRemainder(dividingBy: tileHeight)
        let half = tileHeight / 2
        let progress = position.truncatingRemainder(dividingBy: half) / half
        let bend: CGFloat = position < half ? 360 : -360
        return width / 2 + bend * progress * (1 - progress)
    }

    private func drawTravelers(
        context: GraphicsContext, size: CGSize, time: TimeInterval, playerY: CGFloat,
        offset: CGFloat, cameraOffset: CGFloat
    ) {
        let player = CGPoint(x: size.width / 2 - 17, y: playerY)
        let interval: TimeInterval = 16
        let firstCrossing: TimeInterval = 4
        let first = max(0, Int((time - firstCrossing) / interval) - 1)

        for index in first...(first + 3) {
            let crossing = firstCrossing + Double(index) * interval
            let y = playerY + CGFloat(time - crossing) * walkingSpeed * 2
            guard y > -60, y < size.height + 60 else { continue }
            let passer = CGPoint(
                x: pathCenter(at: y - offset, width: size.width) + cameraOffset + 17, y: y)
            drawWalker(
                context: context, at: passer, time: time + Double(index), facingForward: true,
                coat: MeadowPalette.passerCoats[index % MeadowPalette.passerCoats.count],
                skin: MeadowPalette.walkerSkins[index % MeadowPalette.walkerSkins.count])

            let greeting = (time - crossing + 0.9) / 1.8
            if (0...1).contains(greeting) {
                drawGreeting(context: context, player: player, passer: passer, progress: greeting)
            }
        }
        drawWalker(
            context: context, at: player, time: time, facingForward: false,
            coat: MeadowPalette.playerCoat, skin: MeadowPalette.walkerSkins[0])
    }

    private func drawWalker(
        context: GraphicsContext, at point: CGPoint, time: TimeInterval,
        facingForward: Bool, coat: Color, skin: Color
    ) {
        var context = context
        context.translateBy(x: point.x, y: point.y)
        context.fill(
            Path(ellipseIn: CGRect(x: -17, y: 14, width: 37, height: 13)),
            with: .color(MeadowPalette.trunk.opacity(0.2)))
        let stride = CGFloat(sin(time * 8)) * 3
        for leg in 0..<2 {
            let step = leg == 0 ? stride : -stride
            context.fill(
                Path(
                    roundedRect: CGRect(x: leg == 0 ? -8 : 4, y: 7 + step, width: 8, height: 14),
                    cornerRadius: 3),
                with: .color(MeadowPalette.ink))
        }
        context.translateBy(x: 0, y: -abs(stride) * 0.4)
        context.fill(
            Path(roundedRect: CGRect(x: -14, y: -14, width: 29, height: 31), cornerRadius: 11),
            with: .color(coat))
        for arm in [-19.0, 14.0] {
            context.fill(
                Path(roundedRect: CGRect(x: arm, y: -9, width: 6, height: 17), cornerRadius: 3),
                with: .color(skin))
        }
        context.fill(
            Path(ellipseIn: CGRect(x: -13, y: -37, width: 27, height: 28)),
            with: .color(skin))
        context.fill(
            Path(
                roundedRect: CGRect(x: -14, y: -39, width: 29, height: facingForward ? 13 : 25),
                cornerRadius: 9),
            with: .color(MeadowPalette.walkerHair))
        if facingForward {
            for eye in [-5.0, 5.0] {
                context.fill(
                    Path(ellipseIn: CGRect(x: eye, y: -24, width: 2.5, height: 3)),
                    with: .color(MeadowPalette.ink))
            }
            var smile = Path()
            smile.move(to: CGPoint(x: -3, y: -17))
            smile.addQuadCurve(to: CGPoint(x: 4, y: -17), control: CGPoint(x: 0.5, y: -13))
            context.stroke(
                smile, with: .color(MeadowPalette.ink), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        } else {
            context.fill(
                Path(roundedRect: CGRect(x: -8, y: -8, width: 17, height: 21), cornerRadius: 6),
                with: .color(MeadowPalette.playerBackpack))
        }
    }

    private func drawGreeting(
        context: GraphicsContext, player: CGPoint, passer: CGPoint, progress: Double
    ) {
        var context = context
        context.opacity = sin(progress * .pi)
        for (point, side) in [(player, -1.0), (passer, 1.0)] {
            let ring = CGRect(x: point.x - 25, y: point.y - 19, width: 50, height: 50)
                .insetBy(dx: -progress * 8, dy: -progress * 8)
            context.stroke(Path(ellipseIn: ring), with: .color(MeadowPalette.greeting), lineWidth: 2)
            let bubble = CGRect(
                x: point.x + side * 12 - 15,
                y: point.y - 72 - sin(progress * .pi) * 5, width: 30, height: 30)
            context.fill(Path(ellipseIn: bubble), with: .color(MeadowPalette.paper))
            context.stroke(Path(ellipseIn: bubble), with: .color(MeadowPalette.greeting), lineWidth: 2)
            var wave = context.resolve(Image(systemName: "hand.wave.fill"))
            wave.shading = .color(MeadowPalette.ink)
            context.draw(wave, in: bubble.insetBy(dx: 7, dy: 7))
        }
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
