import SwiftUI

struct MeadowHeader: View {
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 4)
            Button(action: openSettings) {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 44, height: 44)
                    .background(MeadowPalette.paper, in: Circle())
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("appSettings")
        }
        .font(.system(.subheadline, weight: .semibold))
        .buttonStyle(MeadowPressStyle())
    }
}
