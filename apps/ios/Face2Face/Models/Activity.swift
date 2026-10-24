import Foundation
import Observation

/// Tracks one in-flight request and its error message for a screen.
@MainActor
@Observable
final class Activity {
    private(set) var isBusy = false
    var errorMessage: String?

    /// Runs `action` unless another one is in flight. Returns false when it failed or did not run.
    @discardableResult
    func run(_ action: () async throws -> Void) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await action()
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
