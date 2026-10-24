import {
  type PublicKeyCredentialCreationOptionsJSON,
  type PublicKeyCredentialRequestOptionsJSON,
  startAuthentication,
  startRegistration,
} from "@simplewebauthn/browser";
import type { APIClient } from "./client";
import type { Passkey } from "./types";

export async function registerPasskey(client: APIClient, name: string) {
  const optionsJSON = await client.send<PublicKeyCredentialCreationOptionsJSON>(
    {
      path: "api/auth/passkey/generate-register-options",
      query: { name },
      authenticated: true,
      withCookies: true,
    },
  );
  const response = await startRegistration({ optionsJSON });
  return client.send<Passkey>({
    path: "api/auth/passkey/verify-registration",
    body: { response, name },
    authenticated: true,
    withCookies: true,
  });
}

export async function signInWithPasskey(client: APIClient) {
  const optionsJSON = await client.send<PublicKeyCredentialRequestOptionsJSON>({
    path: "api/auth/passkey/generate-authenticate-options",
    withCookies: true,
  });
  const response = await startAuthentication({ optionsJSON });
  return client.send({
    path: "api/auth/passkey/verify-authentication",
    body: { response },
    withCookies: true,
  });
}

export function listPasskeys(client: APIClient) {
  return client.send<Passkey[]>({
    path: "api/auth/passkey/list-user-passkeys",
    authenticated: true,
  });
}

export function deletePasskey(client: APIClient, id: string) {
  return client.send({
    path: "api/auth/passkey/delete-passkey",
    body: { id },
    authenticated: true,
  });
}
