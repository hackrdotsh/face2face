import SwiftUI

struct FormEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var visible: Bool
    var order: Int
    var lastOrder: Int

    static func exitDuration(lastOrder: Int, reduceMotion: Bool) -> Double {
        reduceMotion ? 0.12 : 0.16 + Double(lastOrder) * 0.05
    }

    private var animation: Animation {
        guard visible else {
            return reduceMotion
                ? .easeOut(duration: 0.12)
                : .easeIn(duration: 0.16).delay(Double(max(0, lastOrder - order)) * 0.05)
        }
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
