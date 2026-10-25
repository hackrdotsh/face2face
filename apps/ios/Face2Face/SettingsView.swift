import Face2FaceCore
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = AppAppearance.system
    @Bindable var session: SessionModel
    @State private var passkeyEnrollment: PasskeyEnrollmentModel

    init(session: SessionModel, passkeys: PasskeyAuthorizer) {
        self.session = session
        _passkeyEnrollment = State(initialValue: PasskeyEnrollmentModel(session: session, passkeys: passkeys))
    }

    private var account: Account? {
        guard case .ready(let account) = session.phase else { return nil }
        return account
    }

    var body: some View {
        NavigationStack {
            Form {
                if let account {
                    accountPreferences(account)
                        .disabled(session.isTownPreview)
                }
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
                .disabled(session.isTownPreview)
                #if DEBUG
                    Section("Developer tools") {
                        if account == nil {
                            Button("Preview town") {
                                session.enterTownPreview()
                                dismiss()
                            }
                            .accessibilityIdentifier("previewTown")
                        }
                        NavigationLink("Walk test") {
                            WalkDiscoveryView(model: ConnectedDiscoveryModel.backgroundWalk)
                        }
                        NavigationLink("Connected test") { ConnectedDiscoveryView() }
                        NavigationLink("Pocket test") {
                            PocketDiscoveryView(model: PocketDiscoveryModel.shared)
                        }
                        NavigationLink("Device test") { DiscoveryDiagnosticView() }
                    }
                    .disabled(session.isTownPreview)
                #endif
                if let error = session.activity.errorMessage {
                    Section {
                        Text(error).foregroundStyle(MeadowPalette.errorInk)
                    }
                }
            }
            .disabled(session.activity.isBusy || passkeyEnrollment.activity.isBusy)
            .accessibilityIdentifier("settingsForm")
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
        .activityAlert(passkeyEnrollment.activity)
        .onChange(of: session.connection) { _, status in
            AccessibilityNotification.Announcement(status).post()
        }
    }

    @ViewBuilder private func accountPreferences(_ account: Account) -> some View {
        Section {
            if passkeyEnrollment.isEnrolled {
                Label("Passkey added", systemImage: "checkmark.shield")
            } else {
                Button("Add a passkey") {
                    Task { await passkeyEnrollment.addPasskey(for: account) }
                }
                .accessibilityIdentifier("addPasskey")
            }
        } header: {
            Text("Passkey")
        } footer: {
            Text("Use Face ID or Touch ID instead of typing a password.")
        }
        DiscoverySection(model: ConnectedDiscoveryModel.backgroundWalk, account: account)
    }
}
