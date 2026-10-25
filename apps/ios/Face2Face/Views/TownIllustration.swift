import SwiftUI

/// One map, one world scale. Building foundations, paths, residents and touch targets align.
enum TownIllustration {
    private static let personScale: CGFloat = 0.42
    private static let cream = MeadowPalette.paper
    private static let wood = MeadowPalette.trunk

    static func draw(context: GraphicsContext, time: TimeInterval, friendCount: Int = 0) {
        terrain(context: context)
        water(context: context, time: time)
        paths(context: context)
        trees(context: context)
        venue(context: context, time: time)
        cafe(context: context, time: time)
        board(context: context)
        residents(context: context, time: time, friendCount: friendCount)
        waterfront(context: context)
    }

    private static func terrain(context: GraphicsContext) {
        fill(context, CGRect(x: 0, y: 0, width: 400, height: 640), MeadowPalette.grass)
        // Quiet patches and flowers, outside the walking surface and building footprints.
        for (index, point) in [
            CGPoint(x: 57, y: 73), CGPoint(x: 280, y: 79), CGPoint(x: 299, y: 170),
            CGPoint(x: 94, y: 283), CGPoint(x: 114, y: 329), CGPoint(x: 268, y: 479),
            CGPoint(x: 313, y: 512), CGPoint(x: 88, y: 573), CGPoint(x: 259, y: 564),
        ].enumerated() {
            var tuft = Path()
            for blade in 0..<3 {
                let x = point.x + CGFloat(blade) * 4
                tuft.move(to: CGPoint(x: x, y: point.y))
                tuft.addLine(to: CGPoint(x: x - 1, y: point.y - CGFloat(blade == 1 ? 5 : 3)))
            }
            context.stroke(
                tuft, with: .color(MeadowPalette.grassDetail.opacity(0.65)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            if index.isMultiple(of: 2) {
                for flower in 0..<3 {
                    let center = CGPoint(
                        x: point.x + CGFloat(flower) * 7 - 3, y: point.y + 9 + CGFloat(flower % 2) * 4)
                    dot(context, center, radius: 2.8, color: MeadowPalette.flower)
                    dot(context, center, radius: 1, color: MeadowPalette.flowerCenter)
                }
            }
        }
    }

    private static func paths(context: GraphicsContext) {
        // An orthogonal route with two grass islands, like the reference town.
        // Union first: no internal seams where paths meet.
        let pieces: [CGRect] = [
            CGRect(x: 185, y: 67, width: 28, height: 488),
            CGRect(x: 43, y: 207, width: 155, height: 28),
            CGRect(x: 199, y: 249, width: 177, height: 28),
            CGRect(x: 348, y: 263, width: 28, height: 142),
            CGRect(x: 199, y: 391, width: 163, height: 28),
            CGRect(x: 43, y: 399, width: 156, height: 28),
            CGRect(x: 43, y: 413, width: 28, height: 128),
            CGRect(x: 57, y: 527, width: 142, height: 28),
        ]
        var outside = Path()
        var inside = Path()
        for rect in pieces {
            outside = outside.union(Path(roundedRect: rect.insetBy(dx: -3, dy: -3), cornerRadius: 6))
            inside = inside.union(Path(roundedRect: rect, cornerRadius: 5))
        }
        context.fill(outside, with: .color(MeadowPalette.pathEdge))
        context.fill(inside, with: .color(MeadowPalette.path))
        // Sparse little stones; no noisy texture over the whole map.
        for point in [
            CGPoint(x: 89, y: 217), CGPoint(x: 144, y: 227), CGPoint(x: 194, y: 339),
            CGPoint(x: 366, y: 318), CGPoint(x: 105, y: 538), CGPoint(x: 301, y: 404),
        ] {
            fill(
                context, CGRect(x: point.x, y: point.y, width: 3, height: 1.5), MeadowPalette.pathEdge,
                radius: 1)
        }
    }

    private static func trees(context: GraphicsContext) {
        // Exactly the login tree artwork. Non-overlapping crowns, not stacked circles.
        for (index, x) in [28.0, 104, 280, 356].enumerated() {
            MeadowIllustrations.tree(
                context: context, at: CGPoint(x: x, y: index % 2 == 0 ? 33 : 40),
                scale: 0.58, light: index.isMultiple(of: 2))
        }
        for (index, point) in [
            CGPoint(x: 18, y: 137), CGPoint(x: 19, y: 302),
            CGPoint(x: 384, y: 132), CGPoint(x: 383, y: 480),
        ].enumerated() {
            MeadowIllustrations.tree(context: context, at: point, scale: 0.38, light: index.isMultiple(of: 2))
        }
        // A garden on the open lower-right lawn, not more buildings.
        MeadowIllustrations.tree(context: context, at: CGPoint(x: 296, y: 472), scale: 0.56, light: true)
        bench(context: context, at: CGPoint(x: 296, y: 512))
    }

    private static func venue(context: GraphicsContext, time: TimeInterval) {
        var c = context
        c.translateBy(x: 108, y: 155)
        // No drop shadow. The footing ends at y=198, before the path begins at 207.
        fill(c, CGRect(x: -57, y: 28, width: 114, height: 15), MeadowPalette.pathEdge, radius: 3)
        fill(c, CGRect(x: -55, y: -34, width: 110, height: 69), cream, radius: 5)
        fill(c, CGRect(x: -50, y: -28, width: 100, height: 58), MeadowPalette.field, radius: 3)
        // Pitched, softly colored roof with a visible ridge.
        polygon(
            c,
            [
                CGPoint(x: -64, y: -32), CGPoint(x: -46, y: -61),
                CGPoint(x: 45, y: -61), CGPoint(x: 65, y: -32),
            ], MeadowPalette.accentShadow)
        line(
            c, [CGPoint(x: -45, y: -57), CGPoint(x: 44, y: -57)], MeadowPalette.accent.opacity(0.65), width: 2
        )
        // Marquee lights make this a venue rather than another house.
        fill(c, CGRect(x: -59, y: -34, width: 118, height: 20), MeadowPalette.accent, radius: 4)
        for index in 0..<9 {
            dot(
                c, CGPoint(x: -48 + CGFloat(index) * 12, y: -29), radius: 1.6,
                color: MeadowPalette.flowerCenter.opacity(0.75 + 0.2 * sin(time * 1.1 + Double(index))))
        }
        symbol(
            c, "sparkles", in: CGRect(x: -9, y: -26, width: 18, height: 11), color: MeadowPalette.accentInk)
        // Curtains framing a warm entry.
        fill(c, CGRect(x: -18, y: -8, width: 36, height: 43), MeadowPalette.interiorGlow, radius: 4)
        fill(c, CGRect(x: -18, y: -8, width: 8, height: 37), MeadowPalette.accentShadow, radius: 2)
        fill(c, CGRect(x: 10, y: -8, width: 8, height: 37), MeadowPalette.accentShadow, radius: 2)
        for x in [-41.0, 30] {
            fill(c, CGRect(x: x, y: -3, width: 12, height: 24), MeadowPalette.pathEdge, radius: 2)
            fill(c, CGRect(x: x + 2, y: -1, width: 8, height: 20), MeadowPalette.flower, radius: 1)
        }
        // An orderly queue on the pavement, all at the global human scale.
        line(c, [CGPoint(x: 22, y: 55), CGPoint(x: 64, y: 55)], wood.opacity(0.7), width: 1)
        for index in 0..<3 {
            person(
                c, at: CGPoint(x: 23 + CGFloat(index) * 17, y: 60), index: index,
                time: 0, facing: false, standing: true)
        }
    }

    private static func cafe(context: GraphicsContext, time: TimeInterval) {
        var c = context
        c.translateBy(x: 278, y: 315)
        // A modest terrace inside its own grass island, well clear of the venue.
        fill(c, CGRect(x: -56, y: 31, width: 112, height: 42), MeadowPalette.pathEdge, radius: 5)
        fill(c, CGRect(x: -53, y: 33, width: 106, height: 37), MeadowPalette.path.opacity(0.8), radius: 3)
        for x in stride(from: -40.0, through: 44, by: 21) {
            line(
                c, [CGPoint(x: x, y: 34), CGPoint(x: x, y: 69)], MeadowPalette.pathEdge.opacity(0.7),
                width: 0.7)
        }
        fill(c, CGRect(x: -53, y: 17, width: 106, height: 14), wood, radius: 3)
        fill(c, CGRect(x: -51, y: -39, width: 102, height: 61), cream, radius: 5)
        // Sloped roof, not a floating horizontal bar.
        polygon(
            c,
            [
                CGPoint(x: -59, y: -38), CGPoint(x: -46, y: -63),
                CGPoint(x: 42, y: -63), CGPoint(x: 60, y: -38),
            ], MeadowPalette.cafeRoof)
        for row in 0..<3 {
            let y = -58 + CGFloat(row) * 8
            line(
                c, [CGPoint(x: -42 - CGFloat(row) * 4, y: y), CGPoint(x: 42 + CGFloat(row) * 4, y: y)],
                cream.opacity(0.17), width: 1)
        }
        // Big windows, divided panes, cozy light.
        for x in [-43.0, 14] {
            fill(c, CGRect(x: x, y: -28, width: 29, height: 34), wood, radius: 3)
            fill(c, CGRect(x: x + 2, y: -26, width: 25, height: 29), MeadowPalette.interiorGlow, radius: 2)
            line(c, [CGPoint(x: x + 14.5, y: -26), CGPoint(x: x + 14.5, y: 3)], wood.opacity(0.55), width: 1)
            line(c, [CGPoint(x: x + 2, y: -12), CGPoint(x: x + 27, y: -12)], wood.opacity(0.55), width: 1)
            // Window box.
            fill(c, CGRect(x: x - 1, y: 5, width: 31, height: 5), MeadowPalette.treeShade, radius: 2)
            for flower in 0..<4 {
                dot(
                    c, CGPoint(x: x + 3 + CGFloat(flower) * 7, y: 5), radius: 1.5, color: MeadowPalette.flower
                )
            }
        }
        fill(c, CGRect(x: -9, y: -25, width: 18, height: 48), wood, radius: 3)
        fill(c, CGRect(x: -6, y: -21, width: 12, height: 24), MeadowPalette.interiorGlow, radius: 2)
        dot(c, CGPoint(x: 4, y: 12), radius: 1.2, color: cream)
        // Scalloped striped awning under the roof.
        for stripe in 0..<8 {
            fill(
                c, CGRect(x: -56 + CGFloat(stripe) * 14, y: -38, width: 14, height: 13),
                stripe.isMultiple(of: 2) ? MeadowPalette.cafeRoof : cream, radius: 3)
        }
        // Clearly visible cup sign above the roof, never hidden behind the awning.
        line(c, [CGPoint(x: -40, y: -67), CGPoint(x: -40, y: -86), CGPoint(x: -15, y: -86)], wood, width: 2)
        var sign = c
        sign.translateBy(x: -17, y: -83)
        sign.rotate(by: .radians(sin(time * 0.9) * 0.035))
        fill(sign, CGRect(x: -13, y: 0, width: 26, height: 22), cream, radius: 5)
        symbol(
            sign, "cup.and.saucer.fill", in: CGRect(x: -9, y: 5, width: 18, height: 13),
            color: MeadowPalette.cafeRoof)
        // The same residents as the login, sitting at actual tables and chairs.
        table(c, at: CGPoint(x: -30, y: 52), time: time, index: 0)
        table(c, at: CGPoint(x: 30, y: 52), time: time, index: 2)
        // Stepping stone meets the lower path: no floating foundation.
        fill(c, CGRect(x: -10, y: 74, width: 20, height: 3), MeadowPalette.pathEdge, radius: 1)
    }

    private static func table(_ c: GraphicsContext, at point: CGPoint, time: TimeInterval, index: Int) {
        var c = c
        c.translateBy(x: point.x, y: point.y)
        for x in [-12.0, 12] {
            fill(c, CGRect(x: x - 5, y: 0, width: 10, height: 7), wood, radius: 2)
            line(c, [CGPoint(x: x - 4, y: 4), CGPoint(x: x - 4, y: 11)], wood, width: 1.5)
        }
        person(c, at: CGPoint(x: -12, y: -1), index: index, time: 0, facing: true, seated: true)
        person(c, at: CGPoint(x: 12, y: -1), index: index + 1, time: 0, facing: true, seated: true)
        line(c, [CGPoint(x: 0, y: 1), CGPoint(x: 0, y: 12)], wood, width: 3)
        c.fill(Path(ellipseIn: CGRect(x: -14, y: -3, width: 28, height: 10)), with: .color(cream))
        for x in [-5.0, 5] {
            fill(c, CGRect(x: x - 2.5, y: -5, width: 5, height: 4), MeadowPalette.cafeRoof, radius: 1)
            let lift = CGFloat(sin(time * 1.3 + Double(index))) * 1.5
            line(
                c, [CGPoint(x: x, y: -8), CGPoint(x: x + 1, y: -12 + lift)],
                cream.opacity(0.8), width: 1)
        }
    }

    private static func board(context: GraphicsContext) {
        var c = context
        c.translateBy(x: 123, y: 488)
        for x in [-35.0, 32] {
            fill(c, CGRect(x: x, y: -5, width: 6, height: 39), wood, radius: 2)
        }
        fill(c, CGRect(x: -47, y: -41, width: 94, height: 56), wood, radius: 5)
        fill(c, CGRect(x: -42, y: -36, width: 84, height: 46), MeadowPalette.boardCork, radius: 2)
        // A small weather cap and three posters contained within the frame.
        polygon(
            c,
            [
                CGPoint(x: -51, y: -42), CGPoint(x: -44, y: -49),
                CGPoint(x: 44, y: -49), CGPoint(x: 51, y: -42),
            ], MeadowPalette.cafeRoof)
        for index in 0..<3 {
            var p = c
            p.translateBy(x: -27 + CGFloat(index) * 27, y: -14)
            p.rotate(by: .degrees(index == 1 ? 4 : -4))
            fill(p, CGRect(x: -11, y: -17, width: 22, height: 33), cream, radius: 1)
            fill(
                p, CGRect(x: -8, y: -10, width: 16, height: 12),
                [MeadowPalette.accent, MeadowPalette.flower, MeadowPalette.treeLight][index], radius: 1)
            symbol(
                p, ["music.note", "heart.fill", "leaf.fill"][index],
                in: CGRect(x: -4, y: -8, width: 8, height: 8), color: MeadowPalette.accentInk.opacity(0.75))
            for row in 0..<2 {
                fill(
                    p, CGRect(x: -7, y: 7 + CGFloat(row) * 4, width: row == 0 ? 14 : 10, height: 1.5),
                    wood.opacity(0.6), radius: 0.5)
            }
            dot(p, CGPoint(x: 0, y: -15), radius: 1.5, color: MeadowPalette.accentShadow)
        }
    }

    private static func residents(context: GraphicsContext, time: TimeInterval, friendCount: Int) {
        for index in 0..<3 where index >= friendCount {
            let pose = TownResidentMotion.pose(slot: index, time: time)
            person(
                context, at: pose.point, index: index + 1, time: time + Double(index),
                facing: pose.facingForward,
                standing: pose.standing)
        }
    }

    private static func water(context: GraphicsContext, time: TimeInterval) {
        let rect = CGRect(x: 0, y: 590, width: 400, height: 50)
        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(colors: [MeadowPalette.waterShore, MeadowPalette.waterDeep]),
                startPoint: CGPoint(x: 0, y: 590), endPoint: CGPoint(x: 0, y: 640)))
        for row in 0..<4 {
            let y = 596 + CGFloat(row) * 14
            let flow = time * (row.isMultiple(of: 2) ? 9 : 6)
            var wave = Path()
            for sample in 0...80 {
                let x = CGFloat(sample) * 5
                let p = CGPoint(x: x, y: y + sin(x * 0.055 - flow * 0.055 + CGFloat(row)) * 2)
                if sample == 0 { wave.move(to: p) } else { wave.addLine(to: p) }
            }
            context.stroke(
                wave, with: .color(MeadowPalette.waterFoam.opacity(row == 0 ? 0.55 : 0.2)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        for index in 0..<12 {
            let x = CGFloat(index * 37 % 400)
            let shimmer = 0.15 + (sin(time * 1.4 + Double(index) * 1.7) + 1) * 0.17
            line(
                context,
                [
                    CGPoint(x: x, y: 612 + CGFloat(index % 3) * 9),
                    CGPoint(x: x + 5, y: 612 + CGFloat(index % 3) * 9),
                ], MeadowPalette.waterFoam.opacity(shimmer), width: 1)
        }
    }

    private static func waterfront(context: GraphicsContext) {
        fill(context, CGRect(x: 0, y: 578, width: 400, height: 13), MeadowPalette.path)
        line(context, [CGPoint(x: 12, y: 575), CGPoint(x: 388, y: 575)], wood, width: 2)
        line(context, [CGPoint(x: 12, y: 581), CGPoint(x: 388, y: 581)], wood, width: 2)
        for x in stride(from: 16.0, through: 384, by: 23) {
            fill(context, CGRect(x: x - 1.5, y: 568, width: 3, height: 17), wood, radius: 1)
        }
    }

    private static func bench(context: GraphicsContext, at point: CGPoint) {
        for row in 0..<3 {
            fill(
                context, CGRect(x: point.x - 18, y: point.y - 7 + CGFloat(row) * 4, width: 36, height: 3),
                wood, radius: 1)
        }
        for x in [-13.0, 13] {
            fill(
                context, CGRect(x: point.x + x, y: point.y + 3, width: 2, height: 6), MeadowPalette.treeShade,
                radius: 1)
        }
    }

    private static func person(
        _ context: GraphicsContext, at point: CGPoint, index: Int,
        time: TimeInterval, facing: Bool, seated: Bool = false, standing: Bool = false
    ) {
        MeadowIllustrations.walker(
            context: context, at: point, time: time,
            facingForward: facing, coat: MeadowPalette.passerCoats[index % MeadowPalette.passerCoats.count],
            skin: MeadowPalette.walkerSkins[index % MeadowPalette.walkerSkins.count],
            scale: personScale, seated: seated, standing: standing)
    }

    private static func fill(_ context: GraphicsContext, _ rect: CGRect, _ color: Color, radius: CGFloat = 0)
    {
        context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(color))
    }
    private static func dot(_ context: GraphicsContext, _ point: CGPoint, radius: CGFloat, color: Color) {
        context.fill(
            Path(
                ellipseIn: CGRect(
                    x: point.x - radius, y: point.y - radius,
                    width: radius * 2, height: radius * 2)), with: .color(color))
    }
    private static func line(_ context: GraphicsContext, _ points: [CGPoint], _ color: Color, width: CGFloat)
    {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        context.stroke(
            path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        )
    }
    private static func polygon(_ context: GraphicsContext, _ points: [CGPoint], _ color: Color) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        context.fill(path, with: .color(color))
    }
    private static func symbol(_ context: GraphicsContext, _ name: String, in rect: CGRect, color: Color) {
        var image = context.resolve(Image(systemName: name))
        image.shading = .color(color)
        context.draw(image, in: rect)
    }
}
