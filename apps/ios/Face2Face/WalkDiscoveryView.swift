#if DEBUG
    import Face2FaceCore
    import SwiftUI

    /// The live walk stays focused on the crossing. Detailed radio controls live one level below.
    @MainActor
    struct WalkDiscoveryView: View {
        @Bindable var model: ConnectedDiscoveryModel
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var hasMatch: Bool { model.matchCount > 0 }

        private var headline: String {
            if model.isStarting { return "Starting your walk…" }
            guard model.isRunning else { return "Your next hello starts here." }
            if model.submittedReports > 0 { return "Waiting for the other report." }
            if model.pendingUploads > 0 { return "Sending your report." }
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
                    "Your report reached the server. A match appears after both phones report each other."
            }
            if model.pendingUploads > 0 {
                return
                    "A Bluetooth token arrived. The report needs to reach the server before a match can appear."
            }
            return "Begin with both screens open. Background and locked-screen behavior still need testing."
        }

        var body: some View {
            List {
                Section {
                    if hasMatch {
                        WalkMatchReveal(count: model.matchCount)
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

                    if model.isEnabled || model.isStarting {
                        Button(model.isStarting ? "Cancel start" : "Stop walk", role: .destructive) {
                            model.stop()
                        }
                        .frame(minHeight: 44)
                    } else {
                        Button("Start discovery") { Task { await model.start() } }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .frame(minHeight: 44)
                            .disabled(
                                model.user == nil || model.isRefreshing
                                    || model.revocationPending || BluetoothDiscoveryService.isSimulator)
                    }
                } footer: {
                    Text(
                        "Starting opts you in to anonymous matching. A match opens a chance without naming either person. Reports do not verify physical proximity."
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
                            title: "Match recorded", isComplete: hasMatch)
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(model.discoveryStatus)
                            LabeledContent("Current token valid for") {
                                Text("\(Int(ceil(model.walkRemaining))) seconds")
                                    .monospacedDigit()
                            }
                        }
                    } header: {
                        Text("This walk")
                    } footer: {
                        Text(
                            "Discovery stays enabled until Stop. The radio pauses if it cannot renew its short-lived token."
                        )
                    }
                } else {
                    Section("Before you start") {
                        if let user = model.user {
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
                        Text(
                            "Start unlocked. After the app is terminated, reopen it to resume discovery for the same account."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                        }
                    }
                }

                Section {
                    NavigationLink {
                        ConnectedDiscoveryView(model: model, managesLifecycle: false)
                    } label: {
                        Label("Diagnostics", systemImage: "waveform.path.ecg")
                    }
                } footer: {
                    Text("Experimental • two-phone validation pending")
                }
            }
            .navigationTitle("Walk")
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.matchCount)
            .sensoryFeedback(.success, trigger: model.matchCount) { old, new in
                new > old && model.isApplicationActive
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

    struct WalkMatchReveal: View {
        let count: Int

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Label("Match recorded", systemImage: "person.2.wave.2")
                    .font(.headline)
                Text(count == 1 ? "1 match this walk" : "\(count) matches this walk")
                    .font(.largeTitle.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(
                    "Both phones reported each other. A match can open a chance. Check Passed in the web client."
                )
            }
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
        }
    }
#endif
