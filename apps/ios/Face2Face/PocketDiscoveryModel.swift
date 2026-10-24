#if DEBUG
    import Face2FaceCore
    import Foundation
    import Observation
    import UIKit

    /// App-owned so switching tabs or locking the phone does not destroy an opted-in test.
    @MainActor
    @Observable
    final class PocketDiscoveryModel {
        static let shared = PocketDiscoveryModel()
        let radio = BluetoothDiscoveryService()
        private(set) var window: PocketTestWindow?
        private(set) var checkpointMessage = "No saved Pocket test."
        @ObservationIgnored private let defaults: UserDefaults
        private static let checkpointKey = "streetpass.pocketConsent.v1"

        init(defaults: UserDefaults = .standard) {
            self.defaults = defaults
            radio.onStopped = { [weak self] in self?.clearCheckpoint() }
            radio.onRestored = { [weak self] in
                self?.checkpointMessage = "iOS delivered Core Bluetooth restoration state."
            }
            guard let data = defaults.data(forKey: Self.checkpointKey) else { return }
            guard !BluetoothDiscoveryService.isSimulator,
                let saved = try? JSONDecoder().decode(PocketTestWindow.self, from: data),
                saved.remaining(uptime: ProcessInfo.processInfo.systemUptime) > 0
            else {
                defaults.removeObject(forKey: Self.checkpointKey)
                checkpointMessage = "Previous consent expired or could not be restored. Start a new test."
                return
            }
            window = saved
            checkpointMessage = "Checking whether iOS preserved the previous radio session."
            radio.prepareForRestoration(
                window: saved, applicationActive: UIApplication.shared.applicationState != .background)
        }

        var remaining: TimeInterval {
            window?.remaining(uptime: ProcessInfo.processInfo.systemUptime) ?? 0
        }

        func start() {
            guard !BluetoothDiscoveryService.isSimulator, !radio.isRequested, !radio.isRestorationPending
            else { return }
            let fresh = PocketTestWindow(uptime: ProcessInfo.processInfo.systemUptime)
            guard let data = try? JSONEncoder().encode(fresh) else { return }
            // No token, account, peer observation or credential is persisted here.
            defaults.set(data, forKey: Self.checkpointKey)
            window = fresh
            checkpointMessage = "Five-minute consent saved. Only iOS restoration callbacks may resume it."
            radio.setApplicationActive(UIApplication.shared.applicationState != .background)
            radio.start(pocketWindow: fresh)
        }

        func stop() {
            clearCheckpoint()
            radio.stop(reason: "Pocket test stopped")
        }

        func sceneChanged(active: Bool) {
            if window != nil, remaining <= 0 {
                radio.stop(reason: "Five-minute Pocket test expired")
                clearCheckpoint()
                return
            }
            radio.setApplicationActive(active)
        }

        private func clearCheckpoint() {
            defaults.removeObject(forKey: Self.checkpointKey)
            window = nil
            checkpointMessage = "Consent cleared. Start is required for another test."
        }

        var report: String {
            guard radio.session != nil else {
                return "Face2Face Pocket test — no test has started. Hardware validation pending."
            }
            return [
                "Five-minute anonymous background experiment. Hardware validation pending.",
                "Remaining consent: \(Int(ceil(remaining))) seconds",
                "Checkpoint: \(checkpointMessage)",
                "No accounts, server uploads, GPS, or identity/proximity proof.",
                "",
                radio.report,
            ].joined(separator: "\n")
        }
    }
#endif
