import SwiftUI

extension View {
    func activityAlert(_ activity: Activity) -> some View {
        alert(
            "Something went wrong",
            isPresented: Binding(
                get: { activity.errorMessage != nil },
                set: { if !$0 { activity.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { activity.errorMessage = nil }
        } message: {
            Text(activity.errorMessage ?? "Try again.")
        }
        .overlay { if activity.isBusy { ProgressView().accessibilityLabel("Loading") } }
    }
}
