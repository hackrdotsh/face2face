import SwiftUI

/// One slot per digit over a hidden text field, so one-time code autofill and paste still work.
struct OneTimeCodeField<Focus: Hashable>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var code: String
    let focus: FocusState<Focus?>.Binding
    let focusValue: Focus
    /// Changes when a code is rejected, to shake the slots.
    var rejections = 0
    let onComplete: () -> Void

    static var length: Int { 6 }

    private var isFocused: Bool { focus.wrappedValue == focusValue }

    var body: some View {
        ZStack {
            TextField("", text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focused(focus, equals: focusValue)
                .accessibilityLabel("6-digit code")
                .accessibilityIdentifier("codeField")
                .onChange(of: code) { _, newValue in
                    let digits = String(newValue.filter { $0.isASCII && $0.isNumber }.prefix(Self.length))
                    if digits != newValue {
                        code = digits
                    } else if digits.count == Self.length {
                        onComplete()
                    }
                }
            HStack(spacing: 8) {
                ForEach(0..<Self.length, id: \.self, content: slot)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(height: 60)
        .keyframeAnimator(initialValue: CGFloat.zero, trigger: rejections) { content, offset in
            content.offset(x: reduceMotion ? 0 : offset)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(10, duration: 0.07)
                CubicKeyframe(-8, duration: 0.07)
                CubicKeyframe(6, duration: 0.07)
                CubicKeyframe(-4, duration: 0.07)
                CubicKeyframe(0, duration: 0.07)
            }
        }
    }

    private func slot(_ index: Int) -> some View {
        let digits = Array(code)
        let isActive = isFocused && index == min(digits.count, Self.length - 1)
        return ZStack {
            if index < digits.count {
                Text(String(digits[index]))
                    .font(.system(.title2, design: .rounded, weight: .heavy))
                    .monospacedDigit()
            } else if isActive {
                PhaseAnimator([true, false]) { visible in
                    Capsule()
                        .fill(MeadowPalette.ink)
                        .frame(width: 2, height: 24)
                        .opacity(visible || reduceMotion ? 1 : 0)
                } animation: { _ in
                    .easeInOut(duration: 0.5)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .meadowWell(selected: isActive)
        .animation(.easeOut(duration: 0.12), value: isActive)
    }
}
