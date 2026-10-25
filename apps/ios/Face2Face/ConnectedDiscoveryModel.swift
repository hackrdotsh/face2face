import Face2FaceCore
import Foundation
import Observation
import UIKit

/// Ongoing opt-in discovery; credentials and radio permits remain memory-only.
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
    private(set) var revocationPending = false
    private(set) var isRevoking = false
    private(set) var pendingUploads = 0
    private(set) var submittedReports = 0
    private(set) var discardedReports = 0
    private(set) var backgroundPasses = 0
    private(set) var deferredPasses = 0
    private(set) var tokenExpiresAt: Date?
    private(set) var optIn: DiscoveryOptIn?
    /// Matches recorded during the current run. Receipts never say who the peer was.
    private(set) var matchCount = 0
    private(set) var firstMatchElapsed: TimeInterval?
    /// Reciprocal reports that opened no chance because the two people share no interests.
    private(set) var noSharedInterestCount = 0
    @ObservationIgnored private var matches = WalkMatchTracker()
    @ObservationIgnored private var unshared = WalkMatchTracker(counting: .noSharedInterests)
    @ObservationIgnored private var startedUptime: TimeInterval = 0

    @ObservationIgnored private var client: APIClient?
    @ObservationIgnored private var lease: DiscoveryLease?
    @ObservationIgnored private var walkPermit: AuthenticatedRadioPermit?
    @ObservationIgnored private var walkConsent: DiscoveryConsent?
    @ObservationIgnored private var outbox = DiscoveryOutbox()
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var expiryWatchdog: Task<Void, Never>?
    @ObservationIgnored private var nextRotation = Date.distantFuture
    @ObservationIgnored private var networkBusy = false
    @ObservationIgnored private var wantsBackgroundPass = false
    @ObservationIgnored private var backgroundPolicy = BackgroundUploadPolicy()
    @ObservationIgnored private var backgroundUpload: Task<Void, Never>?
    @ObservationIgnored private var backgroundBudget: LimitedBackgroundExecution?
    @ObservationIgnored private var backgroundPassID = UUID()
    @ObservationIgnored private var revocation: (client: APIClient, sessionId: String)?
    @ObservationIgnored private var revocationTask: Task<Void, Never>?
    @ObservationIgnored private var revocationBudget: LimitedBackgroundExecution?
    @ObservationIgnored private var retryStart: Task<Void, Never>?
    @ObservationIgnored private var pausingRadio = false
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let clientFactory: ((APIConfiguration) -> APIClient)?
    @ObservationIgnored private let canAccessCredentials: () -> Bool
    @ObservationIgnored private let supportsBluetooth: Bool
    @ObservationIgnored private let automaticallyRefreshes: Bool
    private static let preferenceKey = "discoveryOptIn"

    init(
        allowsBackground: Bool = false, preferences: UserDefaults = .standard,
        clientFactory: ((APIConfiguration) -> APIClient)? = nil,
        canAccessCredentials: @escaping () -> Bool = {
            UIApplication.shared.applicationState == .active && UIApplication.shared.isProtectedDataAvailable
        },
        supportsBluetooth: Bool = !BluetoothDiscoveryService.isSimulator,
        automaticallyRefreshes: Bool = true
    ) {
        self.allowsBackground = allowsBackground
        self.preferences = preferences
        self.clientFactory = clientFactory
        self.canAccessCredentials = canAccessCredentials
        self.supportsBluetooth = supportsBluetooth
        self.automaticallyRefreshes = automaticallyRefreshes
        if allowsBackground, let data = preferences.data(forKey: Self.preferenceKey) {
            optIn = try? JSONDecoder().decode(DiscoveryOptIn.self, from: data)
        }
        radio.onEncounter = { [weak self] encounter in self?.enqueue(encounter) }
        radio.onExchangeCompleted = { [weak self] in self?.requestBackgroundPass() }
        radio.onActivity = { [weak self] in self?.requestBackgroundPass() }
        radio.onPermissionDenied = { [weak self] in self?.stop(reason: "Bluetooth permission was revoked") }
        radio.onStopped = { [weak self] in
            guard let self, self.isRunning, !self.pausingRadio else { return }
            if self.allowsBackground, self.radio.stopCause != .preempted {
                self.pause(reason: "Paused — waiting to renew discovery")
                if self.radio.stopCause == .failed { self.nextRotation = Date().addingTimeInterval(15) }
            } else {
                self.stop(reason: self.radio.status)
            }
        }
    }

    deinit {
        loop?.cancel()
        expiryWatchdog?.cancel()
        backgroundUpload?.cancel()
        revocationTask?.cancel()
        retryStart?.cancel()
    }

    var isEnabled: Bool { allowsBackground ? optIn != nil : isRunning || isStarting }

    var discoveryStatus: String {
        guard isEnabled else { return "Off" }
        if isStarting { return "Starting…" }
        guard isRunning, radio.isRequested, walkRemaining > 0 else { return "Paused — waiting to resume" }
        if !radio.isScanning || !radio.isAdvertising { return "Paused — \(radio.bluetoothStatus)" }
        return isApplicationActive ? "Discovering" : "Background — best effort"
    }

    func enable(for account: Account) {
        guard allowsBackground, !revocationPending else { return }
        do {
            let configuration = try APIConfiguration(
                address: preferences.string(forKey: "apiAddress") ?? "",
                allowInsecureHTTP: Self.allowsInsecureHTTP)
            let preference = DiscoveryOptIn(accountID: account.user.id, server: configuration.baseURL)
            try save(preference)
            user = account.user
            Task {
                guard self.optIn?.id == preference.id else { return }
                await self.start()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save(_ preference: DiscoveryOptIn) throws {
        preferences.set(try JSONEncoder().encode(preference), forKey: Self.preferenceKey)
        optIn = preference
    }

    func restore(for account: Account) async {
        guard allowsBackground, let optIn else { return }
        guard
            let configuration = try? APIConfiguration(
                address: preferences.string(forKey: "apiAddress") ?? "",
                allowInsecureHTTP: Self.allowsInsecureHTTP),
            optIn.matches(accountID: account.user.id, server: configuration.baseURL)
        else {
            stop(reason: "Account or API changed")
            return
        }
        user = account.user
        if !isRunning { await start() }
    }

    var walkRemaining: TimeInterval {
        walkPermit?.remaining(uptime: ProcessInfo.processInfo.systemUptime) ?? 0
    }

    private static var allowsInsecureHTTP: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }

    private func configuredClient() throws -> APIClient {
        let address = preferences.string(forKey: "apiAddress") ?? ""
        let configuration = try APIConfiguration(address: address, allowInsecureHTTP: Self.allowsInsecureHTTP)
        apiAddress = configuration.baseURL.absoluteString
        if let clientFactory { return clientFactory(configuration) }
        return APIClient(
            configuration: configuration, tokens: KeychainTokenStore(server: configuration.baseURL))
    }

    func refresh() async {
        if isRunning, allowsBackground {
            if !radio.isRequested { nextRotation = .distantPast }
            await step(operation: generation)
            return
        }
        guard !isRunning, !isStarting, !isRefreshing else { return }
        guard canAccessCredentials() else {
            errorMessage = "Unlock the phone to access the saved account."
            return
        }
        isRefreshing = true
        let operation = generation
        user = nil
        defer { isRefreshing = false }
        do {
            let api = try await configuredClient().capturingCurrentCredential()
            let signedIn = try await api.currentAccount().user
            guard generation == operation else { return }
            let contextMatches = try await api.usesSameCredential(as: configuredClient())
            guard generation == operation, canAccessCredentials(), contextMatches
            else { return }
            client = api
            user = signedIn
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
                : "Could not load the account. Check the error below, then retry."
            errorMessage = error.localizedDescription
        }
    }

    func start() async {
        guard !isStarting, !isRunning, !isRefreshing, !revocationPending,
            supportsBluetooth
        else { return }
        guard canAccessCredentials() else {
            errorMessage = "Open the app and unlock the phone before starting."
            return
        }
        isStarting = true
        retryStart?.cancel()
        retryStart = nil
        isApplicationActive = true
        let operation = UUID()
        generation = operation
        errorMessage = nil
        status = "Starting an authenticated discovery session"
        defer {
            isStarting = false
            if generation == operation { scheduleStartRetry() }
        }
        do {
            let api = try await configuredClient().capturingCurrentCredential()
            let signedIn = try await api.currentAccount().user
            guard generation == operation else { return }
            if allowsBackground {
                let server = try APIConfiguration(
                    address: apiAddress, allowInsecureHTTP: Self.allowsInsecureHTTP
                ).baseURL
                if let optIn, !optIn.matches(accountID: signedIn.id, server: server) {
                    stop(reason: "Account or API changed")
                    return
                }
                if optIn == nil {
                    let preference = DiscoveryOptIn(accountID: signedIn.id, server: server)
                    try save(preference)
                }
                walkConsent = optIn.map { DiscoveryConsent(untilStopped: $0.id) }
            }
            let requestStartedAt = Date()
            let requestStartedUptime = ProcessInfo.processInfo.systemUptime
            let issued = try await api.startDiscovery()
            guard generation == operation, canAccessCredentials()
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
                return
            }
            user = signedIn
            outbox = DiscoveryOutbox()
            pendingUploads = 0
            submittedReports = 0
            discardedReports = 0
            backgroundPasses = 0
            deferredPasses = 0
            backgroundPolicy = BackgroundUploadPolicy()
            matches = WalkMatchTracker()
            matchCount = 0
            unshared = WalkMatchTracker(counting: .noSharedInterests)
            noSharedInterestCount = 0
            firstMatchElapsed = nil
            startedUptime = requestStartedUptime
            isRunning = true
            let token = try applyLease(
                issued, operation: operation, requestStartedAt: requestStartedAt,
                requestStartedUptime: requestStartedUptime)
            radio.setApplicationActive(true)
            radio.start(token: token, authenticatedPermit: walkPermit)
            guard radio.isRequested else { throw APIError.invalidResponse }
            status =
                allowsBackground ? "Discovery enabled until you turn it off" : "Discovery session active"
            startForegroundLoop(operation: operation)
        } catch {
            guard generation == operation else { return }
            if error as? APIError == .unauthenticated || error as? APIError == .onboardingRequired {
                stop(reason: "Sign in and finish your profile to use discovery")
            } else if optIn != nil {
                pause(reason: "Paused — could not start discovery")
                nextRotation = Date().addingTimeInterval(15)
                if isRunning { startForegroundLoop(operation: operation) }
            } else if lease != nil {
                stop(reason: "Discovery could not start")
            } else {
                status = "Discovery could not start"
            }
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleStartRetry() {
        guard automaticallyRefreshes, isEnabled, isApplicationActive, !isRunning else { return }
        retryStart?.cancel()
        retryStart = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, self.isEnabled, self.isApplicationActive else { return }
            self.retryStart = nil
            await self.start()
        }
    }

    private func pause(reason: String) {
        pausingRadio = true
        radio.stop(reason: reason)
        pausingRadio = false
        walkPermit = nil
        tokenExpiresAt = nil
        nextRotation = .distantPast
        status = reason
    }

    private func startForegroundLoop(operation: UUID) {
        loop?.cancel()
        guard automaticallyRefreshes, isRunning, isApplicationActive else { return }
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
            !allowsBackground && issued.expiresAt == issued.sessionExpiresAt
            ? .distantFuture : Date().addingTimeInterval(120)
        expiryWatchdog?.cancel()
        expiryWatchdog = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) } catch {
                return
            }
            guard let self, self.isRunning, self.generation == operation,
                self.lease?.token == issued.token
            else { return }
            if self.allowsBackground {
                self.pause(reason: "Paused — discovery token expired")
            } else {
                self.stop(reason: "Discovery token reached its safe expiry deadline")
            }
        }
        return token
    }

    func sceneChanged(active: Bool) {
        guard allowsBackground else { return }
        isApplicationActive = active
        radio.setApplicationActive(active)
        if !active {
            retryStart?.cancel()
            retryStart = nil
            if isStarting {
                // An issued lease is revoked by start() before another attempt.
                return
            }
            loop?.cancel()
            loop = nil
            if isRunning { requestBackgroundPass() }
        } else if isRunning {
            cancelBackgroundPass()
            startForegroundLoop(operation: generation)
        } else if isEnabled, user != nil {
            Task {
                guard self.isEnabled else { return }
                await self.start()
            }
        }
    }

    func viewClosed() {
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
        guard allowsBackground, isRunning, !isApplicationActive,
            outbox.nextReady() != nil || Date() >= nextRotation
        else { return }
        wantsBackgroundPass = true
        launchBackgroundPassIfIdle()
    }

    private func launchBackgroundPassIfIdle() {
        guard wantsBackgroundPass, !networkBusy, backgroundUpload == nil,
            allowsBackground, isRunning, !isApplicationActive, isEnabled
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
        guard background ? (!isApplicationActive && isEnabled) : isApplicationActive else {
            return
        }
        networkBusy = true
        defer {
            networkBusy = false
            launchBackgroundPassIfIdle()
        }
        if !background {
            guard canAccessCredentials() else { return }
            do {
                let contextMatches = try await api.usesSameCredential(as: configuredClient())
                guard isRunning, generation == operation, isApplicationActive, canAccessCredentials(),
                    !Task.isCancelled
                else { return }
                guard contextMatches else {
                    stop(reason: "Account or API changed; start a fresh discovery session")
                    user = nil
                    return
                }
            } catch {
                errorMessage = "Unlock and refresh to confirm the current account."
                return
            }
        }
        if Date() >= nextRotation || (outbox.isFull && outbox.pending.isEmpty) {
            nextRotation = Date().addingTimeInterval(5)
            do {
                let startedAt = Date()
                let uptime = ProcessInfo.processInfo.systemUptime
                let replacing =
                    allowsBackground
                    && ((walkPermit?.validity.sessionRemaining(uptime: uptime) ?? 0) <= 120
                        || (outbox.isFull && outbox.pending.isEmpty))
                let rotated: DiscoveryLease
                if replacing {
                    rotated = try await api.startDiscovery()
                } else {
                    rotated = try await api.rotateDiscovery(sessionId: current.sessionId)
                }
                guard isRunning, generation == operation, !Task.isCancelled else {
                    if replacing { scheduleRevocation(rotated.sessionId, using: api) }
                    return
                }
                let token = try applyLease(
                    rotated, operation: operation, requestStartedAt: startedAt,
                    requestStartedUptime: uptime)
                if replacing {
                    outbox = DiscoveryOutbox()
                    pendingUploads = 0
                    matches = WalkMatchTracker()
                    pausingRadio = true
                    radio.stop(reason: "Renewing discovery session")
                    pausingRadio = false
                }
                if radio.isRequested {
                    radio.rotateToken(to: token, authenticatedPermit: walkPermit)
                } else {
                    radio.setApplicationActive(isApplicationActive)
                    radio.start(token: token, authenticatedPermit: walkPermit)
                }
                guard isRunning, generation == operation else { return }
                guard radio.isRequested else {
                    pause(reason: "Paused — Bluetooth could not start")
                    nextRotation = Date().addingTimeInterval(15)
                    return
                }
                status = "Discovery enabled until you turn it off"
                errorMessage = nil
            } catch is CancellationError { return } catch {
                guard isRunning, generation == operation else { return }
                if error as? APIError == .unauthenticated || error as? APIError == .onboardingRequired {
                    stop(reason: "The authenticated discovery session ended")
                    return
                }
                if error as? APIError == .server(410), allowsBackground {
                    pause(reason: "Paused — renewing the expired session")
                } else if error as? APIError == .server(410) {
                    stop(reason: "The discovery session ended")
                    return
                }
                if error as? APIError == .rateLimited {
                    nextRotation = Date().addingTimeInterval(60)
                }
                errorMessage = "Token refresh failed. Radio access ends at the current safe deadline."
            }
        }
        guard let activeLease = lease else { return }
        for _ in 0..<(background ? BackgroundUploadPolicy.maximumReports : 1) {
            guard isRunning, generation == operation, !Task.isCancelled,
                !background || (!isApplicationActive && walkRemaining > 0),
                let pending = outbox.nextReady()
            else { break }
            do {
                let receipt = try await api.observeEncounter(
                    sessionId: activeLease.sessionId, peerToken: pending.peerToken, observationId: pending.id)
                guard isRunning, generation == operation, !Task.isCancelled else { return }
                if pending.awaitingMatchUntil == nil { submittedReports += 1 }
                switch receipt.status {
                case .recorded:
                    outbox.acknowledge(pending.id)
                    recordMatch(receipt)
                case .noSharedInterests:
                    outbox.acknowledge(pending.id)
                    if unshared.ingest(receipt) { noSharedInterestCount += 1 }
                case .pending:
                    outbox.awaitMatch(pending.id)
                }
                errorMessage = nil
            } catch is CancellationError { return } catch {
                guard isRunning, generation == operation, !Task.isCancelled else { return }
                if error as? APIError == .unauthenticated {
                    stop(reason: "Sign in again to continue discovery")
                    user = nil
                    return
                }
                if error as? APIError == .onboardingRequired {
                    stop(reason: "Finish your profile to use discovery")
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
                    let kept = outbox.failed(pending.id, rateLimited: error as? APIError == .rateLimited)
                    if !kept { discardedReports += 1 }
                    errorMessage =
                        kept
                        ? "Upload deferred; its observation ID is preserved."
                        : "A report was discarded after five failed uploads."
                }
            }
            pendingUploads = outbox.pending.count
        }
    }

    private func recordMatch(_ receipt: ObservationReceipt) {
        guard matches.ingest(receipt) else { return }
        matchCount += 1
        if firstMatchElapsed == nil {
            firstMatchElapsed = max(0, ProcessInfo.processInfo.systemUptime - startedUptime)
        }
    }

    var report: String {
        [
            "Authenticated discovery: hardware validation pending.",
            "Matches are client reports. They do not verify physical proximity.",
            "Background passes: \(backgroundPasses); deferred: \(deferredPasses)",
            "Submitted: \(submittedReports); queued: \(pendingUploads); discarded: \(discardedReports)",
            "Remaining permit: \(Int(ceil(walkRemaining))) seconds",
            "Matches this run: \(matchCount)",
            "Passed without shared interests: \(noSharedInterestCount)",
            "First match: \(firstMatchElapsed.map { String(format: "%.1f seconds after Start", $0) } ?? "none")",
            "Status: \(status)",
            "",
            radio.report,
        ].joined(separator: "\n")
    }

    func stop(reason: String = "Discovery stopped") {
        optIn = nil
        if allowsBackground { preferences.removeObject(forKey: Self.preferenceKey) }
        retryStart?.cancel()
        retryStart = nil
        generation = UUID()
        loop?.cancel()
        expiryWatchdog?.cancel()
        loop = nil
        expiryWatchdog = nil
        isRunning = false
        cancelBackgroundPass()
        radio.stop(reason: reason)
        outbox = DiscoveryOutbox()
        pendingUploads = 0
        tokenExpiresAt = nil
        walkPermit = nil
        walkConsent = nil
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
                if let self, self.revocation?.sessionId != pending.sessionId, self.revocationPending {
                    self.retryRevocation()
                } else {
                    self?.scheduleStartRetry()
                }
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
