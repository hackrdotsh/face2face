import Foundation

public struct InterestChoice: Decodable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let memberCount: Int
    public let selected: Bool

    public init(id: String, name: String, memberCount: Int, selected: Bool) {
        self.id = id
        self.name = name
        self.memberCount = memberCount
        self.selected = selected
    }
}

/// Every interest, marked with the signed-in person's picks.
public struct InterestCatalog: Decodable, Sendable, Equatable {
    public let maxSelected: Int
    public let interests: [InterestChoice]

    public init(maxSelected: Int, interests: [InterestChoice]) {
        self.maxSelected = maxSelected
        self.interests = interests
    }

    public var selected: [InterestChoice] { interests.filter(\.selected) }
    public var isFull: Bool { selected.count >= maxSelected }

    /// The interest whose name matches `query` after normalization.
    public func exactMatch(for query: String) -> InterestChoice? {
        let name = InterestName.normalize(query)
        return interests.first { $0.name == name }
    }

    /// Interests ranked for `query`. Names that start with the query come first, then names
    /// with a word that starts with it, then names that contain it. Each group puts the most
    /// members first, then sorts by name. An empty query ranks everything by members.
    public func ranked(for query: String) -> [InterestChoice] {
        let needle = InterestName.normalize(query)
        return interests.compactMap { choice in
            InterestName.matchRank(of: choice.name, for: needle).map { (choice, $0) }
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            if lhs.0.memberCount != rhs.0.memberCount { return lhs.0.memberCount > rhs.0.memberCount }
            return lhs.0.name < rhs.0.name
        }
        .map(\.0)
    }
}

/// Mirrors the server's interest name rules, so the app only offers names it will accept.
public enum InterestName {
    public static let lengthRange = 2...32

    public static func normalize(_ raw: String) -> String {
        raw.precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    /// Whether a normalized name can become a new interest.
    public static func isValid(_ name: String) -> Bool {
        guard lengthRange.contains(name.unicodeScalars.count), let first = name.unicodeScalars.first,
            let last = name.unicodeScalars.last, isAlphanumeric(first), isAlphanumeric(last)
        else { return false }
        return name.unicodeScalars.allSatisfy { isAlphanumeric($0) || " &'-".unicodeScalars.contains($0) }
    }

    private static func isAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isAlphabetic || scalar.properties.numericType != nil
    }

    static func matchRank(of name: String, for needle: String) -> Int? {
        if needle.isEmpty { return 0 }
        if name.hasPrefix(needle) { return 0 }
        if name.split(separator: " ").contains(where: { $0.hasPrefix(needle) }) { return 1 }
        if name.contains(needle) { return 2 }
        return nil
    }
}
