#if DEBUG
    import SwiftUI

    @MainActor
    struct ConnectedDiscoveryView: View {
        @Environment(\.scenePhase) private var scenePhase
        @State private var model: ConnectedDiscoveryModel
        private let managesLifecycle: Bool

        init(model: ConnectedDiscoveryModel = ConnectedDiscoveryModel(), managesLifecycle: Bool = true) {
            _model = State(initialValue: model)
            self.managesLifecycle = managesLifecycle
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
                            "Sign in on Account first. Starting discovery opts you in to anonymous matches after both phones report the exchange."
                        )
                        Text(
                            "Bluetooth reports do not verify identity or physical proximity."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                if model.allowsBackground {
                    Section {
                        Text(
                            "Start unlocked. Discovery stays enabled until you stop it. iOS may delay radio events or deny background execution."
                        )
                        Text(
                            "After process death, reopen the app to resume. Only the account-bound opt-in preference is saved; radio tokens and credentials are not restored from preferences."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                Section("Account and API") {
                    if let user = model.user {
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
                    Button(model.isRefreshing ? "Refreshing…" : "Refresh account") {
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
                    if model.isEnabled || model.isStarting {
                        Button(model.isStarting ? "Cancel start" : "Stop discovery") { model.stop() }
                            .buttonStyle(.bordered)
                    } else {
                        Button(
                            model.allowsBackground
                                ? "Start discovery" : "Start connected discovery"
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
                                "Current token valid for", value: "\(Int(ceil(model.walkRemaining))) seconds"
                            )
                        }
                        LabeledContent("App", value: model.isApplicationActive ? "Foreground" : "Background")
                        LabeledContent("Background upload passes", value: "\(model.backgroundPasses)")
                        LabeledContent("Deferred passes", value: "\(model.deferredPasses)")
                        LabeledContent("Matches this walk", value: "\(model.matchCount)")
                        if let elapsed = model.firstMatchElapsed {
                            LabeledContent("First match") {
                                Text(String(format: "%.1f seconds after Start", elapsed))
                            }
                        }
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
                    LabeledContent("Matches this run", value: "\(model.matchCount)")
                    Text(
                        model.matchCount == 0
                            ? "No matches yet. Both signed-in phones must report each other within two minutes."
                            : "A match can open a chance. Check Passed in the web client."
                    )
                    .foregroundStyle(.secondary)
                } header: {
                    Text("Matches")
                } footer: {
                    Text("A match never names the other person. It does not prove you were near each other.")
                }
            }
            .navigationTitle(model.allowsBackground ? "Walk diagnostics" : "Connected test")
            .toolbar {
                if model.allowsBackground {
                    ShareLink(item: model.report) {
                        Label("Share Walk test report", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .task { if managesLifecycle { await model.refresh() } }
            .onChange(of: scenePhase) { _, phase in
                if managesLifecycle, phase == .background, !model.allowsBackground {
                    model.stop(reason: "Stopped when the app entered the background")
                }
            }
            .onDisappear { if managesLifecycle { model.viewClosed() } }
        }
    }
#endif
