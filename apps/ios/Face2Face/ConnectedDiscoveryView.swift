#if DEBUG
    import SwiftUI

    @MainActor
    struct ConnectedDiscoveryView: View {
        @Environment(\.scenePhase) private var scenePhase
        @State private var model: ConnectedDiscoveryModel

        init(model: ConnectedDiscoveryModel = ConnectedDiscoveryModel()) {
            _model = State(initialValue: model)
        }

        var body: some View {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            model.allowsBackground
                                ? "Take your encounter test for a walk."
                                : "Turn a token exchange into an encounter."
                        )
                        .font(.title2.bold())
                        Text(
                            "Sign in on Account first. Starting discovery opts you in to sharing your name after both devices report the exchange."
                        )
                        Text(
                            "Names are account claims. Bluetooth reports do not verify identity or physical proximity."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                if model.allowsBackground {
                    Section {
                        Text(
                            "Start unlocked. This memory-only test can run for up to five minutes when you leave the tab or lock the phone. iOS may delay radio events or deny uploads."
                        )
                        Text(
                            "No signed-in walk is restored after process death. Tokens still expire; a fresh Start is required."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                Section("Account and API") {
                    if let user = model.user, model.historyIsVisible {
                        LabeledContent("Signed in", value: user.name)
                    } else {
                        Text("Refresh to confirm the current account.")
                    }
                    if !model.apiAddress.isEmpty {
                        Text(model.apiAddress)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Button(model.isRefreshing ? "Refreshing…" : "Refresh account and encounters") {
                        Task { await model.refresh() }
                    }
                    .disabled(
                        model.isRefreshing || (!model.allowsBackground && model.isRunning) || model.isStarting
                    )
                }

                Section("Discovery session") {
                    Text(model.status)
                    if BluetoothDiscoveryService.isSimulator {
                        Text(
                            "Use two physical iPhones for the Bluetooth exchange. The API contract can be tested independently."
                        )
                        .foregroundStyle(.secondary)
                    }
                    if model.isRunning || model.isStarting {
                        Button(model.isStarting ? "Cancel start" : "Stop discovery") { model.stop() }
                            .buttonStyle(.bordered)
                    } else {
                        Button(
                            model.allowsBackground
                                ? "Start five-minute Walk test" : "Start connected discovery"
                        ) { Task { await model.start() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            model.user == nil || model.isRefreshing || model.revocationPending
                                || BluetoothDiscoveryService.isSimulator)
                    }
                    if model.revocationPending {
                        Button(model.isRevoking ? "Revoking…" : "Retry server revocation") {
                            model.retryRevocation()
                        }
                        .disabled(model.isRevoking)
                    }
                    if let message = model.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                    }
                    Text(
                        model.allowsBackground
                            ? "Leaving this tab keeps the walk active. Stop ends the radio immediately and attempts server revocation."
                            : "Keep this screen open and phones unlocked. Leaving stops the radio and requests server revocation."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section("Radio and uploads") {
                    if model.allowsBackground {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            LabeledContent(
                                "Safe walk time remaining", value: "\(Int(ceil(model.walkRemaining))) seconds"
                            )
                        }
                        LabeledContent("App", value: model.isApplicationActive ? "Foreground" : "Background")
                        LabeledContent("Background upload passes", value: "\(model.backgroundPasses)")
                        LabeledContent("Deferred passes", value: "\(model.deferredPasses)")
                    }
                    Text(model.radio.status)
                    LabeledContent("Bluetooth", value: model.radio.bluetoothStatus)
                    LabeledContent("Scanning", value: model.radio.isScanning ? "Active" : "Stopped")
                    LabeledContent("Advertising", value: model.radio.isAdvertising ? "Active" : "Stopped")
                    LabeledContent("Exchange", value: model.radio.exchangeStatus)
                    if let issue = model.radio.lastIssue { Text(issue) }
                    if let session = model.radio.session {
                        LabeledContent("Session code", value: session.token.shortCode)
                    }
                    if let expiry = model.tokenExpiresAt {
                        LabeledContent(
                            "Safe token deadline", value: expiry.formatted(date: .omitted, time: .standard))
                    }
                    LabeledContent("Queued reports", value: "\(model.pendingUploads)")
                    LabeledContent("Submitted reports", value: "\(model.submittedReports)")
                    LabeledContent("Discarded reports", value: "\(model.discardedReports)")
                }

                Section {
                    if !model.historyIsVisible || model.encounters.isEmpty {
                        Text(
                            "No reciprocal encounters yet. Both signed-in phones must submit an exchange before a name appears."
                        )
                        .foregroundStyle(.secondary)
                    }
                    ForEach(model.historyIsVisible ? model.encounters : []) { encounter in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(encounter.peer.name).font(.headline)
                            Text("Both devices reported an exchange")
                            Text(encounter.lastSeenDate, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Recent server encounters")
                } footer: {
                    Text(
                        "Up to 50 encounters from the last 24 hours. These are encounters, not friendship requests."
                    )
                }
            }
            .navigationTitle(model.allowsBackground ? "Walk test" : "Connected test")
            .toolbar {
                if model.allowsBackground {
                    ShareLink(item: model.report) {
                        Label("Share Walk test report", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .task { await model.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background, !model.allowsBackground {
                    model.stop(reason: "Stopped when the app entered the background")
                }
            }
            .onDisappear { model.viewClosed() }
        }
    }
#endif
