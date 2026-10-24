import Foundation

/// The server keeps each WebAuthn challenge behind a signed cookie, which must be sent back with the
/// matching verify request even though the transport otherwise ignores cookies.
struct PasskeyChallengeCookie: Sendable, Equatable {
    static let nameSuffix = "better-auth-passkey"
    let header: String

    init(from response: HTTPResponse) throws {
        guard let cookie = response.cookies.first(where: { $0.key.hasSuffix(Self.nameSuffix) }) else {
            throw APIError.invalidResponse
        }
        header = "\(cookie.key)=\(cookie.value)"
    }
}

public struct PasskeyRegistrationChallenge: Sendable, Equatable {
    public let relyingPartyID: String
    public let challenge: Data
    public let userID: Data
    public let userName: String
    public let excludedCredentialIDs: [Data]
    let cookie: PasskeyChallengeCookie
}

public struct PasskeySignInChallenge: Sendable, Equatable {
    public let relyingPartyID: String
    public let challenge: Data
    public let allowedCredentialIDs: [Data]
    let cookie: PasskeyChallengeCookie
}

public struct PasskeyRegistration: Sendable {
    public let credentialID: Data
    public let clientDataJSON: Data
    public let attestationObject: Data

    public init(credentialID: Data, clientDataJSON: Data, attestationObject: Data) {
        self.credentialID = credentialID
        self.clientDataJSON = clientDataJSON
        self.attestationObject = attestationObject
    }
}

public struct PasskeyAssertion: Sendable {
    public let credentialID: Data
    public let clientDataJSON: Data
    public let authenticatorData: Data
    public let signature: Data
    public let userID: Data?

    public init(
        credentialID: Data, clientDataJSON: Data, authenticatorData: Data, signature: Data, userID: Data?
    ) {
        self.credentialID = credentialID
        self.clientDataJSON = clientDataJSON
        self.authenticatorData = authenticatorData
        self.signature = signature
        self.userID = userID
    }
}

private struct CredentialDescriptor: Decodable { let id: String }

private struct RegistrationOptions: Decodable {
    struct RelyingParty: Decodable { let id: String }
    struct UserEntity: Decodable {
        let id: String
        let name: String
    }
    let challenge: String
    let rp: RelyingParty
    let user: UserEntity
    let excludeCredentials: [CredentialDescriptor]?
}

private struct AuthenticationOptions: Decodable {
    let challenge: String
    let rpId: String
    let allowCredentials: [CredentialDescriptor]?
}

private struct RegistrationResponseJSON: Encodable {
    struct Response: Encodable {
        let clientDataJSON: String
        let attestationObject: String
        let transports = ["internal", "hybrid"]
    }
    let id: String
    let rawId: String
    let type = "public-key"
    let response: Response
    let authenticatorAttachment = "platform"
    let clientExtensionResults: [String: String] = [:]
}

private struct AuthenticationResponseJSON: Encodable {
    struct Response: Encodable {
        let clientDataJSON: String
        let authenticatorData: String
        let signature: String
        let userHandle: String?
    }
    let id: String
    let rawId: String
    let type = "public-key"
    let response: Response
    let authenticatorAttachment = "platform"
    let clientExtensionResults: [String: String] = [:]
}

extension APIClient {
    public func passkeyRegistrationChallenge(userName: String) async throws -> PasskeyRegistrationChallenge {
        let response = try await send(
            APIRequest(
                path: "api/auth/passkey/generate-register-options",
                query: [
                    URLQueryItem(name: "name", value: userName),
                    URLQueryItem(name: "authenticatorAttachment", value: "platform"),
                ],
                authenticated: true))
        let options = try decode(RegistrationOptions.self, from: response)
        guard let challenge = Data(base64URLEncoded: options.challenge),
            let userID = Data(base64URLEncoded: options.user.id)
        else { throw APIError.invalidResponse }
        return PasskeyRegistrationChallenge(
            relyingPartyID: options.rp.id, challenge: challenge, userID: userID, userName: options.user.name,
            excludedCredentialIDs: try credentialIDs(options.excludeCredentials),
            cookie: try PasskeyChallengeCookie(from: response))
    }

    public func registerPasskey(
        _ registration: PasskeyRegistration, for challenge: PasskeyRegistrationChallenge
    )
        async throws
    {
        struct Body: Encodable {
            let response: RegistrationResponseJSON
            let name: String
        }
        let credentialID = registration.credentialID.base64URLEncodedString()
        let body = Body(
            response: RegistrationResponseJSON(
                id: credentialID, rawId: credentialID,
                response: .init(
                    clientDataJSON: registration.clientDataJSON.base64URLEncodedString(),
                    attestationObject: registration.attestationObject.base64URLEncodedString())),
            name: "iPhone")
        _ = try await post(
            "api/auth/passkey/verify-registration", body, authenticated: true, cookie: challenge.cookie.header
        )
    }

    public func passkeySignInChallenge() async throws -> PasskeySignInChallenge {
        let response = try await send(APIRequest(path: "api/auth/passkey/generate-authenticate-options"))
        let options = try decode(AuthenticationOptions.self, from: response)
        guard let challenge = Data(base64URLEncoded: options.challenge) else {
            throw APIError.invalidResponse
        }
        return PasskeySignInChallenge(
            relyingPartyID: options.rpId, challenge: challenge,
            allowedCredentialIDs: try credentialIDs(options.allowCredentials),
            cookie: try PasskeyChallengeCookie(from: response))
    }

    public func signIn(with assertion: PasskeyAssertion, for challenge: PasskeySignInChallenge) async throws {
        struct Body: Encodable { let response: AuthenticationResponseJSON }
        let credentialID = assertion.credentialID.base64URLEncodedString()
        let body = Body(
            response: AuthenticationResponseJSON(
                id: credentialID, rawId: credentialID,
                response: .init(
                    clientDataJSON: assertion.clientDataJSON.base64URLEncodedString(),
                    authenticatorData: assertion.authenticatorData.base64URLEncodedString(),
                    signature: assertion.signature.base64URLEncodedString(),
                    userHandle: assertion.userID?.base64URLEncodedString())))
        let response = try await post(
            "api/auth/passkey/verify-authentication", body, cookie: challenge.cookie.header)
        try await saveSessionToken(from: response)
    }

    private func credentialIDs(_ descriptors: [CredentialDescriptor]?) throws -> [Data] {
        try (descriptors ?? []).map {
            guard let id = Data(base64URLEncoded: $0.id) else { throw APIError.invalidResponse }
            return id
        }
    }
}
