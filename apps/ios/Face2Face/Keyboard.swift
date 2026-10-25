import SwiftUI
import UIKit

@MainActor
enum Keyboard {
    /// True from the moment the keyboard starts to show until it has finished hiding.
    private(set) static var isShowing = false
    private static var observers: [NSObjectProtocol] = []

    static func startTracking() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) {
                _ in MainActor.assumeIsolated { isShowing = true }
            },
            center.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) {
                _ in MainActor.assumeIsolated { isShowing = false }
            },
        ]
    }

    /// Waits for the keyboard to finish hiding after focus is cleared. Returns at once when it is not showing.
    static func waitUntilHidden(timeout: Duration = .milliseconds(600)) async {
        guard isShowing else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in NotificationCenter.default.notifications(
                    named: UIResponder.keyboardDidHideNotification)
                {
                    return
                }
            }
            group.addTask { try? await Task.sleep(for: timeout) }
            await group.next()
            group.cancelAll()
        }
    }
}

/// Closes the keyboard when the person taps anywhere outside a text input. Taps still reach the view under them.
struct KeyboardDismissOnTap: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView {
        Keyboard.startTracking()
        return InstallerView()
    }

    func updateUIView(_ uiView: InstallerView, context: Context) {}

    final class InstallerView: UIView, UIGestureRecognizerDelegate {
        private let tap = UITapGestureRecognizer()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, tap.view !== window else { return }
            tap.addTarget(self, action: #selector(dismiss))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
        }

        @objc private func dismiss() {
            window?.endEditing(true)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool
        {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}
