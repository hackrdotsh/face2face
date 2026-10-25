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

    private static let defaultAddress = "https://f2f.rocky.systems"

    func client() throws -> APIClient {
        let configuration = try self.configuration()
        UserDefaults.standard.set(configuration.baseURL.absoluteString, forKey: "apiAddress")
        return APIClient(
            configuration: configuration, tokens: KeychainTokenStore(server: configuration.baseURL))
    }

    /// A signed photo path on the current server, or nil when the address is not valid.
    func mediaURL(for path: String) -> URL? {
        try? configuration().mediaURL(for: path)
    }

    private func configuration() throws -> APIConfiguration {
        #if DEBUG
            let allowHTTP = true
        #else
            let allowHTTP = false
        #endif
        return try APIConfiguration(address: serverAddress, allowInsecureHTTP: allowHTTP)
    }

    func serverChanged() {
        BlobCompanionModel.shared.stop()
        ConnectedDiscoveryModel.backgroundWalk.stop(reason: "API changed")
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
            BlobCompanionModel.shared.stop()
            ConnectedDiscoveryModel.backgroundWalk.stop(reason: "Authentication ended")
            phase = .signedOut
        }
    }

    func signOut() async {
        BlobCompanionModel.shared.stop()
        ConnectedDiscoveryModel.backgroundWalk.stop(reason: "Signed out")
        await activity.run {
            do { try await self.client().signOut() } catch APIError.unauthenticated {}
            self.phase = .signedOut
        }
    }

    #if DEBUG
        /// Prototype bypass: enter the town without a session. Scratch only — never ship.
        func enterTownPreview() {
            let json = """
                {"user":{"id":"preview","name":"Preview Walker","email":"preview@seed.face2face.test",
                "avatar":{"seed":"AAAAAAAAAAAAAAAAAAAAAA","photo":null}},"onboardingComplete":true}
                """
            if let account = try? JSONDecoder().decode(Account.self, from: Data(json.utf8)) {
                phase = .ready(account)
            }
        }
    #endif

    var isTownPreview: Bool {
        #if DEBUG
            if case .ready(let account) = phase { return account.user.id == "preview" }
        #endif
        return false
    }
}
