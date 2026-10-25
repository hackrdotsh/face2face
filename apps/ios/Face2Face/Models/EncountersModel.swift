import Face2FaceCore
import Foundation
import Observation

@MainActor
@Observable
final class EncountersModel {
    let isPreview: Bool
    private let session: SessionModel?
    private let feedbackContext: UUID?
    private var fixedSource: (any EncounterRepository)?
    private var client: APIClient?
    private(set) var chances: [TownConnection] = []
    private(set) var loading = true
    private(set) var busyID: String?
    private(set) var error: String?
    private(set) var notice: String?
    private(set) var newlyConnectedID: String?
    private var acceptedIDs = Set<String>()
    private var announcedIDs = Set<String>()
    private var version = 0

    init(session: SessionModel) {
        self.session = session
        feedbackContext = session.celebrations.context
        isPreview = session.isTownPreview
        #if DEBUG
            if isPreview { fixedSource = PreviewEncounterRepository() }
        #endif
    }
    init(repository: any EncounterRepository) {
        session = nil
        feedbackContext = nil
        isPreview = false
        fixedSource = repository
    }
    private func repository() async throws -> any EncounterRepository {
        if let fixedSource {
            guard !isPreview || session?.isTownPreview == true else { throw APIError.unauthenticated }
            return fixedSource
        }
        guard let session else { throw APIError.unauthenticated }
        let current = try session.client()
        if let client {
            guard try await current.usesSameCredential(as: client) else { throw APIError.unauthenticated }
            return client
        }
        let snapshot = try await current.capturingCurrentCredential()
        client = snapshot
        return snapshot
    }

    func refresh() async {
        guard busyID == nil else { return }
        let feedbackRevision = session?.celebrations.revision ?? 0
        version += 1
        let request = version
        loading = true
        error = nil
        defer { if request == version { loading = false } }
        do {
            let source = try await repository()
            let all = try await source.townConnections()
            guard request == version, !Task.isCancelled else { return }
            session?.celebrations.observeSnapshot(all, context: feedbackContext, revision: feedbackRevision)
            acceptedIDs.formUnion(all.filter { $0.isPending && $0.you?.decision == .accepted }.map(\.id))
            if let current = newlyConnectedID, !all.contains(where: { $0.id == current && $0.isFriend }) {
                newlyConnectedID = nil
            }
            if newlyConnectedID == nil,
                let match = all.first(where: {
                    $0.isFriend && acceptedIDs.contains($0.id) && !announcedIDs.contains($0.id)
                })
            {
                newlyConnectedID = match.id
                registerPreviewChat(match)
            }
            var seen = Set<String>()
            chances = all.filter { $0.isPending && seen.insert($0.id).inserted }
        } catch {
            guard request == version, !Task.isCancelled else { return }
            chances = []
            newlyConnectedID = nil
            self.error =
                error is APIError
                ? error.localizedDescription
                : "Couldn't load your chances. Check your connection and try again."
        }
    }

    func decide(_ id: String, decision: ConnectionDecision) async {
        guard busyID == nil else { return }
        guard let row = chances.first(where: { $0.id == id }) else {
            error = APIError.chanceEnded.localizedDescription
            return
        }
        guard row.you?.decision == nil else {
            error = APIError.chanceAlreadyAnswered.localizedDescription
            return
        }
        version += 1
        let request = version
        busyID = id
        error = nil
        notice = nil
        if decision == .accepted { acceptedIDs.insert(id) }
        var failure: String?
        do {
            let source = try await repository()
            let result = try await source.decideConnection(id, decision: decision)
            guard request == version, !Task.isCancelled else { return }
            chances.removeAll { $0.id == id }
            if result.isPending { chances.append(result) }
            if result.isFriend {
                session?.celebrations.observe(result, context: feedbackContext, allowNew: true)
                newlyConnectedID = result.id
                registerPreviewChat(result)
            } else if decision == .declined {
                notice = "Chance dismissed. Take your time with the next hello."
            }
        } catch {
            guard request == version, !Task.isCancelled else { return }
            failure = Self.decisionMessage(error)
        }
        guard request == version else { return }
        busyID = nil
        await refresh()
        let acceptanceConfirmed =
            decision == .accepted
            && (newlyConnectedID == id || chances.contains { $0.id == id && $0.you?.decision == .accepted })
        if let failure, !acceptanceConfirmed { error = failure }
    }

    func block(_ id: String) async {
        guard busyID == nil, chances.contains(where: { $0.id == id }) else { return }
        version += 1
        let request = version
        busyID = id
        error = nil
        do {
            let source = try await repository()
            try await source.blockConnection(id)
            guard request == version, !Task.isCancelled else { return }
            chances.removeAll { $0.id == id }
            notice = "Connection blocked. Future chances with this person will be ignored."
        } catch {
            guard request == version, !Task.isCancelled else { return }
            self.error = "Couldn't confirm the block. Refresh and try again."
        }
        guard request == version else { return }
        busyID = nil
    }

