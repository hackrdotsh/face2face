import Face2FaceCore
import SwiftUI

/// Renders one server-described onboarding field by its type.
struct OnboardingFieldView: View {
    let field: OnboardingField
    @Binding var form: OnboardingForm
    let error: String?
    /// The signed-in person's avatar, for `image` fields.
    let avatar: Avatar
    let session: SessionModel

    var body: some View {
        input
        if let error {
            Text(error).font(.footnote).foregroundStyle(.red)
        }
    }

    @ViewBuilder private var input: some View {
        switch field.type {
        case .text:
            TextField(field.label, text: draft.text)
        case .date:
            DatePicker(
                field.label, selection: dateSelection,
                in: form.dateRange(for: field) ?? .distantPast ... .now,
                displayedComponents: .date)
        case .singleChoice:
            Picker(field.label, selection: draft.optionId) {
                Text("Choose").tag(String?.none)
                ForEach(field.options) { option in Text(option.label).tag(String?.some(option.id)) }
            }
            if form.selectedOption(for: field)?.allowsDescription == true {
                TextField("Describe", text: draft.description)
            }
        case .image:
            ProfilePhotoEditor(avatar: avatar, session: session)
        case .unsupported:
            EmptyView()
        }
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
