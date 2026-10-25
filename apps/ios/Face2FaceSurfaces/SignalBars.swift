import SwiftUI

/// Chronological quantized radio samples, not decorative audio or distance measurements.
struct SignalBars: View {
    let levels: [Int]
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let count = compact ? 5 : 9
        let values = Array((Array(repeating: 0, count: count) + levels).suffix(count))
        HStack(alignment: .center, spacing: compact ? 2 : 4) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(level == 0 ? Color.white.opacity(0.2) : Color.mint)
                    .frame(width: compact ? 3 : 5, height: 3 + Double(level) * (compact ? 3.5 : 7))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.8, dampingFraction: 0.65), value: levels)
        .accessibilityHidden(true)
    }
}
