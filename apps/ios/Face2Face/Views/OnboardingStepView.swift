import Face2FaceCore
import SwiftUI

/// One onboarding step: a heading for the field and the input for its type.
struct OnboardingStepView: View {
    let field: OnboardingField
    @Binding var form: OnboardingForm
    let error: String?
    /// The signed-in person's avatar, for `image` fields.
    let avatar: Avatar
    let session: SessionModel
    let interests: InterestsModel
    let textFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(heading.title)
                    .font(.system(.title, design: .rounded, weight: .heavy))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let detail = heading.detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(MeadowPalette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            input
            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(MeadowPalette.errorInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            if field.type == .text { textFocused.wrappedValue = true }
        }
    }

    private var heading: (title: String, detail: String?) {
        switch field.key {
        case "name": ("What should we call you?", "This is the name people see.")
        case "birthDate": ("When's your birthday?", "You need to be 18 or older.")
        case "gender": ("What's your gender?", nil)
        case "interests":
            (
                "What are you into?",
                "Pick up to 10. Shared interests open chances to meet. You can change them later."
            )
        case "photo": ("Meet your little alter ego", "Uniquely yours. No profile photo needed.")
        default: (field.label, nil)
        }
    }

    @ViewBuilder private var input: some View {
        switch field.type {
        case .text:
            TextField(field.label, text: draft.text)
                .font(.title3.weight(.semibold))
                .textContentType(field.key == "name" ? .name : nil)
                .submitLabel(.next)
                .focused(textFocused)
                .onSubmit(onSubmit)
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .meadowWell()
                .focusTarget { textFocused.wrappedValue = true }
                .accessibilityLabel(field.label)
        case .date:
            DatePicker(
                field.label, selection: dateSelection,
                in: form.dateRange(for: field) ?? .distantPast ... .now,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .meadowWell()
        case .singleChoice:
            ChipFlow(spacing: 8) {
                ForEach(field.options) { option in
                    chip(option)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(field.label)
            if form.selectedOption(for: field)?.allowsDescription == true {
                TextField("Describe it in your words", text: draft.description)
                    .focused(textFocused)
                    .submitLabel(.next)
                    .onSubmit(onSubmit)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .meadowWell()
                    .focusTarget { textFocused.wrappedValue = true }
                    .accessibilityLabel("Description")
            }
        case .image:
            BlobPortrait(seed: avatar.seed, prominent: true)
                .frame(maxWidth: .infinity)
        case .interests:
            InterestsSection(model: interests, showsHeader: false)
        case .unsupported:
            EmptyView()
        }
    }

    private func chip(_ option: ChoiceOption) -> some View {
        let selected = draft.wrappedValue.optionId == option.id
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { draft.wrappedValue.optionId = option.id }
        } label: {
            Text(option.label)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(selected ? MeadowPalette.accentInk : MeadowPalette.ink)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: MeadowRadius.control).fill(MeadowPalette.accent)
                    }
                }
                .meadowWell(selected: selected)
        }
        .buttonStyle(MeadowPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var draft: Binding<FieldDraft> {
        Binding(
            get: { form.drafts[field.key] ?? FieldDraft() },
            set: { form.drafts[field.key] = $0 }
        )
    }

    private var dateSelection: Binding<Date> {
        Binding(
            get: { draft.wrappedValue.date ?? form.dateRange(for: field)?.upperBound ?? .now },
            set: { draft.wrappedValue.date = $0 }
        )
    }
}

/// Lays out children in rows, wrapping to a new row when one is full.
struct ChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [(
        indices: [Int], width: CGFloat, height: CGFloat
    )] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + size.width <= width {
                rows[rows.count - 1].indices.append(index)
                rows[rows.count - 1].width += spacing + size.width
                rows[rows.count - 1].height = max(last.height, size.height)
            } else {
                rows.append(([index], size.width, size.height))
            }
        }
        return rows
    }
}
