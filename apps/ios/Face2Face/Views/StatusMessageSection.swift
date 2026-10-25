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
            if model.isTooLong {
                Text("Keep it to \(StatusMessage.maxLength) characters.")
                    .font(.footnote)
                    .foregroundStyle(MeadowPalette.errorInk)
                    .accessibilityIdentifier("statusMessageTooLong")
            }
            HStack(spacing: 12) {
                MeadowPrimaryButton(title: "Save Status", symbol: "checkmark", isBusy: model.activity.isBusy)
                {
                    Task { await save() }
                }
                .disabled(!model.canSave)
                .opacity(model.canSave || model.activity.isBusy ? 1 : 0.5)
                .accessibilityIdentifier("saveStatusMessage")
                if !model.draft.isEmpty {
                    Button {
                        Task {
                            isFocused = false
                            await model.clear()
                        }
                    } label: {
                        Text("Clear").underline()
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MeadowPalette.secondaryInk)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(MeadowPressStyle())
                    .disabled(model.activity.isBusy)
                    .accessibilityIdentifier("clearStatusMessage")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .activityAlert(model.activity)
    }

    private func save() async {
        isFocused = false
        guard model.canSave else { return }
        await model.save()
    }
}
