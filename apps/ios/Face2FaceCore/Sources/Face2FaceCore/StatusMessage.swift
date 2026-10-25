import Foundation

/// The short line a person shows to their public connections.
public enum StatusMessage {
    /// Matches the server, which counts Unicode code points.
    public static let maxLength = 80

    /// One line of text, or nil when nothing is left after trimming.
    public static func normalized(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return line.isEmpty ? nil : line
    }

    public static func isTooLong(_ text: String) -> Bool {
        (normalized(text)?.unicodeScalars.count ?? 0) > maxLength
    }
}
