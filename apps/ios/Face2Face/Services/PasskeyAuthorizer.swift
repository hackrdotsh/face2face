import AuthenticationServices
import Face2FaceCore
import UIKit

enum PasskeyError: LocalizedError {
    case unexpectedCredential
    case alreadyInProgress

    var errorDescription: String? {
        switch self {
        case .unexpectedCredential: "The passkey response was not usable. Try again."
        case .alreadyInProgress: "A passkey request is already open."
        }
    }
}

/// Runs passkey ceremonies with AuthenticationServices and returns the raw credential data.
@MainActor
final class PasskeyAuthorizer: NSObject {
    private var pending: CheckedContinuation<PasskeyCredential, any Error>?

    func register(_ challenge: PasskeyRegistrationChallenge) async throws -> PasskeyRegistration {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: challenge.relyingPartyID)
        let request = provider.createCredentialRegistrationRequest(
            challenge: challenge.challenge, name: challenge.userName, userID: challenge.userID)
        if #available(iOS 17.4, *) {
            request.excludedCredentials = challenge.excludedCredentialIDs.map {
                ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
            }
        }
        guard case .registration(let registration) = try await perform(request) else {
            throw PasskeyError.unexpectedCredential
        }
        return registration
    }

    func signIn(_ challenge: PasskeySignInChallenge) async throws -> PasskeyAssertion {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: challenge.relyingPartyID)
        let request = provider.createCredentialAssertionRequest(challenge: challenge.challenge)
        request.allowedCredentials = challenge.allowedCredentialIDs.map {
            ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
        }
        guard case .assertion(let assertion) = try await perform(request) else {
            throw PasskeyError.unexpectedCredential
        }
        return assertion
    }

    private func perform(_ request: ASAuthorizationRequest) async throws -> PasskeyCredential {
        guard pending == nil else { throw PasskeyError.alreadyInProgress }
        return try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<PasskeyCredential, any Error>) {
        pending?.resume(with: result)
        pending = nil
    }
}

enum PasskeyCredential: Sendable {
    case registration(PasskeyRegistration)
    case assertion(PasskeyAssertion)

    init(_ credential: any ASAuthorizationCredential) throws {
        if let registration = credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
            let attestationObject = registration.rawAttestationObject
        {
            self = .registration(
                PasskeyRegistration(
                    credentialID: registration.credentialID, clientDataJSON: registration.rawClientDataJSON,
                    attestationObject: attestationObject))
        } else if let assertion = credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
            self = .assertion(
                PasskeyAssertion(
                    credentialID: assertion.credentialID, clientDataJSON: assertion.rawClientDataJSON,
                    authenticatorData: assertion.rawAuthenticatorData, signature: assertion.signature,
                    userID: assertion.userID))
        } else {
            throw PasskeyError.unexpectedCredential
        }
    }
}

extension PasskeyAuthorizer: @preconcurrency ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        finish(Result { try PasskeyCredential(authorization.credential) })
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error)
    {
        finish(.failure(error))
    }
}

extension PasskeyAuthorizer: @preconcurrency ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let windows = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }
        return windows.first ?? ASPresentationAnchor()
    }
}
