import Foundation

/// Stage 1's anonymous test token. This is neither an account identity nor an auth credential.
public struct DiscoveryToken: Hashable, Sendable {
    public static let packetLength = 17
    private let value: UUID

    public init() {
        value = UUID()
    }

    /// The version byte and 16 token bytes fit in the default 20-byte ATT write payload.
    public var packet: Data {
        var uuid = value.uuid
        return Data([1]) + withUnsafeBytes(of: &uuid) { Data($0) }
    }

    public init(packet: Data) throws {
        guard packet.count == Self.packetLength else { throw DiscoveryPacketError.invalidLength }
        let bytes = Array(packet)
        guard bytes[0] == 1 else { throw DiscoveryPacketError.unsupportedVersion }
        value = UUID(
            uuid: (
                bytes[1], bytes[2], bytes[3], bytes[4],
                bytes[5], bytes[6], bytes[7], bytes[8],
                bytes[9], bytes[10], bytes[11], bytes[12],
                bytes[13], bytes[14], bytes[15], bytes[16]
            ))
    }

    /// For comparing two diagnostic screens; never use this truncated code as an identity.
    public var shortCode: String {
        String(value.uuidString.prefix(8)).lowercased()
    }
}

public enum DiscoveryPacketError: Error, Equatable {
    case invalidLength
    case unsupportedVersion
}

public struct DiscoveryEncounter: Identifiable, Sendable, Equatable {
    public let id: DiscoveryToken
    public let observedAt: Date
    public let elapsed: TimeInterval
}

/// In-memory, session-scoped deduplication shared by incoming and outgoing exchanges.
public struct DiscoverySession: Sendable {
    public static let encounterLimit = 100
    public let token: DiscoveryToken
    public let startedAt: Date
    public private(set) var encounters: [DiscoveryEncounter] = []
    private var seen: Set<DiscoveryToken> = []

    public init(token: DiscoveryToken = DiscoveryToken(), startedAt: Date = Date()) {
        self.token = token
        self.startedAt = startedAt
    }

    /// Public radio input is untrusted. Ignore reflection, duplicates, and excess tokens.
    @discardableResult
    public mutating func record(_ peer: DiscoveryToken, at date: Date = Date()) -> DiscoveryEncounter? {
        guard peer != token, !seen.contains(peer), encounters.count < Self.encounterLimit else {
            return nil
        }
        let encounter = DiscoveryEncounter(
            id: peer, observedAt: date, elapsed: max(0, date.timeIntervalSince(startedAt)))
        seen.insert(peer)
        encounters.append(encounter)
        return encounter
    }
}