    func openedChat(_ id: String) {
        announcedIDs.insert(id)
        if newlyConnectedID == id { newlyConnectedID = nil }
    }
    func clearVisibleData() {
        version += 1
        chances = []
        newlyConnectedID = nil
        busyID = nil
        loading = false
        error = nil
    }
    private func registerPreviewChat(_ connection: TownConnection) {
        #if DEBUG
            if isPreview { try? ChatPreview.registerConnection(connection) }
        #endif
    }
    private static func decisionMessage(_ error: any Error) -> String {
        if let api = error as? APIError {
            if api == .server(404) { return APIError.chanceEnded.localizedDescription }
            return api.localizedDescription
        }
        return
            "Couldn't confirm your answer. We refreshed your chances; check the latest status before trying again."
    }
}

#if DEBUG
    actor PreviewEncounterRepository: EncounterRepository {
        private var rows: [[String: Any]] = []
        private let state: String?
        private var reads = 0
        private(set) var answerCount = 0
        init(state: String? = nil) {
            let args = ProcessInfo.processInfo.arguments
            let index = args.firstIndex(of: "-encounters-preview-state")
            self.state = state ?? index.flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        }
        private func previewSeed(_ id: String) -> String {
            switch id {
            case "preview-chance": "AQIDBAUGBwgJCgsMDQ4PEA"
            case "preview-decline": "EBEREhMUFRYXGBkaGxwdHg"
            default: "ICEiIyQlJicoKSorLC0uLw"
            }
        }
        private func seed() {
            guard rows.isEmpty else { return }
            let formatter = ISO8601DateFormatter()
            for (id, interests, answer, hours) in [
                ("preview-chance", ["music", "coffee"], "", 22.0),
                ("preview-decline", ["hiking", "books"], "", 10.0),
                ("preview-waiting", ["art"], "accepted", 4.0),
            ] {
                rows.append([
                    "id": id, "status": state == "expired" ? "expired" : "pending",
                    "sharedInterests": interests,
                    "createdAt": formatter.string(from: Date().addingTimeInterval(-3600)),
                    "expiresAt": formatter.string(from: Date().addingTimeInterval(hours * 3600)),
                    "you": [
                        "decision": answer.isEmpty ? NSNull() : answer as Any,
                        "decidedAt": answer.isEmpty ? NSNull() : formatter.string(from: Date()) as Any,
                        "publicAt": NSNull(),
                    ],
                    "theirAvatar": ["seed": previewSeed(id)],
                    // Adversarial identity-shaped data: the pending UI must never render it.
                    "them": [
                        "userId": "hidden-peer", "name": "Must stay hidden", "age": 27,
                        "avatar": ["seed": "AAAAAAAAAAAAAAAAAAAAAA"], "interests": ["coffee"],
                    ],
                ])
            }
        }
        private func decode(_ row: [String: Any]) throws -> TownConnection {
            try JSONDecoder().decode(TownConnection.self, from: JSONSerialization.data(withJSONObject: row))
        }
        func townConnections() throws -> [TownConnection] {
            if state == "error" { throw APIError.server(503) }
            if state == "empty" { return [] }
            seed()
            reads += 1
            if state == "peer-accepts" && reads > 1,
                let index = rows.firstIndex(where: { $0["id"] as? String == "preview-waiting" })
            {
                rows[index]["status"] = "private"
                rows[index]["them"] = NSNull()
            }
            return try rows.filter { $0["status"] as? String != "expired" }.map(decode)
        }
        func decideConnection(_ id: String, decision: ConnectionDecision) throws -> TownConnection {
            seed()
            guard let index = rows.firstIndex(where: { $0["id"] as? String == id }),
                rows[index]["status"] as? String == "pending"
            else { throw APIError.chanceEnded }
            if state == "stale" {
                rows[index]["status"] = "expired"
                throw APIError.chanceEnded
            }
            var you = rows[index]["you"] as! [String: Any]
            guard you["decision"] is NSNull else { throw APIError.chanceAlreadyAnswered }
            answerCount += 1
            you["decision"] = decision.rawValue
            you["decidedAt"] = ISO8601DateFormatter().string(from: Date())
            rows[index]["you"] = you
            rows[index]["status"] =
                decision == .declined ? "expired" : id == "preview-chance" ? "private" : "pending"
            rows[index]["them"] = NSNull()
            if state == "lost-response" { throw URLError(.networkConnectionLost) }
            return try decode(rows[index])
        }
        func blockConnection(_ id: String) throws {
            seed()
            guard let index = rows.firstIndex(where: { $0["id"] as? String == id }) else {
                throw APIError.server(404)
            }
            rows[index]["status"] = "blocked"
            rows[index]["them"] = NSNull()
        }
    }
#endif
