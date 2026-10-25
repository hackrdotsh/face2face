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

    private var session: SessionModel?
    private var deviceToken: Data?
    private var registeredToken: (token: Data, userID: String)?
    private let log = Logger(subsystem: "systems.rocky.face2face", category: "push")

    private static var environment: PushEnvironment {
        #if DEBUG
            .sandbox
        #else
            .production
        #endif
    }

    /// Shows the permission prompt the first time, then refreshes the device token on every launch.
    func start(for account: Account, session: SessionModel) async {
        self.session = session
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        UIApplication.shared.registerForRemoteNotifications()
        await uploadToken(for: account.user.id)
    }

    /// Stops pushes to this phone. Call while the session token is still valid.
    func signOut(client: APIClient) async {
        defer {
            registeredToken = nil
            setBadge(0)
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
        guard case .ready(let account) = session?.phase else { return }
        await uploadToken(for: account.user.id)
    }

    fileprivate func registrationFailed(_ error: any Error) {
        log.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    fileprivate func arrivedInForeground() { foregroundArrivals += 1 }

    private func uploadToken(for userID: String) async {
        guard let token = deviceToken, let session, !session.isTownPreview else { return }
        if let registeredToken, registeredToken.token == token, registeredToken.userID == userID { return }
        do {
            try await session.client().registerPushDevice(token: token, environment: Self.environment)
            registeredToken = (token, userID)
        } catch {
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

    /// The bell shows new notifications while the app is open, so the system banner stays hidden.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await MainActor.run { PushNotifications.shared.arrivedInForeground() }
        return []
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
