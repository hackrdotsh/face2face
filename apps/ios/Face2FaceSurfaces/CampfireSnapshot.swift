import Foundation

struct CampfireGuest: Codable, Equatable, Identifiable, Sendable {
    /// A local drawing slot, never an account/connection identifier.
    let id: Int
    let name: String
    let seed: String
    let isAnonymous: Bool
}

struct CampfireSnapshot: Codable, Equatable, Sendable {
    enum Status: String, Codable { case ready, disabled, signedOut, unavailable, expired }
    let status: Status
    var ownSeed = BlobSurface.previewSeed
    var guests: [CampfireGuest] = []
    var updatedAt = Date()
    static let lifetime: TimeInterval = 15 * 60

    var expiresAt: Date { updatedAt.addingTimeInterval(Self.lifetime) }

    func visible(at date: Date) -> Self {
        guard status == .ready else { return .init(status: status) }
        guard updatedAt.timeIntervalSince(date) <= 5, date < expiresAt else { return .init(status: .expired) }
        return self
    }

    func pageCount(size: Int) -> Int { max(1, (guests.count + max(1, size) - 1) / max(1, size)) }

    func page(_ index: Int, size: Int) -> [CampfireGuest] {
        let size = max(1, size)
        let page = ((index % pageCount(size: size)) + pageCount(size: size)) % pageCount(size: size)
        return Array(guests.dropFirst(page * size).prefix(size))
    }
}

enum CampfireStore {
    static let group = "group.systems.rocky.face2face"
    static let preferenceKey = "campfireWidgetEnabled"
    private static let snapshotKey = "campfire.snapshot.v1"

    static func read(defaults: UserDefaults? = UserDefaults(suiteName: group), at date: Date = .now)
        -> CampfireSnapshot
    {
        guard let data = defaults?.data(forKey: snapshotKey),
            let snapshot = try? JSONDecoder().decode(CampfireSnapshot.self, from: data)
        else { return .init(status: .disabled) }
        return snapshot.visible(at: date)
    }

    @discardableResult static func write(
        _ snapshot: CampfireSnapshot, defaults: UserDefaults? = UserDefaults(suiteName: group)
    ) -> Bool {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return false }
        defaults.set(data, forKey: snapshotKey)
        return true
    }

    static func page(size: Int, defaults: UserDefaults? = UserDefaults(suiteName: group)) -> Int {
        defaults?.integer(forKey: "campfire.page.\(size)") ?? 0
    }

    static func advance(by step: Int, size: Int, defaults: UserDefaults? = UserDefaults(suiteName: group)) {
        let snapshot = read(defaults: defaults)
        guard snapshot.status == .ready else { return }
        let count = snapshot.pageCount(size: size)
        let index = (page(size: size, defaults: defaults) % count + count) % count
        defaults?.set((index + (step < 0 ? -1 : 1) + count) % count, forKey: "campfire.page.\(size)")
    }

    static func clear(
        _ status: CampfireSnapshot.Status, defaults: UserDefaults? = UserDefaults(suiteName: group)
    ) {
        write(.init(status: status), defaults: defaults)
        for size in [4, 6, 10] { defaults?.removeObject(forKey: "campfire.page.\(size)") }
    }
}
