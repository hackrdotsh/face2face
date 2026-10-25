import SwiftUI

struct MeadowGlass<Surface: InsettableShape>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: Surface
    var interactive = false

    var body: some View {
        if reduceTransparency {
            shape.fill(MeadowPalette.paper)
        } else if #available(iOS 26.0, *) {
            shape.fill(.clear)
                .glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                MeadowPalette.glassEdge.opacity(0.9), MeadowPalette.glassEdge.opacity(0.15),
                                MeadowPalette.glassEdge.opacity(0.6),
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
                }
        }
    }
}
