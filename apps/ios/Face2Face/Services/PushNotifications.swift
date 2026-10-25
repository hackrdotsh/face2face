import Face2FaceCore
import OSLog
import Observation
import SwiftUI
import UserNotifications

/// Asks for notification permission, keeps this phone's APNs token registered
/// for the signed-in person, and relays notifications the system hands the app.
@MainActor
@Observable
final class PushNotifications {
    static let shared = PushNotifications()

    /// Changes each time a notification arrives while the app is open.
    private(set) var foregroundArrivals = 0
    /// Set when a notification is tapped. The town opens the inbox and clears it.
    var inboxRequested = false
    /// Set when a message notification is tapped. The town opens that chat and clears it.
    var requestedChatID: String?
    private(set) var permission = "Not checked"
    private(set) var appleRegistration = "Not registered"
    private(set) var serverRegistration = "Not registered"
    private(set) var setupError: String?
    private(set) var serverSetup = "Not checked"
    private var visibility = MessagePushVisibility()

    private var session: SessionModel?
    private var deviceToken: Data?
    private var registeredToken: (token: Data, userID: String, server: String)?
    private let log = Logger(subsystem: "systems.rocky.face2face", category: "push")

    static var environment: PushEnvironment {
        #if DEBUG
            .sandbox
        #else
            .production
        #endif
    }

    /// Shows the permission prompt the first time, then refreshes the device token on every launch.
    func start(for account: Account, session: SessionModel, force: Bool = false) async {
        guard !session.isTownPreview else { return }
        self.session = session
        if force { registeredToken = nil }
        setupError = nil
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        permission = Self.permissionText(status)
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            appleRegistration = "Not requested — enable notifications in iOS Settings"
            return
        }
        if deviceToken == nil { appleRegistration = "Registering with Apple…" }
        UIApplication.shared.registerForRemoteNotifications()
        await uploadToken(for: account.user.id)
    }

    /// Stops pushes to this phone. Call while the session token is still valid.
    func signOut(client: APIClient) async {
        session = nil
        visibility.clear()
        defer {
            registeredToken = nil
            setBadge(0)
            serverRegistration = "Not registered (signed out)"
            setupError = nil
        }
        guard let token = deviceToken else { return }
        do { try await client.unregisterPushDevice(token: token) } catch {
            log.error("Could not unregister push device: \(error.localizedDescription, privacy: .public)")
        }
    }

    func setBadge(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
    }

    fileprivate func received(token: Data) async {
        deviceToken = token
        appleRegistration = "Apple device token received"
        registeredToken = nil
        guard case .ready(let account) = session?.phase else { return }
        await uploadToken(for: account.user.id)
    }

    fileprivate func registrationFailed(_ error: any Error) {
        appleRegistration = "Apple registration failed"
        setupError = error.localizedDescription
        log.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    fileprivate func arrivedInForeground() { foregroundArrivals += 1 }

    func showChat(_ chatID: String, accountID: String, owner: UUID) {
        visibility.show(chatID: chatID, accountID: accountID, owner: owner)
    }
    func hideChat(owner: UUID) { visibility.hide(owner: owner) }

    fileprivate func foregroundOptions(kind: String?, chatID: String?) -> UNNotificationPresentationOptions {
        guard let session, !session.isTownPreview, case .ready(let account) = session.phase else { return [] }
        return visibility.options(kind: kind, chatID: chatID, accountID: account.user.id)
    }

    func refreshStatus(session: SessionModel) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permission =
            Self.permissionText(settings.authorizationStatus)
            + "; alerts \(settings.alertSetting == .enabled ? "on" : "off"), sound \(settings.soundSetting == .enabled ? "on" : "off")"
        guard !session.isTownPreview else {
            serverSetup = "Preview — no real push setup tested"
            return
        }
        guard case .ready(let account) = session.phase else {
            serverSetup = "Sign in to check server setup"
            return
        }
        let server = session.serverAddress
        let summary: String
        do {
            let client = try await session.client().capturingCurrentCredential()
            let status = try await client.pushSetupStatus()
            guard try await session.client().usesSameCredential(as: client) else { return }
            let topicMatches = status.topic == Bundle.main.bundleIdentifier
            summary =
                "Provider \(status.providerConfigured ? "configured" : "not configured"); \(status.registeredDeviceCount) registered device(s). "
                + (topicMatches ? "App topic matches." : "App topic does not match this build.")
        } catch APIError.server(404) {
            summary = "Server diagnostics unavailable — deploy the matching API"
        } catch { summary = "Could not check server setup: \(error.localizedDescription)" }
        guard case .ready(let current) = session.phase, current.user.id == account.user.id,
            session.serverAddress == server, !Task.isCancelled
        else { return }
        serverSetup = summary
    }

    private static func permissionText(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized: "Allowed"
        case .provisional: "Quiet delivery (provisional permission)"
        case .ephemeral: "Allowed temporarily"
        case .denied: "Disabled in iOS Settings"
        case .notDetermined: "Permission not requested"
        @unknown default: "Unknown permission state"
        }
    }

    private func uploadToken(for userID: String) async {
        guard let token = deviceToken, let session, !session.isTownPreview else { return }
        let server = session.serverAddress
        guard case .ready(let account) = session.phase, account.user.id == userID else { return }
        if let registeredToken, registeredToken.token == token, registeredToken.userID == userID,
            registeredToken.server == server
        {
            return
        }
        serverRegistration = "Registering with server…"
        do {
            let client = try await session.client().capturingCurrentCredential()
            guard self.session === session, case .ready(let current) = session.phase,
                current.user.id == userID, session.serverAddress == server,
                try await session.client().usesSameCredential(as: client), !Task.isCancelled
            else { return }
            try await client.registerPushDevice(token: token, environment: Self.environment)
            guard self.session === session, case .ready(let current) = session.phase,
                current.user.id == userID, session.serverAddress == server, deviceToken == token
            else { return }
            guard try await session.client().usesSameCredential(as: client) else { return }
            registeredToken = (token, userID, server)
            serverRegistration = "Registered (\(Self.environment.rawValue))"
            setupError = nil
        } catch {
            guard self.session === session, case .ready(let current) = session.phase,
                current.user.id == userID, session.serverAddress == server, !Task.isCancelled
            else { return }
            serverRegistration = "Server registration failed"
            setupError = error.localizedDescription
            log.error("Could not register push device: \(error.localizedDescription, privacy: .public)")
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in await PushNotifications.shared.received(token: deviceToken) }
    }

    func application(
        _ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        Task { @MainActor in PushNotifications.shared.registrationFailed(error) }
    }

    /// Message alerts are visible outside the conversation; connection events use the in-app UI.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let info = notification.request.content.userInfo
        let kind = info["kind"] as? String
        let chatID = info["chatId"] as? String
        return await MainActor.run {
            PushNotifications.shared.arrivedInForeground()
            return PushNotifications.shared.foregroundOptions(kind: kind, chatID: chatID)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let chatID = info["kind"] as? String == "message" ? info["chatId"] as? String : nil
        await MainActor.run {
            if let chatID {
                PushNotifications.shared.requestedChatID = chatID
            } else {
                PushNotifications.shared.inboxRequested = true
            }
        }
    }
}
