import Foundation

extension APIClient {
    public func onboarding() async throws -> OnboardingState {
        try decode(
            OnboardingState.self,
            from: try await send(APIRequest(path: "api/onboarding", authenticated: true)))
    }

    public func updateOnboarding(_ values: [String: FieldValue]) async throws -> OnboardingState {
        struct Update: Encodable { let values: [String: FieldValue] }
        let response = try await send(
            APIRequest(
                path: "api/onboarding", method: "PATCH",
                body: try JSONEncoder().encode(Update(values: values)),
                authenticated: true))
        return try decode(OnboardingState.self, from: response)
    }
}
