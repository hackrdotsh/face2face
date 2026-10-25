import ActivityKit
import Foundation
import Observation

struct BlobCompanionSession: Equatable, Sendable {
    let id: String
    let seed: String
    let endsAt: Date
}

@MainActor
protocol BlobCompanionClient {
    var isAvailable: Bool { get }
    var sessions: [BlobCompanionSession] { get }
    func start(seed: String, endsAt: Date) throws -> BlobCompanionSession
    func end(_ session: BlobCompanionSession) async
    func update(_ session: BlobCompanionSession, signal: BlobSignal, pulse: Int) async
    func updates(for session: BlobCompanionSession) -> AsyncStream<Bool>
}

@MainActor
struct SystemBlobCompanionClient: BlobCompanionClient {
    var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    static func isOngoing(_ state: ActivityState) -> Bool {
        state != .ended && state != .dismissed
    }

    var sessions: [BlobCompanionSession] {
        ActivityKit.Activity<BlobCompanionAttributes>.activities.filter {
            $0.activityState != .ended && $0.activityState != .dismissed
        }.map {
            BlobCompanionSession(id: $0.id, seed: $0.attributes.seed, endsAt: $0.content.state.endsAt)
        }
    }

    func start(seed: String, endsAt: Date) throws -> BlobCompanionSession {
        let activity = try ActivityKit.Activity.request(
            attributes: BlobCompanionAttributes(seed: seed),
            content: ActivityContent(state: .init(endsAt: endsAt), staleDate: endsAt), pushType: nil)
        return BlobCompanionSession(id: activity.id, seed: seed, endsAt: endsAt)
    }

    nonisolated func end(_ session: BlobCompanionSession) async {
        guard
            let activity = ActivityKit.Activity<BlobCompanionAttributes>.activities.first(where: {
                $0.id == session.id
            })
        else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    nonisolated func update(_ session: BlobCompanionSession, signal: BlobSignal, pulse: Int) async {
        guard
            let activity = ActivityKit.Activity<BlobCompanionAttributes>.activities.first(where: {
                $0.id == session.id
            })
        else { return }
        let state = BlobCompanionAttributes.ContentState(
            endsAt: session.endsAt, signal: signal, pulse: max(pulse, activity.content.state.pulse + 1))
        await activity.update(
            ActivityContent(state: state, staleDate: min(session.endsAt, signal.staleDate ?? session.endsAt)))
    }

    func updates(for session: BlobCompanionSession) -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let task = Task {
                guard
                    let activity = ActivityKit.Activity<BlobCompanionAttributes>.activities.first(where: {
                        $0.id == session.id
                    })
                else {
                    continuation.yield(false)
                    continuation.finish()
                    return
                }
                for await state in activity.activityStateUpdates {
                    // iOS 26 can report .pending before presentation. It is not a dismissal.
                    let ongoing = Self.isOngoing(state)
                    continuation.yield(ongoing)
                    if !ongoing { break }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// A companion is an explicitly started, bounded decoration, never a discovery session.
@MainActor
@Observable
final class BlobCompanionModel {
    static let shared = BlobCompanionModel(client: SystemBlobCompanionClient())
    private(set) var session: BlobCompanionSession?
    private(set) var errorMessage: String?
    private(set) var isAvailable = false
    @ObservationIgnored private let client: any BlobCompanionClient
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var monitor: Task<Void, Never>?
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private var endingIDs: Set<String> = []
    @ObservationIgnored private var signalUpdate: Task<Void, Never>?
    @ObservationIgnored private var latestSignal = BlobSignal.off
    @ObservationIgnored private var lastSignalUpdate = Date.distantPast
    @ObservationIgnored private var pulse = 0

    init(client: any BlobCompanionClient, now: @escaping () -> Date = Date.init) {
        self.client = client
        self.now = now
        isAvailable = client.isAvailable
    }

    deinit {
        monitor?.cancel()
        expiry?.cancel()
        signalUpdate?.cancel()
    }

    var isEnabled: Bool { session != nil }

    /// Coalesced event updates, not a timer that keeps the app or Island awake.
    func updateSignal(_ signal: BlobSignal, force: Bool = false) {
        guard force || signal != latestSignal else { return }
        latestSignal = signal
        signalUpdate?.cancel()
        guard let current = session else { return }
        let delay =
            signal.mode == .receiving && !force ? max(0, 10 - now().timeIntervalSince(lastSignalUpdate)) : 0
        signalUpdate = Task { [weak self] in
            if delay > 0 {
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
            guard let self, !Task.isCancelled, self.session?.id == current.id else { return }
            self.pulse += 1
            self.lastSignalUpdate = self.now()
            await self.client.update(current, signal: self.latestSignal, pulse: self.pulse)
        }
    }

    /// Reconcile only after authentication resolves. Never automatically restart a dismissed activity.
    func refresh(seed: String?) {
        isAvailable = client.isAvailable
        endingIDs.formIntersection(Set(client.sessions.map(\.id)))
        let valid = client.sessions.first {
            !endingIDs.contains($0.id) && isAvailable && $0.seed == seed && $0.endsAt > now()
        }
        let obsolete = client.sessions.filter { $0.id != valid?.id }
        end(obsolete)
        if session != valid { observe(valid) }
    }

    func start(seed: String) {
        errorMessage = nil
        refresh(seed: seed)
        guard session == nil else { return }
        guard isAvailable else {
            errorMessage = "Live Activities are disabled. Allow them for face2face in iPhone Settings."
            return
        }
        do {
            observe(
                try client.start(seed: seed, endsAt: now().addingTimeInterval(BlobSurface.sessionDuration)))
        } catch {
            errorMessage = "Could not start your blob companion. \(error.localizedDescription)"
        }
    }

    func stop() {
        let previous = client.sessions
        observe(nil)
        errorMessage = nil
        end(previous)
    }

    private func end(_ sessions: [BlobCompanionSession]) {
        let sessions = sessions.filter { !endingIDs.contains($0.id) }
        endingIDs.formUnion(sessions.map(\.id))
        let client = client
        Task { for session in sessions { await client.end(session) } }
    }

    private func observe(_ current: BlobCompanionSession?) {
        signalUpdate?.cancel()
        monitor?.cancel()
        expiry?.cancel()
        session = current
        guard let current else { return }
        let updates = client.updates(for: current)
        monitor = Task { [weak self] in
            for await active in updates {
                guard !Task.isCancelled, let self, self.session?.id == current.id else { return }
                if !active {
                    self.stop()
                    return
                }
            }
        }
        let remaining = max(0, current.endsAt.timeIntervalSince(now()))
        expiry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
            guard let self, self.session?.id == current.id else { return }
            self.stop()
        }
    }
}
