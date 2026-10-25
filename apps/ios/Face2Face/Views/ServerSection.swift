import SwiftUI

struct ServerSection: View {
    @Bindable var session: SessionModel

    var body: some View {
        Section("API Server") {
            TextField("API URL", text: $session.serverAddress)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: session.serverAddress) { session.serverChanged() }
            Button("Check connection") { Task { await session.checkConnection() } }
            Text(session.connection).foregroundStyle(.secondary)
        }
        .disabled(session.activity.isBusy)
    }
}
