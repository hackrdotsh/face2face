import SwiftUI

/// Shared scenery for the login meadow and town. These residents are purely decorative.
enum MeadowIllustrations {
    static func tree(context: GraphicsContext, at point: CGPoint, scale: CGFloat, light: Bool) {
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
            with: .color(MeadowPalette.treeHighlight.opacity(0.22)))
    }

    static func walker(
        context: GraphicsContext, at point: CGPoint, time: TimeInterval,
        facingForward: Bool, coat: Color, skin: Color, scale: CGFloat = 1,
        seated: Bool = false, standing: Bool = false
    ) {
        var context = context
        context.translateBy(x: point.x, y: point.y)
        context.scaleBy(x: scale, y: scale)
        context.fill(
            Path(ellipseIn: CGRect(x: -17, y: 14, width: 37, height: 13)),
            with: .color(MeadowPalette.trunk.opacity(0.2)))
        let stride: CGFloat = seated || standing ? 0 : CGFloat(sin(time * 8)) * 3
        for leg in 0..<2 {
            let step = leg == 0 ? stride : -stride
            context.fill(
                Path(
                    roundedRect: CGRect(
                        x: leg == 0 ? -8 : 4, y: 7 + step, width: 8,
                        height: seated ? 8 : 14), cornerRadius: 3),
                with: .color(MeadowPalette.characterInk))
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
        context.fill(Path(ellipseIn: CGRect(x: -13, y: -37, width: 27, height: 28)), with: .color(skin))
        context.fill(
            Path(
                roundedRect: CGRect(x: -14, y: -39, width: 29, height: facingForward ? 13 : 25),
                cornerRadius: 9),
            with: .color(MeadowPalette.walkerHair))
        if facingForward {
            for eye in [-5.0, 5.0] {
                context.fill(
                    Path(ellipseIn: CGRect(x: eye, y: -24, width: 2.5, height: 3)),
                    with: .color(MeadowPalette.characterInk))
            }
            var smile = Path()
            smile.move(to: CGPoint(x: -3, y: -17))
            smile.addQuadCurve(to: CGPoint(x: 4, y: -17), control: CGPoint(x: 0.5, y: -13))
            context.stroke(
                smile, with: .color(MeadowPalette.characterInk),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        } else {
            context.fill(
                Path(roundedRect: CGRect(x: -8, y: -8, width: 17, height: 21), cornerRadius: 6),
                with: .color(MeadowPalette.playerBackpack))
        }
    }
}
