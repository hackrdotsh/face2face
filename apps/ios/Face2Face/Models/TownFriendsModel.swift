import Face2FaceCore
import Foundation
import Observation

@MainActor
@Observable
final class TownFriendsModel {
    private let load: @MainActor () async throws -> [PublicTownFriend]
    let isPreview: Bool
    private(set) var visitors: [PublicTownFriend] = []
    private(set) var selectedID: String?
    private(set) var profileChecked = false
    private(set) var error: String?
    private var friends: [PublicTownFriend] = []
    private var generation = 0

    var selectedProfile: PublicTownFriend? {
        guard profileChecked else { return nil }
        return friends.first { $0.id == selectedID }
    }

    init(session: SessionModel) {
        isPreview = session.isTownPreview
        var previewRequests = 0
        load = {
            #if DEBUG
                if session.isTownPreview {
                    previewRequests += 1
                    return try TownFriendsPreview.load(request: previewRequests)
                }
            #endif
            return try await session.client().townPublicFriends()
        }
    }

    /// Injectable source for native tests; production always uses the authenticated API.
    init(load: @escaping @MainActor () async throws -> [PublicTownFriend]) {
        self.load = load
        isPreview = false
    }

    func refresh(preferredConnectionID: String? = nil) async {
        generation += 1
        let request = generation
        do {
            let result = try await load()
            guard !Task.isCancelled, request == generation else { return }
            var seen = Set<String>()
            friends = result.filter { seen.insert($0.userId).inserted }
            // Keep existing slots stable across refreshes; fill vacancies with a few visitors.
            let previous = visitors.compactMap { visitor in friends.first { $0.id == visitor.id } }
            let remaining = friends.filter { friend in !previous.contains { $0.id == friend.id } }
            #if DEBUG
                let candidates = isPreview ? remaining : remaining.shuffled()
            #else
                let candidates = remaining.shuffled()
            #endif
            let preferred = friends.first { $0.id == preferredConnectionID }
            let ordered = previous + candidates
            visitors = Array(
                ((preferred.map { [$0] } ?? []) + ordered.filter { $0.id != preferred?.id }).prefix(3))
            profileChecked = selectedID != nil
            error = nil
        } catch {
            guard !Task.isCancelled, request == generation else { return }
            // Fail closed: no stale faces or profiles after a failed authorization refresh.
            friends = []
            visitors = []
            profileChecked = false
            self.error = "We couldn't check your public connections. Please try again."
        }
    }

    func select(_ friend: PublicTownFriend) {
        guard visitors.contains(where: { $0.id == friend.id }) else { return }
        openPublicConnection(friend.id)
    }

    /// The compact sheet still fetches the public-only list before rendering any identity.
    /// A public chat need not already occupy one of the three visitor slots.
    func openPublicConnection(_ id: String) {
        generation += 1
        selectedID = id
        profileChecked = false
        error = nil
    }

    func closeProfile() {
        selectedID = nil
        profileChecked = false
    }

    func clearVisibleData() {
        generation += 1
        visitors = []
        friends = []
        profileChecked = false
        error = nil
    }
}

#if DEBUG
    @MainActor private enum TownFriendsPreview {
        static func load(request: Int) throws -> [PublicTownFriend] {
            let arguments = ProcessInfo.processInfo.arguments
            let index = arguments.firstIndex(of: "-town-friends-preview-state")
            let state = index.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
            if state == "error" { throw APIError.server(503) }
            if state == "empty" { return [] }
            let status = state == "revoked" && request > 1 ? "private" : "public"
            let people: [(String, String, Int, [String], String?)] = [
                ("ava", "Ava", 26, ["music", "coffee", "hiking"], "Looking for a hiking buddy this weekend"),
                ("cleo", "Cleo", 24, ["art", "coffee"], nil),
                ("noor", "Noor", 28, ["music", "books"], "Ask me about the book I just finished"),
            ]
            var rows: [[String: Any]] = people.map { id, name, age, interests, statusMessage in
                [
                    "id": "preview-\(id)", "status": status, "sharedInterests": ["coffee"],
                    "expiresAt": "2026-10-26T00:00:00Z",
                    "them": [
                        "userId": id, "name": name, "age": age, "interests": interests,
                        "avatar": ["seed": id == "ava" ? "AAAAAAAAAAAAAAAAAAAAAA" : "AQIDBAUGBwgJCgsMDQ4PEA"],
                        "statusMessage": statusMessage.map { $0 as Any } ?? NSNull(),
                    ],
                ]
            }
            // Deliberately include non-public identity-shaped data: it must never become an NPC.
            for status in ["private", "pending", "blocked", "expired"] {
                rows.append([
                    "id": "hidden-\(status)", "status": status, "sharedInterests": [],
                    "expiresAt": "2026-10-26T00:00:00Z",
                    "them": [
                        "userId": "hidden", "name": "Hidden \(status)",
                        "avatar": ["seed": "AAAAAAAAAAAAAAAAAAAAAA"],
                    ],
                ])
            }
            let connections = try JSONDecoder().decode(
                [TownConnection].self,
                from: JSONSerialization.data(withJSONObject: rows))
            let base = connections.compactMap(\.publicTownFriend)
            return state == "revoked" ? base : base + (try ChatPreview.sharedPublicFriends())
        }
    }
#endif
