import CryptoKit
import Face2FaceCore
import Foundation
import Observation
import UIKit

/// Local, account-scoped feedback receipts. Never an authorization or identity cache.
@MainActor
@Observable
final class ConnectionCelebrations {
    struct Milestone: Identifiable, Equatable {
        enum Kind: Int {
            case privateChat = 1
            case publicProfiles = 2
        }
        let connectionID: String
        let kind: Kind
        var id: String { "\(connectionID)-\(kind.rawValue)" }
    }

    private(set) var context: UUID?
    private(set) var revision = 0
    private(set) var presented: Milestone?
    private var owner: UUID?
    private var pending: [Milestone] = []
    private var stages: [String: Int] = [:]
    private var hasBaseline = false
    private var key: String?
    private var scope: String?
    private let defaults: UserDefaults
    private let haptic: @MainActor () -> Void

    init(
        defaults: UserDefaults = .standard,
        haptic: @escaping @MainActor () -> Void = {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    ) {
        self.defaults = defaults
        self.haptic = haptic
    }

    func bind(accountID: String, server: String, preview: Bool = false) {
        let next = Self.digest("\(server)\n\(accountID)\n\(preview)")
        guard scope != next else { return }
        clear()
        scope = next
        context = UUID()
        key = preview ? nil : "connection-feedback.v1.\(next)"
        if let key {
            stages = defaults.dictionary(forKey: key) as? [String: Int] ?? [:]
            hasBaseline = defaults.bool(forKey: key + ".baseline")
        }
    }

    func clear() {
        context = nil
        scope = nil
        key = nil
        stages = [:]
        hasBaseline = false
        pending = []
        presented = nil
        owner = nil
        revision += 1
    }

    /// A first snapshot quietly establishes existing friendships. Later snapshots detect changes.
    func observeSnapshot(_ rows: [TownConnection], context: UUID?, revision: Int) {
        guard context != nil, context == self.context, revision == self.revision else { return }
        let allowNew = hasBaseline
        for row in rows { observe(row, context: context, allowNew: allowNew) }
        hasBaseline = true
        if let key { defaults.set(true, forKey: key + ".baseline") }
        let valid = Set(rows.filter(\.isFriend).map(\.id))
        for event in pending where !valid.contains(event.connectionID) {
            cancel(event.connectionID, context: context)
        }
        if let presented, !valid.contains(presented.connectionID) {
            cancel(presented.connectionID, context: context)
        }
    }

    /// Unknown chats load silently; a confirmed action may announce a newly created friendship.
    func observe(_ row: TownConnection, context: UUID?, allowNew: Bool = false) {
        guard context != nil, context == self.context else { return }
        guard row.isPending || row.isFriend else {
            cancel(row.id, context: context)
            return
        }
        let stage = row.status == "public" ? 2 : row.status == "private" ? 1 : 0
        let id = Self.digest(row.id)
        let previous = stages[id]
        if let previous, stage <= previous { return }
        stages[id] = max(previous ?? 0, stage)
        if let key { defaults.set(stages, forKey: key) }
        guard let kind = Milestone.Kind(rawValue: stage), previous != nil || allowNew else { return }
        pending.removeAll { $0.connectionID == row.id }
        pending.append(Milestone(connectionID: row.id, kind: kind))
        revision += 1
    }

    func cancel(_ id: String, context: UUID?) {
        guard context != nil, context == self.context,
            pending.contains(where: { $0.connectionID == id }) || presented?.connectionID == id
        else { return }
        pending.removeAll { $0.connectionID == id }
        if presented?.connectionID == id {
            presented = nil
            owner = nil
        }
        revision += 1
    }

    func claim(owner: UUID) -> Milestone? {
        guard context != nil, presented == nil, !pending.isEmpty else { return nil }
        let event = pending.removeFirst()
        presented = event
        self.owner = owner
        haptic()
        return event
    }

    func dismiss(owner: UUID) {
        guard self.owner == owner else { return }
        presented = nil
        self.owner = nil
        revision += 1
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    #if DEBUG
        func preview(_ kind: Milestone.Kind) {
            guard key == nil, context != nil else { return }
            let status = kind == .privateChat ? "private" : "public"
            let json = """
                {"id":"preview-celebration","status":"\(status)","sharedInterests":[],"them":null,
                "expiresAt":"2026-12-01T00:00:00Z"}
                """
            guard let row = try? JSONDecoder().decode(TownConnection.self, from: Data(json.utf8)) else {
                return
            }
            observe(row, context: context, allowNew: true)
        }
    #endif
}
