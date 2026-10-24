#if DEBUG
    import Face2FaceCore
    import Foundation
    import Observation

    /// Stage 2 diagnostic integration. No background uploads, persisted locators, or friendship state.
    @MainActor
    @Observable
    final class ConnectedDiscoveryModel {
        let radio = BluetoothDiscoveryService()
        private(set) var user: User?
        private(set) var apiAddress = ""
        private(set) var status = "Sign in on Account, then refresh."
        private(set) var errorMessage: String?
        private(set) var isStarting = false
        private(set) var isRefreshing = false
        private(set) var isRunning = false
        private(set) var revocationPending = false
        private(set) var isRevoking = false
        private(set) var pendingUploads = 0
        private(set) var submittedReports = 0
        private(set) var discardedReports = 0
        private(set) var encounters: [ServerEncounter] = []
        private(set) var tokenExpiresAt: Date?

        @ObservationIgnored private var client: APIClient?
        @ObservationIgnored private var lease: DiscoveryLease?
        @ObservationIgnored private var outbox = DiscoveryOutbox()
        @ObservationIgnored private var generation = UUID()
        @ObservationIgnored private var loop: Task<Void, Never>?
        @ObservationIgnored private var expiryWatchdog: Task<Void, Never>?
        @ObservationIgnored private var nextRotation = Date.distantFuture
        @ObservationIgnored private var nextRefresh = Date.distantPast
        @ObservationIgnored private var revocation: (client: APIClient, sessionId: String)?

        init() {
            radio.onEncounter = { [weak self] encounter in self?.enqueue(encounter) }
            radio.onStopped = { [weak self] in
                guard let self, self.isRunning else { return }
                self.stop(reason: self.radio.status)
            }
        }

        deinit {
            loop?.cancel()
            expiryWatchdog?.cancel()
        }

        private func configuredClient() throws -> APIClient {
            let address = UserDefaults.standard.string(forKey: "apiAddress") ?? "http://localhost:8787"
            let configuration = try APIConfiguration(address: address, allowInsecureHTTP: true)
            apiAddress = configuration.baseURL.absoluteString
            return APIClient(
                configuration: configuration, tokens: KeychainTokenStore(server: configuration.baseURL))
        }

        func refresh() async {
            guard !isRunning, !isStarting, !isRefreshing else { return }
            isRefreshing = true
            let operation = generation
            user = nil
            encounters = []
            defer { isRefreshing = false }
            do {
                let api = try configuredClient()
                let signedIn = try await api.currentUser()
                guard generation == operation else { return }
                let history = try await api.encounters()
                guard generation == operation else { return }
                client = api
                user = signedIn
                encounters = history
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
                    : "Could not load discovery. Check the API connection and apply its migrations."
                errorMessage = error.localizedDescription
            }
        }

        func start() async {
            guard !isStarting, !isRunning, !isRefreshing, !revocationPending,
                !BluetoothDiscoveryService.isSimulator
            else { return }
            isStarting = true
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
                guard generation == operation else {
                    status = "Discovery stopped"
                    return
                }
                let requestStartedAt = Date()
                let issued = try await api.startDiscovery()
                // Canceling while the request was in flight must revoke its late response.
                guard generation == operation else {
                    scheduleRevocation(issued.sessionId, using: api)
                    return
                }
                client = api
                user = signedIn
                lease = issued
                outbox = DiscoveryOutbox()
                pendingUploads = 0
                submittedReports = 0
                discardedReports = 0
                nextRefresh = .distantPast
                isRunning = true
                let token = try applyLease(issued, operation: operation, requestStartedAt: requestStartedAt)
                radio.start(token: token)
                status = "Discovery session active"
                loop = Task { [weak self] in
                    while !Task.isCancelled {
                        guard let self, self.isRunning, self.generation == operation else { return }
                        await self.step(operation: operation)
                        do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    }
                }
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

        private func applyLease(_ issued: DiscoveryLease, operation: UUID, requestStartedAt: Date) throws
            -> DiscoveryToken
        {
            let token = try issued.validatedToken()
            let receivedAt = Date()
            let deadline = min(
                issued.tokenDeadline(requestStartedAt: requestStartedAt),
                issued.sessionDeadline(requestStartedAt: requestStartedAt))
            guard deadline > receivedAt else { throw APIError.invalidResponse }
            lease = issued
            tokenExpiresAt = deadline
            nextRotation =
                issued.expiresAt == issued.sessionExpiresAt
                ? .distantFuture : receivedAt.addingTimeInterval(120)
            expiryWatchdog?.cancel()
            expiryWatchdog = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) } catch {
                    return
                }
                guard let self, self.isRunning, self.generation == operation,
                    self.lease?.token == issued.token
                else { return }
                self.stop(reason: "Discovery token reached its safe expiry deadline")
            }
            return token
        }

        private func enqueue(_ encounter: DiscoveryEncounter) {
            guard isRunning, lease != nil else { return }
            if outbox.enqueue(encounter.id) {
                pendingUploads = outbox.pending.count
            } else {
                errorMessage = "This session has reached its report limit. Stop and start a fresh session."
            }
        }

        private func step(operation: UUID) async {
            guard isRunning, generation == operation, let api = client, let current = lease else { return }
            if Date() >= nextRotation {
                nextRotation = Date().addingTimeInterval(5)
                do {
                    let requestStartedAt = Date()
                    let rotated = try await api.rotateDiscovery(sessionId: current.sessionId)
                    guard isRunning, generation == operation else { return }
                    let token = try applyLease(
                        rotated, operation: operation, requestStartedAt: requestStartedAt)
                    radio.rotateToken(to: token)
                    errorMessage = nil
                } catch {
                    guard isRunning, generation == operation else { return }
                    if error as? APIError == .unauthenticated || error as? APIError == .server(410) {
                        stop(reason: "The authenticated discovery session ended")
                        return
                    }
                    errorMessage =
                        "Token refresh failed. Discovery will stop before the current token expires."
                }
            }

            guard isRunning, generation == operation else { return }
            if let pending = outbox.nextReady() {
                do {
                    _ = try await api.observeEncounter(
                        sessionId: current.sessionId, peerToken: pending.peerToken, observationId: pending.id)
                    guard isRunning, generation == operation else { return }
                    outbox.acknowledge(pending.id)
                    submittedReports += 1
                    errorMessage = nil
                    nextRefresh = .distantPast
                } catch {
                    guard isRunning, generation == operation else { return }
                    if error as? APIError == .unauthenticated {
                        stop(reason: "Sign in again to continue discovery")
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
                            ? "An upload failed. Retrying with the same observation ID."
                            : "A report was discarded after five failed uploads."
                    }
                }
                pendingUploads = outbox.pending.count
            }

            guard isRunning, generation == operation else { return }
            if Date() >= nextRefresh {
                nextRefresh = Date().addingTimeInterval(5)
                do {
                    let history = try await api.encounters()
                    guard isRunning, generation == operation else { return }
                    encounters = history
                } catch {
                    guard isRunning, generation == operation else { return }
                    if error as? APIError == .unauthenticated {
                        stop(reason: "Sign in again to view encounters")
                    } else {
                        errorMessage = "Could not refresh encounters. Retrying while discovery stays active."
                    }
                }
            }
        }

        func stop(reason: String = "Discovery stopped") {
            generation = UUID()
            loop?.cancel()
            expiryWatchdog?.cancel()
            loop = nil
            expiryWatchdog = nil
            isRunning = false
            radio.stop(reason: reason)
            outbox = DiscoveryOutbox()
            pendingUploads = 0
            tokenExpiresAt = nil
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
            Task { [weak self] in
                defer { self?.isRevoking = false }
                do {
                    try await pending.client.stopDiscovery(sessionId: pending.sessionId)
                    guard let self, self.revocation?.sessionId == pending.sessionId else { return }
                    self.revocation = nil
                    self.revocationPending = false
                    self.status = "Discovery stopped; server session revoked"
                    self.errorMessage = nil
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
