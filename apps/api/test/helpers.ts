import { exports } from "cloudflare:workers";
import { afterEach, vi } from "vitest";

export const origin = "http://localhost:8080";
export const nativeOrigin = "face2face://";
export const testPassword = "test-password-123456";

export function callAPI(path: string, init: RequestInit = {}) {
  return exports.default.fetch(`${origin}${path}`, init);
}

export function postJSON(
  path: string,
  body: unknown,
  headers: Record<string, string> = {},
) {
  return callAPI(path, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Origin: nativeOrigin,
      ...headers,
    },
    body: JSON.stringify(body),
  });
}

export function bearerHeaders(token: string) {
  return { Authorization: `Bearer ${token}`, Origin: nativeOrigin };
}

interface LoggedEmail {
  to: string;
  subject: string;
  text: string;
}

const emailLog = vi.spyOn(console, "info").mockImplementation(() => {});

afterEach(() => emailLog.mockClear());

export function lastCodeSentTo(email: string): Promise<string> {
  return vi.waitFor(() => {
    const message = emailLog.mock.calls
      .map(([line]) => JSON.parse(String(line)) as LoggedEmail)
      .findLast((logged) => logged.to === email);
    const code = message?.text.match(/\b\d{6}\b/)?.[0];
    if (!code) throw new Error(`No code was emailed to ${email}`);
    return code;
  });
}

export function requireAuthToken(response: Response): string {
  const token = response.headers.get("set-auth-token");
  if (!token) throw new Error(`No auth token in HTTP ${response.status}`);
  return token;
}

export async function signInWithEmailCode(email: string): Promise<string> {
  await postJSON("/api/auth/email-otp/send-verification-otp", {
    email,
    type: "sign-in",
  });
  const response = await postJSON("/api/auth/sign-in/email-otp", {
    email,
    otp: await lastCodeSentTo(email),
  });
  return requireAuthToken(response);
}

export async function completeOnboarding(token: string) {
  const response = await callAPI("/api/onboarding", {
    method: "PATCH",
    headers: { ...bearerHeaders(token), "Content-Type": "application/json" },
    body: JSON.stringify({
      values: {
        name: "Test person",
        birthDate: "1990-05-17",
        gender: { optionId: "female" },
      },
    }),
  });
  if (response.status !== 200) {
    throw new Error(`Onboarding failed with HTTP ${response.status}`);
  }
}
