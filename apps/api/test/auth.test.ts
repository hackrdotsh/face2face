import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import {
  bearerHeaders,
  callAPI,
  lastCodeSentTo,
  postJSON,
  requireAuthToken,
  signInWithEmailCode,
  testPassword,
} from "./helpers";

beforeEach(async () => {
  await env.DB.prepare("DELETE FROM rate_limit").run();
});

async function signUpWithPassword(email: string) {
  const response = await postJSON("/api/auth/sign-up/email", {
    name: "",
    email,
    password: testPassword,
  });
  expect(response.status).toBe(200);
  return response;
}

describe("email and password", () => {
  it("does not issue a session until the email is verified", async () => {
    const email = "unverified@example.test";
    const signUp = await signUpWithPassword(email);
    expect(signUp.headers.get("set-auth-token")).toBeNull();
    const signIn = await postJSON("/api/auth/sign-in/email", {
      email,
      password: testPassword,
    });
    expect(signIn.status).toBe(403);
  });

  it("signs in with the password after the emailed code verifies the address", async () => {
    const email = "verified@example.test";
    await signUpWithPassword(email);
    const verified = await postJSON("/api/auth/email-otp/verify-email", {
      email,
      otp: await lastCodeSentTo(email),
    });
    expect(verified.status).toBe(200);
    requireAuthToken(verified);
    const signIn = await postJSON("/api/auth/sign-in/email", {
      email,
      password: testPassword,
    });
    expect(signIn.status).toBe(200);
    const me = await callAPI("/api/me", {
      headers: bearerHeaders(requireAuthToken(signIn)),
    });
    expect(await me.json()).toMatchObject({ user: { email } });
  });

  it("resets the password with an emailed code and revokes existing sessions", async () => {
    const email = "reset@example.test";
    const oldToken = await signInWithEmailCode(email);
    const requested = await postJSON(
      "/api/auth/email-otp/request-password-reset",
      {
        email,
      },
    );
    expect(requested.status).toBe(200);
    const newPassword = "a-brand-new-password-987";
    const reset = await postJSON("/api/auth/email-otp/reset-password", {
      email,
      otp: await lastCodeSentTo(email),
      password: newPassword,
    });
    expect(reset.status).toBe(200);
    expect(
      (await callAPI("/api/me", { headers: bearerHeaders(oldToken) })).status,
    ).toBe(401);
    const signIn = await postJSON("/api/auth/sign-in/email", {
      email,
      password: newPassword,
    });
    expect(signIn.status).toBe(200);
  });
});

describe("email code sign-in", () => {
  it("creates an account on first sign-in and reuses it after", async () => {
    const email = "code@example.test";
    const first = await signInWithEmailCode(email);
    const second = await signInWithEmailCode(email);
    const firstUser = await (
      await callAPI("/api/me", { headers: bearerHeaders(first) })
    ).json();
    const secondUser = await (
      await callAPI("/api/me", { headers: bearerHeaders(second) })
    ).json();
    expect(firstUser).toEqual(secondUser);
    const users = await env.DB.prepare(
      "SELECT count(*) AS total FROM user WHERE email = ?",
    )
      .bind(email)
      .first<{ total: number }>();
    expect(users?.total).toBe(1);
  });

  it("rejects a wrong code and does not store codes in plain text", async () => {
    const email = "wrong-code@example.test";
    await postJSON("/api/auth/email-otp/send-verification-otp", {
      email,
      type: "sign-in",
    });
    const code = await lastCodeSentTo(email);
    const wrongCode = code === "000000" ? "111111" : "000000";
    const rejected = await postJSON("/api/auth/sign-in/email-otp", {
      email,
      otp: wrongCode,
    });
    expect(rejected.status).toBe(400);
    expect(rejected.headers.get("set-auth-token")).toBeNull();
    const stored = await env.DB.prepare(
      "SELECT value FROM verification WHERE identifier LIKE ?",
    )
      .bind(`%${email}%`)
      .all<{ value: string }>();
    expect(stored.results.length).toBeGreaterThan(0);
    for (const row of stored.results) expect(row.value).not.toContain(code);
  });
});

describe("passkeys", () => {
  it("requires a session to start passkey registration", async () => {
    const response = await callAPI(
      "/api/auth/passkey/generate-register-options",
      {
        headers: { Origin: "face2face://" },
      },
    );
    expect(response.status).toBe(401);
  });

  it("returns registration options and a challenge cookie for a signed-in person", async () => {
    const token = await signInWithEmailCode("passkey@example.test");
    const response = await callAPI(
      "/api/auth/passkey/generate-register-options",
      {
        headers: bearerHeaders(token),
      },
    );
    expect(response.status).toBe(200);
    const options = await response.json<{
      challenge: string;
      rp: { id: string };
    }>();
    expect(options.challenge).toBeTruthy();
    expect(options.rp.id).toBe("localhost");
    expect(response.headers.getSetCookie().join(";")).toContain(
      "better-auth-passkey",
    );
  });

  it("returns sign-in options without a session", async () => {
    const response = await callAPI(
      "/api/auth/passkey/generate-authenticate-options",
      { headers: { Origin: "face2face://" } },
    );
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ rpId: "localhost" });
    expect(response.headers.getSetCookie().join(";")).toContain(
      "better-auth-passkey",
    );
  });
});
