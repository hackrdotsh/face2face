import SwiftUI

struct FormEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var visible: Bool
    var order: Int

    private var animation: Animation {
        guard visible else { return .easeOut(duration: 0.12) }
        if reduceMotion { return .easeOut(duration: 0.15) }
        return .spring(response: 0.32, dampingFraction: 0.78).delay(Double(order) * 0.08)
    }

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible || reduceMotion ? 1 : 0.88)
            .offset(y: visible || reduceMotion ? 0 : 10)
            .animation(animation, value: visible)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
    }
}
