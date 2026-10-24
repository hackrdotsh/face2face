import Face2FaceCore
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var serverAddress = UserDefaults.standard.string(forKey: "apiAddress") ?? AppModel.defaultAddress
    var email = ""
    var password = ""
    var name = ""
    var createAccount = false
    var user: User?
    var isBusy = false
    var connection = "Not checked"
    var errorMessage: String?

    private static var defaultAddress: String {
        #if DEBUG
            "http://localhost:8787"
        #else
            ""
        #endif
    }

    func serverChanged() {
        user = nil
        connection = "Not checked"
    }

    func checkConnection() async {
        await perform {
            self.connection = "Checking connection"
            do {
                try await self.client().checkHealth()
                self.connection = "API connected"
            } catch {
                self.connection = "Not connected"
                throw error
            }
        }
    }

    func restoreSession() async {
        guard !serverAddress.isEmpty else { return }
        await perform {
            do { self.user = try await self.client().currentUser() } catch APIError.unauthenticated {
                self.user = nil
            }
        }
    }

    func authenticate() async {
        await perform {
            let client = try self.client()
            if self.createAccount {
                self.user = try await client.signUp(
                    name: self.name, email: self.email, password: self.password)
            } else {
                self.user = try await client.signIn(email: self.email, password: self.password)
            }
            self.password = ""
        }
    }

    func signOut() async {
        await perform {
            do { try await self.client().signOut() } catch APIError.unauthenticated {}
            self.user = nil
            self.password = ""
        }
    }

    private func client() throws -> APIClient {
        #if DEBUG
            let allowHTTP = true
        #else
            let allowHTTP = false
        #endif
        let configuration = try APIConfiguration(address: serverAddress, allowInsecureHTTP: allowHTTP)
        UserDefaults.standard.set(configuration.baseURL.absoluteString, forKey: "apiAddress")
        return APIClient(
            configuration: configuration, tokens: KeychainTokenStore(server: configuration.baseURL))
    }

    private func perform(_ action: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do { try await action() } catch is CancellationError {} catch {
            errorMessage = error.localizedDescription
        }
    }
}
