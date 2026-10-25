import type { APIClient } from "./client";

export type EmailCodePurpose =
  | "sign-in"
  | "email-verification"
  | "forget-password";

export function sendSignInCode(client: APIClient, email: string) {
  return client.send({
    path: "api/auth/email-otp/send-verification-otp",
    body: { email, type: "sign-in" satisfies EmailCodePurpose },
  });
}

export function signInWithCode(client: APIClient, email: string, code: string) {
  return client.send({
    path: "api/auth/sign-in/email-otp",
    body: { email, otp: code },
  });
}

export function signInWithPassword(
  client: APIClient,
  email: string,
  password: string,
) {
  return client.send({
    path: "api/auth/sign-in/email",
    body: { email, password },
  });
}

/** Creates a password account. The server emails a code to pass to `verifyEmail`. */
export function createAccount(
  client: APIClient,
  email: string,
  password: string,
) {
  return client.send({
    path: "api/auth/sign-up/email",
    body: { name: "", email, password },
  });
}

export function verifyEmail(client: APIClient, email: string, code: string) {
  return client.send({
    path: "api/auth/email-otp/verify-email",
    body: { email, otp: code },
  });
}

export function resendVerificationCode(client: APIClient, email: string) {
  return client.send({
    path: "api/auth/email-otp/send-verification-otp",
    body: { email, type: "email-verification" satisfies EmailCodePurpose },
  });
}

export function requestPasswordReset(client: APIClient, email: string) {
  return client.send({
    path: "api/auth/email-otp/request-password-reset",
    body: { email },
  });
}

export function resetPassword(
  client: APIClient,
  email: string,
  code: string,
  password: string,
) {
  return client.send({
    path: "api/auth/email-otp/reset-password",
    body: { email, otp: code, password },
  });
}

export async function signOut(client: APIClient) {
  try {
    await client.send({
      path: "api/auth/sign-out",
      body: {},
      authenticated: true,
    });
  } finally {
    client.clearToken();
  }
}
