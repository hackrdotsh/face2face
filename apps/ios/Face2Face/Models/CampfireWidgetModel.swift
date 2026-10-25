import Face2FaceCore
import Foundation
import Observation
import WidgetKit

/// Publishes only opt-in, short-lived presentation data. The extension never authenticates.
@MainActor
@Observable
final class CampfireWidgetModel {
    static let shared = CampfireWidgetModel()
    private(set) var isRefreshing = false
    private(set) var message = "Gather your friends around a little fire."
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var context = ""
    @ObservationIgnored private var lastCheck = Date.distantPast

    static func guests(from connections: [TownConnection]) -> [CampfireGuest] {
        var seen = Set<String>()
        return connections.filter(\.isFriend).sorted { $0.id < $1.id }.filter { seen.insert($0.id).inserted }
            .enumerated().map { index, connection in
                let friend = connection.publicTownFriend
                return CampfireGuest(
                    id: index,
                    name: friend.map {
                        String($0.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
                    } ?? "Anonymous friend",
                    seed: friend?.avatar.seed
                        ?? BlobSurface.dailySeed(at: Date(timeIntervalSince1970: Double(index + 1) * 86_400)),
                    isAnonymous: friend == nil)
            }
    }

    func clear(_ status: CampfireSnapshot.Status) {
        generation = UUID()
        context = ""
        lastCheck = .distantPast
        isRefreshing = false
        CampfireStore.clear(status)
        WidgetCenter.shared.reloadTimelines(ofKind: "DailyBlob")
    }

    func refresh(session: SessionModel, force: Bool = false) async {
        guard UserDefaults.standard.bool(forKey: CampfireStore.preferenceKey) else {
            clear(.disabled)
            return
        }
        guard case .ready(let account) = session.phase, !session.isTownPreview else {
            clear(.signedOut)
            return
        }
        let address = session.serverAddress
        let key = "\(account.user.id)|\(address)"
        if context != key {
            clear(.unavailable)
            context = key
        }
        guard !isRefreshing, force || Date().timeIntervalSince(lastCheck) >= 30 else { return }
        let operation = generation
        isRefreshing = true
        defer { if generation == operation { isRefreshing = false } }
        do {
            let connections = try await session.client().townConnections()
            guard !Task.isCancelled, generation == operation,
                session.serverAddress == address, case .ready(let current) = session.phase,
                current.user.id == account.user.id,
                UserDefaults.standard.bool(forKey: CampfireStore.preferenceKey)
            else { return }
            let guests = Self.guests(from: connections)
            guard
                FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: CampfireStore.group)
                    != nil,
                CampfireStore.write(.init(status: .ready, ownSeed: account.user.avatar.seed, guests: guests))
            else {
                CampfireStore.clear(.unavailable)
                message =
                    "The shared widget container is unavailable. Check App Group signing for both targets."
                return
            }
            lastCheck = Date()
            message =
                guests.isEmpty
                ? "Your fire is ready. Friends will appear after you connect."
                : "\(guests.count) friends gathered. Private connections stay anonymous."
            WidgetCenter.shared.reloadTimelines(ofKind: "DailyBlob")
        } catch {
            guard generation == operation, !Task.isCancelled else { return }
            CampfireStore.clear(.unavailable)
            WidgetCenter.shared.reloadTimelines(ofKind: "DailyBlob")
            message = "Couldn't refresh your friends. The widget hides old friend data until you retry."
        }
    }
}
