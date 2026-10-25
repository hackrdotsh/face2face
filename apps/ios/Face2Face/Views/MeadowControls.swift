import SwiftUI

enum MeadowRadius {
    static let card: CGFloat = 40
    static let cardInset: CGFloat = 24
    /// Concentric with the card corners, for controls placed at the card inset.
    static let control: CGFloat = card - cardInset
}

struct MeadowPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        // Scoped so layout changes in the same transaction, like the keyboard closing, keep their own animation.
        configuration.label
            .animation(.easeOut(duration: 0.15)) { label in
                label
                    .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
                    .opacity(configuration.isPressed ? 0.8 : 1)
            }
    }
}

/// A labeled input well. `content` is the text field or control inside it.
struct MeadowField<Content: View>: View {
    let label: String
    var symbol: String?
    /// A small text button at the trailing end of the label row.
    var accessory: (title: String, action: () -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                Spacer(minLength: 8)
                if let accessory {
                    Button(action: accessory.action) { Text(accessory.title).underline() }
                        .foregroundStyle(MeadowPalette.secondaryInk)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                        .padding(.vertical, -12)
                }
            }
            .font(.system(.caption, design: .rounded, weight: .bold))
            HStack(spacing: 12) {
                if let symbol {
                    Image(systemName: symbol)
                        .foregroundStyle(MeadowPalette.secondaryInk)
                        .accessibilityHidden(true)
                }
                content.font(.body).tint(MeadowPalette.ink)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .meadowWell()
        }
    }
}

extension View {
    /// Widens a text field's tap area to this view plus `outset` on every side.
    /// The field keeps its own taps, so cursor placement still works.
    func focusTarget(outset: CGFloat = 6, _ focus: @escaping () -> Void) -> some View {
        padding(outset)
            .contentShape(Rectangle())
            .onTapGesture(perform: focus)
            .padding(-outset)
    }
}

extension View {
    /// The field fill and hairline border shared by inputs.
    func meadowWell(selected: Bool = false) -> some View {
        background(MeadowPalette.field, in: RoundedRectangle(cornerRadius: MeadowRadius.control))
            .overlay {
                RoundedRectangle(cornerRadius: MeadowRadius.control)
                    .strokeBorder(
                        selected ? MeadowPalette.ink : MeadowPalette.fieldBorder, lineWidth: selected ? 2 : 1
                    )
                    .allowsHitTesting(false)
            }
    }
}

struct MeadowPrimaryButton: View {
    let title: String
    var symbol = "arrow.right"
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                if isBusy {
                    ProgressView().tint(MeadowPalette.accentInk)
                } else {
                    Image(systemName: symbol).accessibilityHidden(true)
                }
            }
            .font(.system(.headline, design: .rounded, weight: .heavy))
            .foregroundStyle(MeadowPalette.accentInk)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background {
                RoundedRectangle(cornerRadius: MeadowRadius.control)
                    .fill(MeadowPalette.accent)
                    .shadow(color: MeadowPalette.accentShadow, radius: 0, y: 4)
            }
            .contentShape(RoundedRectangle(cornerRadius: MeadowRadius.control))
        }
        .buttonStyle(MeadowPressStyle())
        .accessibilityValue(isBusy ? "Loading" : "")
    }
}

/// A two-or-more option pill with a sliding thumb.
struct MeadowSegmentedControl<Value: Hashable>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var thumb
    let title: String
    @Binding var selection: Value
    let options: [(value: Value, label: String)]

    private static var inset: CGFloat { 4 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) {
                        selection = option.value
                    }
                } label: {
                    Text(option.label)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(selected ? MeadowPalette.ink : MeadowPalette.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: MeadowRadius.control - Self.inset)
                                    .fill(MeadowPalette.thumb)
                                    .shadow(color: MeadowPalette.shadow.opacity(0.1), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(Self.inset)
        .meadowWell()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// A glass card whose content sits at the concentric inset.
struct MeadowCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(MeadowRadius.cardInset)
            .background {
                MeadowGlass(shape: RoundedRectangle(cornerRadius: MeadowRadius.card))
                    .shadow(color: MeadowPalette.shadow.opacity(0.12), radius: 16, y: 6)
            }
    }
}

/// A card's heading, with optional trailing detail such as a count.
struct MeadowSectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .heavy))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(MeadowPalette.secondaryInk)
                    .monospacedDigit()
            }
        }
    }
}
