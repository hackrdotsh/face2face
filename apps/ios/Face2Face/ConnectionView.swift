import SwiftUI

struct ConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section("API server") {
                    TextField("API URL", text: $model.serverAddress)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("API URL")
                        .onChange(of: model.serverAddress) { model.serverChanged() }
                    Button("Check connection") { Task { await model.checkConnection() } }
                    Label(model.connection, systemImage: "network")
                        .foregroundStyle(.secondary)
                }
                .disabled(model.isBusy)
                if let error = model.errorMessage {
                    Section {
                        Text(error).foregroundStyle(MeadowPalette.errorInk)
                    }
                }
            }
            .navigationTitle("Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .fontDesign(.rounded)
        .tint(MeadowPalette.ink)
        .onChange(of: model.connection) { _, status in
            AccessibilityNotification.Announcement(status).post()
        }
    }
}
