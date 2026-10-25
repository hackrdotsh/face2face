import Face2FaceCore
import UIKit

/// One finite request, always ended on completion, cancellation, or system expiry.
@MainActor
final class LimitedBackgroundExecution {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private var hasExpired = false
    private var watchdog: Task<Void, Never>?
    private let onExpiration: @MainActor () -> Void

    init?(name: String, onExpiration: @escaping @MainActor () -> Void) {
        self.onExpiration = onExpiration
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.expire()
        }
        guard identifier != .invalid, !hasExpired else {
            end()
            return nil
        }
        watchdog = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(BackgroundUploadPolicy.budgetSeconds)) } catch {
                return
            }
            self?.expire()
        }
    }

    deinit {
        watchdog?.cancel()
        let task = identifier
        if task != .invalid {
            Task { @MainActor in UIApplication.shared.endBackgroundTask(task) }
        }
    }

    func end() {
        watchdog?.cancel()
        watchdog = nil
        guard identifier != .invalid else { return }
        let task = identifier
        identifier = .invalid
        UIApplication.shared.endBackgroundTask(task)
    }

    private func expire() {
        guard !hasExpired else { return }
        hasExpired = true
        onExpiration()
        end()
    }
}
