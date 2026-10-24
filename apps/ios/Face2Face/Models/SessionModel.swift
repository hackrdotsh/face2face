import Face2FaceCore
import Foundation
import Observation

@MainActor
@Observable
final class SessionModel {
    /// `nil` until the saved session has been checked.
    private(set) var phase: SessionPhase?
    var serverAddress = UserDefaults.standard.string(forKey: "apiAddress") ?? SessionModel.defaultAddress
    private(set) var connection = "Not checked"
    let activity = Activity()

    private static var defaultAddress: String {
        #if DEBUG
            "http://localhost:8080"
        #else
            ""
        #endif
    }

    func client() throws -> APIClient {
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

    func serverChanged() {
        phase = .signedOut
        connection = "Not checked"
    }

    func checkConnection() async {
        connection = "Checking connection"
        let connected = await activity.run { try await self.client().checkHealth() }
        connection = connected ? "API connected" : "Not connected"
    }

    func restore() async {
        guard !serverAddress.isEmpty else {
            phase = .signedOut
            return
        }
        let restored = await activity.run { try await self.refreshAccount() }
        if !restored { phase = .signedOut }
    }

    /// Reloads the signed-in account, for example after signing in or finishing onboarding.
    func refreshAccount() async throws {
        do {
            phase = SessionPhase(account: try await client().currentAccount())
        } catch APIError.unauthenticated {
            phase = .signedOut
        }
    }

    func signOut() async {
        await activity.run {
            do { try await self.client().signOut() } catch APIError.unauthenticated {}
            self.phase = .signedOut
        }
    }
}
