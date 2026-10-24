#if DEBUG
    import SwiftUI

    @MainActor
    struct PocketDiscoveryView: View {
        let model: PocketDiscoveryModel

        var body: some View {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Try the crossing with your phone in your pocket.")
                            .font(.title2.bold())
                        Text("A five-minute anonymous radio experiment. No account, API, or name sharing.")
                        Text(
                            "iOS may delay or skip discovery while locked. This screen cannot prove that pocket discovery works."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                Section("Timed consent") {
                    Text(model.radio.status)
                    if model.radio.isRequested {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text("\(Int(ceil(model.remaining))) seconds of consent remaining")
                                .monospacedDigit()
                        }
                        Button("Stop Pocket test") { model.stop() }
                            .buttonStyle(.borderedProminent)
                    } else if model.radio.isRestorationPending {
                        Text("Waiting for iOS to supply preserved radio state.")
                        Button("Discard saved test") { model.stop() }
                    } else {
                        Button("Start five-minute Pocket test") { model.start() }
                            .buttonStyle(.borderedProminent)
                            .disabled(BluetoothDiscoveryService.isSimulator)
                    }
                    if BluetoothDiscoveryService.isSimulator {
                        Text("Two physical iPhones are required. The simulator previews the screen only.")
                            .foregroundStyle(.secondary)
                    }
                    Text(
                        "This test can continue when you leave this tab or background the app. Starting another radio test ends it. Stop clears saved consent."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                Section("Radio diagnostics") {
                    LabeledContent(
                        "App", value: model.radio.isApplicationActive ? "Foreground" : "Background")
                    LabeledContent("Bluetooth", value: model.radio.bluetoothStatus)
                    LabeledContent("Scan requested", value: model.radio.isScanning ? "Yes" : "No")
                    LabeledContent("Advertising registered", value: model.radio.isAdvertising ? "Yes" : "No")
                    LabeledContent("Exchange", value: model.radio.exchangeStatus)
                    LabeledContent("iOS restore callbacks", value: "\(model.radio.restorationCallbacks)")
                    if let issue = model.radio.lastIssue { Text(issue) }
                    Text(model.checkpointMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let session = model.radio.session {
                    Section("Anonymous exchange results") {
                        LabeledContent("Your current code", value: session.token.shortCode)
                        LabeledContent("Unique tokens this process", value: "\(session.encounters.count)")
                        if session.encounters.isEmpty {
                            Text(
                                "Start Pocket test on both phones, then background or lock one phone before bringing them together."
                            )
                            .foregroundStyle(.secondary)
                        }
                        ForEach(session.encounters) { encounter in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(encounter.id.shortCode).font(.body.monospaced())
                                Text(
                                    "\(encounter.elapsed, specifier: "%.1f") seconds since the original Start"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                Section("Event log") {
                    if model.radio.events.isEmpty {
                        Text("No radio events yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.radio.events) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.message)
                            Text(event.timestamp, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Section {
                    Text(
                        "A suspended timer may not fire. Every resumed Bluetooth operation checks consent expiry before exchanging tokens. Force-quitting is not supported as a way to keep discovery running."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Pocket test")
            .toolbar {
                ShareLink(item: model.report) {
                    Label("Share Pocket test report", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
#endif
