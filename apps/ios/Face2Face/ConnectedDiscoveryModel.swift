#if DEBUG
    import Face2FaceCore
    import Foundation
    import Observation
    import UIKit

    /// Foreground diagnostics plus an explicitly started, memory-only authenticated Walk test.
    @MainActor
    @Observable
    final class ConnectedDiscoveryModel {
        static let backgroundWalk = ConnectedDiscoveryModel(allowsBackground: true)
        let allowsBackground: Bool
        let radio = BluetoothDiscoveryService()
        private(set) var user: User?
        private(set) var apiAddress = ""
        private(set) var status = "Sign in on Account, then refresh."
        private(set) var errorMessage: String?
        private(set) var isStarting = false
        private(set) var isRefreshing = false
        private(set) var isRunning = false
        private(set) var isApplicationActive = true
        private(set) var historyIsVisible = false
        private(set) var revocationPending = false
        private(set) var isRevoking = false
        private(set) var pendingUploads = 0
        private(set) var submittedReports = 0
        private(set) var discardedReports = 0
        private(set) var backgroundPasses = 0
        private(set) var deferredPasses = 0
        private(set) var encounters: [ServerEncounter] = []
        private(set) var tokenExpiresAt: Date?
        private(set) var walkEncounters: [ServerEncounter] = []
        private(set) var revealSequence = 0
        private(set) var walkEncounterCount = 0
        private(set) var firstRevealElapsed: TimeInterval?

        @ObservationIgnored private var encounterTracker: WalkEncounterTracker?

        @ObservationIgnored private var client: APIClient?
        @ObservationIgnored private var lease: DiscoveryLease?
        @ObservationIgnored private var walkPermit: AuthenticatedRadioPermit?
        @ObservationIgnored private var walkConsent: PocketTestWindow?
        @ObservationIgnored private var outbox = DiscoveryOutbox()
        @ObservationIgnored private var generation = UUID()
        @ObservationIgnored private var loop: Task<Void, Never>?
        @ObservationIgnored private var expiryWatchdog: Task<Void, Never>?
        @ObservationIgnored private var nextRotation = Date.distantFuture
        @ObservationIgnored private var nextRefresh = Date.distantPast
        @ObservationIgnored private var networkBusy = false
        @ObservationIgnored private var wantsBackgroundPass = false
        @ObservationIgnored private var backgroundPolicy = BackgroundUploadPolicy()
        @ObservationIgnored private var backgroundUpload: Task<Void, Never>?
        @ObservationIgnored private var backgroundBudget: LimitedBackgroundExecution?
        @ObservationIgnored private var backgroundPassID = UUID()
        @ObservationIgnored private var revocation: (client: APIClient, sessionId: String)?
        @ObservationIgnored private var revocationTask: Task<Void, Never>?
        @ObservationIgnored private var revocationBudget: LimitedBackgroundExecution?

        init(allowsBackground: Bool = false) {
            self.allowsBackground = allowsBackground
            radio.onEncounter = { [weak self] encounter in self?.enqueue(encounter) }
            radio.onExchangeCompleted = { [weak self] in self?.requestBackgroundPass() }
            radio.onStopped = { [weak self] in
                guard let self, self.isRunning else { return }
                self.stop(reason: self.radio.status)
            }
        }

        deinit {
            loop?.cancel()
            expiryWatchdog?.cancel()
            backgroundUpload?.cancel()
            revocationTask?.cancel()
        }

        var walkRemaining: TimeInterval {
            walkPermit?.remaining(uptime: ProcessInfo.processInfo.systemUptime) ?? 0
        }

        private func configuredClient() throws -> APIClient {
            let address = UserDefaults.standard.string(forKey: "apiAddress") ?? "http://localhost:8787"
            let configuration = try APIConfiguration(address: address, allowInsecureHTTP: true)
            apiAddress = configuration.baseURL.absoluteString
            return APIClient(
                configuration: configuration, tokens: KeychainTokenStore(server: configuration.baseURL))
        }

        func refresh() async {
            if isRunning, allowsBackground {
                historyIsVisible = false
                nextRefresh = .distantPast
                await step(operation: generation)
                return
            }
            guard !isRunning, !isStarting, !isRefreshing else { return }
            guard UIApplication.shared.isProtectedDataAvailable else {
                errorMessage = "Unlock the phone to access the saved account."
                return
            }
            isRefreshing = true
            let operation = generation
            user = nil
            encounters = []
            historyIsVisible = false
            defer { isRefreshing = false }
            do {
                let api = try await configuredClient().capturingCurrentCredential()
                let signedIn = try await api.currentUser()
                guard generation == operation else { return }
                let history = try await api.encounters()
                let contextMatches = try await api.usesSameCredential(as: configuredClient())
                guard generation == operation, UIApplication.shared.applicationState == .active,
                    UIApplication.shared.isProtectedDataAvailable, contextMatches
                else { return }
                client = api
                user = signedIn
                encounters = history
                historyIsVisible = true
                if !revocationPending {
                    status = "Ready to start an authenticated discovery session."
                    errorMessage = nil
                }
            } catch {
                guard generation == operation else { return }
                client = nil
                status =
                    error as? APIError == .unauthenticated
                    ? "Sign in on Account for this API, then refresh."
                    : "Could not load the account and encounters. Check the error below, then retry."
                errorMessage = error.localizedDescription
            }
        }

        func start() async {
            guard !isStarting, !isRunning, !isRefreshing, !revocationPending,
                !BluetoothDiscoveryService.isSimulator
            else { return }
            guard UIApplication.shared.applicationState == .active,
                UIApplication.shared.isProtectedDataAvailable
            else {
                errorMessage = "Open the app and unlock the phone before starting."
                return
            }
            isStarting = true
            isApplicationActive = true
            let operation = UUID()
            generation = operation
            errorMessage = nil
            status = "Starting an authenticated discovery session"
            defer {
                isStarting = false
                if generation != operation, !revocationPending, !isRunning { status = "Discovery stopped" }
            }
            do {
                let api = try await configuredClient().capturingCurrentCredential()
                let signedIn = try await api.currentUser()
                guard generation == operation else { return }
                // Capture before starting the radio so history cannot masquerade as a new crossing.
                let baseline = allowsBackground ? try await api.encounters() : []
                guard generation == operation else { return }
                let requestStartedAt = Date()
                let requestStartedUptime = ProcessInfo.processInfo.systemUptime
                let issued = try await api.startDiscovery()
                guard generation == operation, UIApplication.shared.applicationState == .active,
                    UIApplication.shared.isProtectedDataAvailable
                else {
                    scheduleRevocation(issued.sessionId, using: api)
                    return
                }
                client = api
                lease = issued
                let contextMatches = try await api.usesSameCredential(as: configuredClient())
                guard generation == operation else { return }
                guard contextMatches else {
                    stop(reason: "Account or API changed; refresh before starting")
                    user = nil
                    encounters = []
                    return
                }
                user = signedIn
                encounters = []
                historyIsVisible = false
                outbox = DiscoveryOutbox()
                pendingUploads = 0
                submittedReports = 0
                discardedReports = 0
                backgroundPasses = 0
                deferredPasses = 0
                backgroundPolicy = BackgroundUploadPolicy()
                if allowsBackground {
                    walkConsent = PocketTestWindow(at: requestStartedAt, uptime: requestStartedUptime)
                    encounterTracker = WalkEncounterTracker(
                        baseline: baseline, serverStartedAt: issued.serverTime)
                    walkEncounters = []
                    walkEncounterCount = 0
                    firstRevealElapsed = nil
                }
                nextRefresh = .distantPast
                isRunning = true
                let token = try applyLease(
                    issued, operation: operation, requestStartedAt: requestStartedAt,
                    requestStartedUptime: requestStartedUptime)
                radio.setApplicationActive(true)
                radio.start(token: token, authenticatedPermit: walkPermit)
                guard radio.isRequested else { throw APIError.invalidResponse }
                status =
                    allowsBackground ? "Five-minute authenticated walk active" : "Discovery session active"
                startForegroundLoop(operation: operation)
            } catch {
                guard generation == operation else { return }
                if lease != nil {
                    stop(reason: "Discovery could not start")
                } else {
                    status = "Discovery could not start"
                }
                errorMessage = error.localizedDescription
            }
        }

        private func startForegroundLoop(operation: UUID) {
            loop?.cancel()
            guard isRunning, isApplicationActive else { return }
            loop = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, self.isRunning, self.generation == operation else { return }
                    await self.step(operation: operation)
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
            }
        }

        private func applyLease(
            _ issued: DiscoveryLease, operation: UUID, requestStartedAt: Date,
            requestStartedUptime: TimeInterval
        ) throws -> DiscoveryToken {
            let token = try issued.validatedToken()
            var deadline = min(
                issued.tokenDeadline(requestStartedAt: requestStartedAt),
                issued.sessionDeadline(requestStartedAt: requestStartedAt))
            if let consent = walkConsent {
                let validity = try DiscoveryTokenValidity(
                    lease: issued, requestStartedAt: requestStartedAt,
                    requestStartedUptime: requestStartedUptime)
                let permit = AuthenticatedRadioPermit(validity: validity, consent: consent)
                let remaining = permit.remaining(uptime: ProcessInfo.processInfo.systemUptime)
                guard remaining > 0 else { throw APIError.invalidResponse }
                walkPermit = permit
                deadline = Date().addingTimeInterval(remaining)
            }
            guard deadline > Date() else { throw APIError.invalidResponse }
            lease = issued
            tokenExpiresAt = deadline
            nextRotation =
                issued.expiresAt == issued.sessionExpiresAt
                ? .distantFuture : Date().addingTimeInterval(120)
            expiryWatchdog?.cancel()
            expiryWatchdog = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) } catch {
                    return
                }
                guard let self, self.isRunning, self.generation == operation,
                    self.lease?.token == issued.token
                else { return }
                self.stop(reason: "Discovery consent or token reached its safe expiry deadline")
            }
            return token
        }

        func sceneChanged(active: Bool) {
            guard allowsBackground else { return }
            isApplicationActive = active
            historyIsVisible = false
            radio.setApplicationActive(active)
            if !active {
                if isStarting {
                    stop(reason: "Start canceled when the app entered the background")
                    return
                }
                loop?.cancel()
                loop = nil
                if isRunning { requestBackgroundPass() }
            } else if isRunning {
                cancelBackgroundPass()
                guard walkRemaining > 0 else {
                    stop(reason: "Authenticated walk consent or token expired")
                    return
                }
                nextRefresh = .distantPast
                startForegroundLoop(operation: generation)
            }
        }

        func viewClosed() {
            historyIsVisible = false
            if !allowsBackground { stop(reason: "Stopped when the connected test closed") }
        }

        private func enqueue(_ encounter: DiscoveryEncounter) {
            guard isRunning, lease != nil else { return }
            if outbox.enqueue(encounter.id) {
                pendingUploads = outbox.pending.count
            } else {
                errorMessage = "This session has reached its report limit. Stop and start a fresh session."
            }
        }

        private func requestBackgroundPass() {
            guard allowsBackground, isRunning, !isApplicationActive, outbox.nextReady() != nil else { return }
            wantsBackgroundPass = true
            launchBackgroundPassIfIdle()
        }

        private func launchBackgroundPassIfIdle() {
            guard wantsBackgroundPass, !networkBusy, backgroundUpload == nil,
                allowsBackground, isRunning, !isApplicationActive, walkRemaining > 0
            else { return }
            wantsBackgroundPass = false
            guard backgroundPolicy.begin(at: ProcessInfo.processInfo.systemUptime) else {
                deferredPasses += 1
                return
            }
            let operation = generation
            let passID = UUID()
            backgroundPassID = passID
            guard
                let budget = LimitedBackgroundExecution(
                    name: "StreetPass encounter upload",
                    onExpiration: { [weak self] in
                        self?.cancelBackgroundPass()
                    })
            else {
                deferredPasses += 1
                errorMessage =
                    "iOS denied background execution. Reports wait for the next event or foreground."
                return
            }
            backgroundBudget = budget
            backgroundPasses += 1
            backgroundUpload = Task { [weak self] in
                guard let self else {
                    budget.end()
                    return
                }
                defer {
                    budget.end()
                    if self.backgroundPassID == passID {
                        self.backgroundBudget = nil
                        self.backgroundUpload = nil
                        self.launchBackgroundPassIfIdle()
                    }
                }
                await self.step(operation: operation, background: true)
            }
        }

        private func cancelBackgroundPass() {
            backgroundPassID = UUID()
            backgroundUpload?.cancel()
            backgroundUpload = nil
            backgroundBudget?.end()
            backgroundBudget = nil
            wantsBackgroundPass = false
        }

        private func step(operation: UUID, background: Bool = false) async {
            guard isRunning, generation == operation, !networkBusy, let api = client, let current = lease
            else { return }
            guard background ? (!isApplicationActive && walkRemaining > 0) : isApplicationActive else {
                return
            }
            networkBusy = true
            defer {
                networkBusy = false
                launchBackgroundPassIfIdle()
            }
            if !background {
                guard UIApplication.shared.isProtectedDataAvailable else {
                    historyIsVisible = false
                    return
                }
                do {
                    let contextMatches = try await api.usesSameCredential(as: configuredClient())
                    guard isRunning, generation == operation, !Task.isCancelled else { return }
                    guard contextMatches else {
                        stop(reason: "Account or API changed; start a fresh discovery session")
                        user = nil
                        encounters = []
                        return
                    }
                } catch {
                    historyIsVisible = false
                    errorMessage = "Unlock and refresh to confirm the current account."
                    return
                }
                if Date() >= nextRotation {
                    nextRotation = Date().addingTimeInterval(5)
                    do {
                        let startedAt = Date()
                        let uptime = ProcessInfo.processInfo.systemUptime
                        let rotated = try await api.rotateDiscovery(sessionId: current.sessionId)
                        guard isRunning, generation == operation, isApplicationActive, !Task.isCancelled
                        else { return }
                        let token = try applyLease(
                            rotated, operation: operation, requestStartedAt: startedAt,
                            requestStartedUptime: uptime)
                        radio.rotateToken(to: token, authenticatedPermit: walkPermit)
                        errorMessage = nil
                    } catch is CancellationError { return } catch {
                        guard isRunning, generation == operation else { return }
                        if error as? APIError == .unauthenticated || error as? APIError == .server(410) {
                            stop(reason: "The authenticated discovery session ended")
                            return
                        }
                        errorMessage = "Token refresh failed. Radio access ends at the current safe deadline."
                    }
                }
            }

            for _ in 0..<(background ? BackgroundUploadPolicy.maximumReports : 1) {
                guard isRunning, generation == operation, !Task.isCancelled,
                    !background || (!isApplicationActive && walkRemaining > 0),
                    let pending = outbox.nextReady()
                else { break }
                do {
                    _ = try await api.observeEncounter(
                        sessionId: current.sessionId, peerToken: pending.peerToken, observationId: pending.id)
                    guard isRunning, generation == operation, !Task.isCancelled else { return }
                    outbox.acknowledge(pending.id)
                    submittedReports += 1
                    errorMessage = nil
                    nextRefresh = .distantPast
                } catch is CancellationError { return } catch {
                    guard isRunning, generation == operation, !Task.isCancelled else { return }
                    if error as? APIError == .unauthenticated {
                        stop(reason: "Sign in again to continue discovery")
                        user = nil
                        encounters = []
                        return
                    }
                    if let apiError = error as? APIError,
                        [.server(400), .server(409), .server(410)].contains(apiError)
                    {
                        outbox.acknowledge(pending.id)
                        discardedReports += 1
                        errorMessage =
                            "A report was rejected because its token or session was no longer valid."
                    } else {
                        let kept = outbox.failed(pending.id, rateLimited: error as? APIError == .server(429))
                        if !kept { discardedReports += 1 }
                        errorMessage =
                            kept
                            ? "Upload deferred; its observation ID is preserved."
                            : "A report was discarded after five failed uploads."
                    }
                }
                pendingUploads = outbox.pending.count
            }

            guard !background, isRunning, generation == operation, isApplicationActive,
                !Task.isCancelled, Date() >= nextRefresh
            else { return }
            nextRefresh = Date().addingTimeInterval(5)
            do {
                let history = try await api.encounters()
                let contextMatches = try await api.usesSameCredential(as: configuredClient())
                guard isRunning, generation == operation, isApplicationActive, !Task.isCancelled else {
                    return
                }
                guard contextMatches else {
                    stop(reason: "Account or API changed; start a fresh discovery session")
                    user = nil
                    encounters = []
                    return
                }
                encounters = history
                historyIsVisible = true
                if allowsBackground, var tracker = encounterTracker {
                    let additions = tracker.ingest(history)
                    encounterTracker = tracker
                    walkEncounters = tracker.encounters
                    walkEncounterCount = tracker.encounters.count
                    if !additions.isEmpty {
                        revealSequence += additions.count
                        if firstRevealElapsed == nil, let consent = walkConsent {
                            firstRevealElapsed = max(
                                0, ProcessInfo.processInfo.systemUptime - consent.startedUptime)
                        }
                    }
                }
            } catch is CancellationError { return } catch {
                historyIsVisible = false
                if error as? APIError == .unauthenticated {
                    stop(reason: "Sign in again to view encounters")
                    user = nil
                    encounters = []
                } else {
                    errorMessage = "Could not refresh encounters. Retrying while discovery stays active."
                }
            }
        }

        var report: String {
            [
                "Authenticated Walk experiment — hardware validation pending.",
                "Names are account claims; observations do not verify physical proximity.",
                "Background passes: \(backgroundPasses); deferred: \(deferredPasses)",
                "Submitted: \(submittedReports); queued: \(pendingUploads); discarded: \(discardedReports)",
                "Remaining permit: \(Int(ceil(walkRemaining))) seconds",
                "New server encounters this walk: \(walkEncounterCount)",
                "First reciprocal reveal: \(firstRevealElapsed.map { String(format: "%.1f seconds after Start", $0) } ?? "none")",
                "Status: \(status)",
                "",
                radio.report,
            ].joined(separator: "\n")
        }

        func stop(reason: String = "Discovery stopped") {
            generation = UUID()
            loop?.cancel()
            expiryWatchdog?.cancel()
            loop = nil
            expiryWatchdog = nil
            isRunning = false
            historyIsVisible = false
            cancelBackgroundPass()
            radio.stop(reason: reason)
            outbox = DiscoveryOutbox()
            pendingUploads = 0
            tokenExpiresAt = nil
            walkPermit = nil
            walkConsent = nil
            encounterTracker = nil
            walkEncounters = []
            if let issued = lease, let api = client {
                lease = nil
                scheduleRevocation(issued.sessionId, using: api)
            } else if !revocationPending {
                status = isStarting ? "Canceling discovery start" : reason
            }
        }

        private func scheduleRevocation(_ sessionId: String, using api: APIClient) {
            revocation = (api, sessionId)
            revocationPending = true
            status = "Radio stopped; revoking the server session"
            retryRevocation()
        }

        func retryRevocation() {
            guard !isRevoking, let pending = revocation else { return }
            isRevoking = true
            if UIApplication.shared.applicationState == .background {
                guard
                    let budget = LimitedBackgroundExecution(
                        name: "StreetPass session revocation",
                        onExpiration: { [weak self] in
                            self?.revocationTask?.cancel()
                            self?.revocationBudget?.end()
                            self?.revocationBudget = nil
                            self?.status = "Radio stopped; server revocation pending"
                        })
                else {
                    isRevoking = false
                    status = "Radio stopped; server revocation pending"
                    return
                }
                revocationBudget = budget
            }
            revocationTask = Task { [weak self] in
                defer {
                    self?.isRevoking = false
                    self?.revocationBudget?.end()
                    self?.revocationBudget = nil
                }
                do {
                    try await pending.client.stopDiscovery(sessionId: pending.sessionId)
                    guard let self, self.revocation?.sessionId == pending.sessionId else { return }
                    self.revocation = nil
                    self.revocationPending = false
                    self.status = "Discovery stopped; server session revoked"
                    self.errorMessage = nil
                } catch is CancellationError {
                    self?.status = "Radio stopped; server revocation pending"
                } catch {
                    guard let self, self.revocation?.sessionId == pending.sessionId else { return }
                    if error as? APIError == .unauthenticated {
                        self.revocation = nil
                        self.revocationPending = false
                        self.status = "Radio stopped; server revocation was not confirmed"
                        self.errorMessage =
                            "Authentication ended. Previously published tokens expire within five minutes."
                    } else {
                        self.status = "Radio stopped; server revocation pending"
                        self.errorMessage =
                            "Retry revocation when online. Published tokens expire within five minutes."
                    }
                }
            }
        }
    }
#endif
