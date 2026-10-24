import SwiftUI

@MainActor
struct ContentView: View {
    @State private var model = AppModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("API server") {
                    TextField("API URL", text: $model.serverAddress)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(model.isBusy)
                        .onChange(of: model.serverAddress) { model.serverChanged() }
                    Button("Check connection") { Task { await model.checkConnection() } }
                        .disabled(model.isBusy)
                    Text(model.connection)
                        .foregroundStyle(.secondary)
                }

                if let user = model.user {
                    Section("Account") {
                        Text(user.name)
                        Button("Sign out") { Task { await model.signOut() } }
                            .disabled(model.isBusy)
                    }
                } else {
                    Section {
                        Picker("Account", selection: $model.createAccount) {
                            Text("Sign in").tag(false)
                            Text("Create account").tag(true)
                        }
                        .pickerStyle(.segmented)
                        if model.createAccount {
                            TextField("Name", text: $model.name)
                                .textContentType(.name)
                        }
                        TextField("Email", text: $model.email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Password", text: $model.password)
                            .textContentType(model.createAccount ? .newPassword : .password)
                        if model.createAccount {
                            Text("Use at least 12 characters for your password.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Button(model.createAccount ? "Create account" : "Sign in") {
                            Task { await model.authenticate() }
                        }
                    }
                    .disabled(model.isBusy)
                }

                Section {
                    Text("Nearby discovery is not available yet.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("face2face")
            .overlay { if model.isBusy { ProgressView().accessibilityLabel("Loading") } }
            .task { await model.restoreSession() }
            .alert(
                "Request failed",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("Dismiss", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "Try again.")
            }
        }
    }
}
