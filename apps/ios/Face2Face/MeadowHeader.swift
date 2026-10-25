import SwiftUI

struct MeadowHeader: View {
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "figure.2")
                    .font(.system(size: 18, weight: .bold))
                Text("face2face")
                    .font(.system(.headline, design: .rounded, weight: .heavy))
            }
            .accessibilityElement(children: .combine)
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
