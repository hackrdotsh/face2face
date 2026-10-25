import SwiftUI

/// Turns a five-minute discovery walk on and off. Matches never name the other person.
struct DiscoverySection: View {
    @Bindable var model: ConnectedDiscoveryModel

    private var isOn: Binding<Bool> {
        Binding(
            get: { model.isRunning || model.isStarting },
            set: { on in
                if on {
                    Task { await model.start() }
                } else {
                    model.stop()
                }
            })
    }

    var body: some View {
        Section {
            Toggle("Discover people nearby", isOn: isOn)
                .disabled(model.revocationPending || BluetoothDiscoveryService.isSimulator)
            if model.isRunning {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    LabeledContent("Time left") {
                        Text(
                            Duration.seconds(ceil(model.walkRemaining)), format: .time(pattern: .minuteSecond)
                        )
                        .monospacedDigit()
                    }
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
                Button(model.isRevoking ? "Stopping…" : "Finish stopping") { model.retryRevocation() }
                    .disabled(model.isRevoking)
            }
        } header: {
            Text("Discovery")
        } footer: {
            Text(
                "Runs for up to five minutes. When two phones find each other, you both get a chance to connect. A match never names either person and does not prove you were near each other."
            )
        }
    }
}
