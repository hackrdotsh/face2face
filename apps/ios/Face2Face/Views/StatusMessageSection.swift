import Face2FaceCore
import SwiftUI

/// The account's status, shown to public connections on their profile and in the plaza.
struct StatusMessageSection: View {
    @Bindable var model: StatusMessageModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MeadowSectionHeader(title: "Status", detail: "\(model.length) of \(StatusMessage.maxLength)")
            Text("Public connections see this on your profile and in a speech bubble in the plaza.")
                .font(.subheadline)
                .foregroundStyle(MeadowPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Your status")
                    Spacer(minLength: 8)
                    clearButton
                }
                .font(.system(.caption, design: .rounded, weight: .bold))
                TextField("What's on your mind?", text: $model.draft, axis: .vertical)
                    .lineLimit(1...3)
                    .submitLabel(.done)
                    .focused($isFocused)
                    .onChange(of: model.draft) { _, draft in
                        guard draft.contains("\n") else { return }
                        model.draft = draft.replacing("\n", with: "")
                        isFocused = false
                        Task { await save() }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 15)
                    .frame(minHeight: 52)
                    .meadowWell()
                    .focusTarget { isFocused = true }
                    .accessibilityLabel("Status")
                    .accessibilityIdentifier("statusMessageField")
            }
            if model.isTooLong {
                Text("Keep it to \(StatusMessage.maxLength) characters.")
                    .font(.footnote)
                    .foregroundStyle(MeadowPalette.errorInk)
                    .accessibilityIdentifier("statusMessageTooLong")
            }
            MeadowPrimaryButton(title: "Save Status", symbol: "checkmark", isBusy: model.activity.isBusy) {
                Task { await save() }
            }
            .disabled(!model.canSave)
            .opacity(model.canSave || model.activity.isBusy ? 1 : 0.5)
            .accessibilityIdentifier("saveStatusMessage")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .activityAlert(model.activity)
    }

    /// Kept in the row while hidden, so the field does not shift when text appears.
    private var clearButton: some View {
        Button {
            Task {
                isFocused = false
                await model.clear()
            }
        } label: {
            Text("Clear").underline()
                .foregroundStyle(MeadowPalette.secondaryInk)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .padding(.vertical, -12)
        }
        .buttonStyle(MeadowPressStyle())
        .opacity(model.draft.isEmpty ? 0 : 1)
        .disabled(model.draft.isEmpty || model.activity.isBusy)
        .accessibilityHidden(model.draft.isEmpty)
        .accessibilityIdentifier("clearStatusMessage")
    }

    private func save() async {
        isFocused = false
        guard model.canSave else { return }
        await model.save()
    }
}
