import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = AppAppearance.system
    @Bindable var session: SessionModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("appearancePicker")
                }
                Section("API server") {
                    TextField("API URL", text: $session.serverAddress)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("API URL")
                        .onChange(of: session.serverAddress) { session.serverChanged() }
                    Button("Check connection") { Task { await session.checkConnection() } }
                    Label(session.connection, systemImage: "network")
                        .foregroundStyle(.secondary)
                }
                .disabled(session.activity.isBusy)
                if let error = session.activity.errorMessage {
                    Section {
                        Text(error).foregroundStyle(MeadowPalette.errorInk)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .fontDesign(.rounded)
        .tint(MeadowPalette.ink)
        .preferredColorScheme(appearance.colorScheme)
        .onChange(of: session.connection) { _, status in
            AccessibilityNotification.Announcement(status).post()
        }
    }
}
