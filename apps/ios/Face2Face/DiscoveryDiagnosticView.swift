#if DEBUG
    import SwiftUI

    @MainActor
    struct DiscoveryDiagnosticView: View {
        @Environment(\.scenePhase) private var scenePhase
        @State private var discovery = BluetoothDiscoveryService()

        var body: some View {
            List {
                Section {
                    Text("Test the crossing, phone to phone.")
                        .font(.title2.bold())
                    Text(
                        "Open this screen on two iPhones. Start discovery on both, then bring them together.")
                    Text("Anonymous test tokens only. No account or API connection is needed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Discovery") {
                    Label(
                        discovery.status,
                        systemImage: discovery.isScanning && discovery.isAdvertising
                            ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    if BluetoothDiscoveryService.isSimulator {
                        Text(
                            "Bluetooth exchange requires two physical iPhones. The simulator can preview this screen only."
                        )
                        .foregroundStyle(.secondary)
                    }
                    Button(discovery.isRequested ? "Stop discovery" : "Start discovery") {
                        if discovery.isRequested {
                            discovery.stop()
                        } else {
                            discovery.start()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(BluetoothDiscoveryService.isSimulator)
                    .accessibilityHint(
                        discovery.isRequested
                            ? "Stops both Bluetooth radios used by this test."
                            : "Requests Bluetooth access and starts a fresh anonymous test session.")
                    Text(
                        "Keep this screen open and both phones unlocked. Leaving the screen or backgrounding the app stops the test."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section("Radio status") {
                    LabeledContent("Bluetooth", value: discovery.bluetoothStatus)
                    LabeledContent("Scanning", value: discovery.isScanning ? "Active" : "Stopped")
                    LabeledContent("Advertising", value: discovery.isAdvertising ? "Active" : "Stopped")
                    LabeledContent("Exchange", value: discovery.exchangeStatus)
                    if let issue = discovery.lastIssue {
                        Label(issue, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.primary)
                    }
                }

                if let session = discovery.session {
                    Section {
                        LabeledContent("Your session code") {
                            Text(session.token.shortCode)
                                .monospaced()
                                .textSelection(.enabled)
                        }
                        LabeledContent("Unique peer tokens", value: "\(session.encounters.count)")
                    } footer: {
                        Text(
                            "Compare your session code with the peer code on the other phone. Codes are truncated for diagnostics; matching codes are not identity or proximity verification."
                        )
                    }

                    Section("Received peer tokens") {
                        if session.encounters.isEmpty {
                            Text(
                                "No exchange yet. Start discovery on the other iPhone and bring the devices nearby."
                            )
                            .foregroundStyle(.secondary)
                        }
                        ForEach(session.encounters) { encounter in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(encounter.id.shortCode)
                                    .font(.body.monospaced())
                                Text(
                                    "\(encounter.elapsed, specifier: "%.1f") seconds after Start · \(encounter.observedAt.formatted(date: .omitted, time: .standard))"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                Section("Event log") {
                    if discovery.events.isEmpty {
                        Text("Start a session to see the Bluetooth handshake steps.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(discovery.events) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.message)
                            Text(event.timestamp, style: .time)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .navigationTitle("StreetPass test")
            .toolbar {
                ShareLink(item: discovery.report) {
                    Label("Share test report", systemImage: "square.and.arrow.up")
                }
            }
            .sensoryFeedback(.success, trigger: discovery.session?.encounters.count ?? 0) { old, new in
                new > old
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    discovery.stop(reason: "Stopped when the app entered the background")
                }
            }
            .onDisappear {
                discovery.stop(reason: "Stopped when the test screen closed")
            }
        }
    }
#endif
