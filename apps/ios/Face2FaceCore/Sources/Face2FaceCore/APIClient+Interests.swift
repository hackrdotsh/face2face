import Foundation

extension APIClient {
    public func interests() async throws -> InterestCatalog {
        try decode(
            InterestCatalog.self, from: try await send(APIRequest(path: "api/interests", authenticated: true))
        )
    }

    /// Replaces the signed-in person's picks with `ids`.
    public func replaceInterests(_ ids: [String]) async throws -> InterestCatalog {
        struct Body: Encodable { let interestIds: [String] }
        let response = try await send(
            APIRequest(
                path: "api/interests", method: "PUT", body: try JSONEncoder().encode(Body(interestIds: ids)),
                authenticated: true))
        return try decode(InterestCatalog.self, from: response)
    }

    /// Picks the interest with this name, creating it when none exists.
    public func addInterest(named name: String) async throws -> InterestCatalog {
        struct Body: Encodable { let name: String }
        return try decode(
            InterestCatalog.self,
            from: try await post("api/interests", Body(name: name), authenticated: true))
    }
}
