import Face2FaceCore
import SwiftUI

/// Saved opt-in and current radio status are distinct. Matches never identify the peer.
struct DiscoverySection: View {
    @Bindable var model: ConnectedDiscoveryModel
    let account: Account

    private var isOn: Binding<Bool> {
        Binding(
            get: { model.isEnabled || model.isStarting },
            set: { on in
                if on {
                    model.enable(for: account)
                } else {
                    model.stop()
                }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MeadowSectionHeader(title: "Discovery")
            Toggle("Discover people nearby", isOn: isOn)
                .accessibilityIdentifier("discoveryToggle")
                .disabled(
                    (model.revocationPending && !model.isEnabled) || BluetoothDiscoveryService.isSimulator)
            if model.isEnabled {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(model.discoveryStatus)
                        .foregroundStyle(MeadowPalette.secondaryInk)
                        .accessibilityIdentifier("discoveryStatus")
                }
            }
            if model.isRunning || model.matchCount > 0 {
                LabeledContent("Matches", value: "\(model.matchCount)")
            }
            if BluetoothDiscoveryService.isSimulator {
                Text("Discovery needs a physical iPhone.").foregroundStyle(.secondary)
            }
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
            }
            if model.revocationPending {
                Button(model.isRevoking ? "Stopping…" : "Finish Stopping") { model.retryRevocation() }
                    .disabled(model.isRevoking)
            }
            Text(
                "Stays on until you turn it off. Background discovery may pause; reopen the app to resume. Matches are anonymous and do not prove physical proximity."
            )
            .font(.footnote)
            .foregroundStyle(MeadowPalette.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
