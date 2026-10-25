import Face2FaceCore
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = AppAppearance.system
    @AppStorage("forest3DEnabled") private var forest3DEnabled = true
    @Bindable var session: SessionModel

    private var account: Account? {
        guard case .ready(let account) = session.phase else { return nil }
        return account
    }

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
                    if #available(iOS 18.0, *) {
                        Toggle("3D forest", isOn: $forest3DEnabled)
                            .accessibilityIdentifier("forest3DToggle")
                    }
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
                    if session.isTownPreview {
                        Section("Town preview") {
                            Button("Return to sign in") {
                                session.showSignInForTesting()
                                dismiss()
                            }
                            .accessibilityIdentifier("exitTownPreview")
                        }
                    }
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
            .disabled(session.activity.isBusy)
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
        .onChange(of: session.connection) { _, status in
            AccessibilityNotification.Announcement(status).post()
        }
    }

}
