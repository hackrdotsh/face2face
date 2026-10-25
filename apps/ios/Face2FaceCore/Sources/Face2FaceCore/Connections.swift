import Foundation

public enum ConnectionDecision: String, Codable, Sendable { case accepted, declined }

public protocol EncounterRepository: Sendable {
    func townConnections() async throws -> [TownConnection]
    func decideConnection(_ id: String, decision: ConnectionDecision) async throws -> TownConnection
    func blockConnection(_ id: String) async throws
}

extension APIClient: EncounterRepository {
    /// Answers as the authenticated person. No caller-supplied user ID or side.
    public func decideConnection(_ id: String, decision: ConnectionDecision) async throws -> TownConnection {
        struct Result: Decodable { let connection: TownConnection }
        let response = try await post(
            try Self.connectionPath(id) + "/decision", ["decision": decision.rawValue], authenticated: true)
        return try decode(Result.self, from: response).connection
    }

    public func blockConnection(_ id: String) async throws {
        _ = try await post(try Self.connectionPath(id) + "/block", [String: String](), authenticated: true)
    }

    private static func connectionPath(_ id: String) throws -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard !id.isEmpty, id.utf8.count <= 256, id != ".", id != "..",
            id.unicodeScalars.allSatisfy(allowed.contains)
        else { throw APIError.invalidResponse }
        return "api/connections/" + id
    }
}
