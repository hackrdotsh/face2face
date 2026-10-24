#if DEBUG
    import Face2FaceCore
    import SwiftUI

    /// The live walk stays focused on the crossing. Detailed radio controls live one level below.
    @MainActor
    struct WalkDiscoveryView: View {
        @Bindable var model: ConnectedDiscoveryModel
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var latestEncounter: ServerEncounter? {
            model.historyIsVisible ? model.walkEncounters.first : nil
        }

        private var headline: String {
            if model.isStarting { return "Starting your walk…" }
            guard model.isRunning else { return "Your next hello starts here." }
            if model.submittedReports > 0 { return "Waiting for the other report." }
            if model.pendingUploads > 0 { return "Sending your encounter." }
            if !model.radio.isScanning || !model.radio.isAdvertising { return "Getting Bluetooth ready." }
            return "Ready for a crossing."
        }

        private var explanation: String {
            if model.isStarting { return "Checking your account and creating a fresh session." }
            guard model.isRunning else {
                return "Open Walk on both iPhones. Start together, then bring the phones nearby."
            }
            if model.submittedReports > 0 {
                return
                    "Your report reached the server. A new name appears after both accounts report the exchange."
            }
            if model.pendingUploads > 0 {
                return
                    "A Bluetooth token arrived. The report needs to reach the server before an encounter can appear."
            }
            return "Begin with both screens open. Background and locked-screen behavior still need testing."
        }

        var body: some View {
            List {
                Section {
                    if let encounter = latestEncounter {
                        WalkEncounterReveal(encounter: encounter)
                            .id(encounter.id)
                            .transition(.opacity)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(headline)
                                .font(.title2.bold())
                            Text(explanation)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }

                    if model.isRunning || model.isStarting {
                        Button(model.isStarting ? "Cancel start" : "Stop walk", role: .destructive) {
                            model.stop()
                        }
                        .frame(minHeight: 44)
                    } else {
                        Button("Start five-minute walk") { Task { await model.start() } }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .frame(minHeight: 44)
                            .disabled(
                                model.user == nil || !model.historyIsVisible || model.isRefreshing
                                    || model.revocationPending || BluetoothDiscoveryService.isSimulator)
                    }
                } footer: {
                    Text(
                        "Starting opts you in to revealing your account name after reciprocal reports. These reports do not verify identity or physical proximity."
                    )
                }

                if model.isRunning {
                    Section {
                        WalkProgressRow(title: "Walk started", isComplete: true)
                        WalkProgressRow(
                            title: "Bluetooth token received",
                            isComplete: !(model.radio.session?.encounters.isEmpty ?? true))
                        WalkProgressRow(
                            title: "Report accepted by server", isComplete: model.submittedReports > 0)
                        WalkProgressRow(
                            title: "New reciprocal encounter",
                            isComplete: model.historyIsVisible && !model.walkEncounters.isEmpty)
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            LabeledContent("Safe time remaining") {
                                Text("\(Int(ceil(model.walkRemaining))) seconds")
                                    .monospacedDigit()
                            }
                        }
                    } header: {
                        Text("This walk")
                    } footer: {
                        Text(
                            "Leaving this tab keeps the walk active until its consent or token expires. Stop ends the radio immediately."
                        )
                    }
                } else {
                    Section("Before you start") {
                        if let user = model.user, model.historyIsVisible {
                            LabeledContent("Account", value: user.name)
                        } else {
                            Text("Sign in on the Account tab, then refresh here.")
                        }
                        Button(model.isRefreshing ? "Checking account…" : "Refresh account") {
                            Task { await model.refresh() }
                        }
                        .disabled(model.isRefreshing || model.isStarting)
                        if BluetoothDiscoveryService.isSimulator {
                            Text(
                                "Start requires two physical iPhones. This simulator cannot exchange Bluetooth tokens."
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                        Text("Start unlocked. Up to five minutes; no automatic restart after process death.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if model.historyIsVisible, model.walkEncounters.count > 1 {
                    Section("Also encountered this walk") {
                        ForEach(model.walkEncounters.dropFirst()) { encounter in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(encounter.peer.name).font(.headline)
                                Text("Reciprocal report recorded")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                if model.revocationPending || model.errorMessage != nil || model.radio.lastIssue != nil {
                    Section("Needs attention") {
                        if let issue = model.errorMessage {
                            Label(issue, systemImage: "exclamationmark.triangle")
                        }
                        if model.isRunning, let issue = model.radio.lastIssue { Text(issue) }
                        if model.revocationPending {
                            Text(model.status)
                            Button(model.isRevoking ? "Revoking…" : "Retry server revocation") {
                                model.retryRevocation()
                            }
                            .disabled(model.isRevoking)
                        } else if model.isRunning {
                            Button("Refresh encounters") { Task { await model.refresh() } }
                        }
                    }
                }

                Section {
                    NavigationLink {
                        ConnectedDiscoveryView(model: model, managesLifecycle: false)
                    } label: {
                        Label("Diagnostics and encounter history", systemImage: "waveform.path.ecg")
                    }
                } footer: {
                    Text("Experimental • two-phone validation pending")
                }
            }
            .navigationTitle("Walk")
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: latestEncounter?.id)
            .sensoryFeedback(.success, trigger: model.revealSequence) { old, new in
                new > old && model.historyIsVisible && model.isApplicationActive
            }
            .task { await model.refresh() }
            .onDisappear { model.viewClosed() }
        }
    }

    private struct WalkProgressRow: View {
        let title: String
        let isComplete: Bool

        var body: some View {
            Label(title, systemImage: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isComplete ? Color.primary : Color.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title): \(isComplete ? "complete" : "waiting")")
        }
    }

    struct WalkEncounterReveal: View {
        let encounter: ServerEncounter

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Label("Encounter recorded", systemImage: "person.2.wave.2")
                    .font(.headline)
                Text(encounter.peer.name)
                    .font(.largeTitle.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Both accounts reported a Bluetooth exchange.")
                Text(encounter.lastSeenDate, style: .time)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
        }
    }
#endif
