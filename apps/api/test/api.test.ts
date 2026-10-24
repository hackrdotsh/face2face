import { env, exports } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { webOrigins } from "../src/origins";
import {
  bearerHeaders,
  callAPI,
  completeOnboarding,
  lastCodeSentTo,
  postJSON,
  requireAuthToken,
  signInWithEmailCode,
  testPassword,
} from "./helpers";

const origin = "http://localhost:8787";

beforeEach(async () => {
  await env.DB.prepare("DELETE FROM rate_limit").run();
});

describe("API foundation", () => {
  it("authenticates native clients with signed bearer tokens and revokes them on sign-out", async () => {
    const token = await signInWithEmailCode("iphone@example.test");
    const headers = bearerHeaders(token);
    expect((await callAPI("/api/me", { headers })).status).toBe(200);
    const signedOut = await callAPI("/api/auth/sign-out", {
      method: "POST",
      headers,
    });
    expect(signedOut.status).toBe(200);
    expect((await callAPI("/api/me", { headers })).status).toBe(401);
  });

  it("rejects unsigned bearer tokens", async () => {
    const response = await exports.default.fetch(`${origin}/api/me`, {
      headers: { Authorization: "Bearer unsigned-session-token" },
    });
    expect(response.status).toBe(401);
  });
  it("does not enable a Tailscale origin when development override is empty", () => {
    expect(webOrigins({ ...env, DEV_WEB_ORIGIN: "" })).toEqual(env.WEB_ORIGINS);
  });
  it("rejects an untrusted auth origin", async () => {
    const response = await exports.default.fetch(
      `${origin}/api/auth/sign-up/email`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Origin: "https://untrusted.example",
        },
        body: JSON.stringify({
          name: "Blocked",
          email: "blocked@example.test",
          password: "test-password-123456",
        }),
      },
    );
    expect(response.status).toBe(403);
  });

  it("rejects short passwords", async () => {
    const response = await exports.default.fetch(
      `${origin}/api/auth/sign-up/email`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Origin: "http://localhost:8081",
        },
        body: JSON.stringify({
          name: "Blocked",
          email: "short@example.test",
          password: "short",
        }),
      },
    );
    expect(response.status).toBe(400);
  });
  it("serves health and returns JSON for missing routes", async () => {
    const response = await exports.default.fetch(`${origin}/health`);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      status: "ok",
      service: "face2face-api",
    });
    expect((await exports.default.fetch(`${origin}/missing`)).status).toBe(404);
  });

  it("requires a session for user and coordinator data", async () => {
    for (const path of ["/api/me", "/api/coordinator"]) {
      expect((await exports.default.fetch(`${origin}${path}`)).status).toBe(
        401,
      );
    }
  });

  it("does not grant browser access to an untrusted origin", async () => {
    const response = await exports.default.fetch(`${origin}/api/me`, {
      headers: { Origin: "https://untrusted.example" },
    });
    expect(response.headers.get("Access-Control-Allow-Origin")).not.toBe(
      "https://untrusted.example",
    );
  });

  it("allows the Metro and built-preview origins to check the API", async () => {
    for (const webOrigin of [
      "http://localhost:8081",
      "http://127.0.0.1:8081",
      "http://100.100.20.30:8081",
    ]) {
      const response = await exports.default.fetch(`${origin}/health`, {
        headers: { Origin: webOrigin },
      });
      expect(response.headers.get("Access-Control-Allow-Origin")).toBe(
        webOrigin,
      );
    }
  });

  it("rejects oversized auth requests", async () => {
    const response = await exports.default.fetch(
      `${origin}/api/auth/sign-up/email`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: "x".repeat(17000) }),
      },
    );
    expect(response.status).toBe(413);
  });

  it("verifies a browser sign-up, persists a session in D1, gates the Durable Object on onboarding, and signs out", async () => {
    const browserOrigin = "http://100.100.20.30:8081";
    const email = "person@example.test";
    const signUp = await postJSON(
      "/api/auth/sign-up/email",
      { name: "", email, password: testPassword },
      { Origin: browserOrigin },
    );
    expect(signUp.status).toBe(200);
    const verified = await postJSON(
      "/api/auth/email-otp/verify-email",
      { email, otp: await lastCodeSentTo(email) },
      { Origin: browserOrigin },
    );
    expect(verified.status).toBe(200);
    const cookies = verified.headers
      .getSetCookie()
      .map((cookie) => cookie.split(";")[0])
      .join("; ");
    expect(cookies).toContain("better-auth.session_token");
    const headers = { Cookie: cookies, Origin: browserOrigin };
    const me = await callAPI("/api/me", { headers });
    expect(me.status).toBe(200);
    expect(me.headers.get("Cache-Control")).toBe("no-store");
    expect(await me.json()).toMatchObject({
      user: { email },
      onboardingComplete: false,
    });
    const blocked = await callAPI("/api/coordinator", { headers });
    expect(blocked.status).toBe(403);
    expect(await blocked.json()).toEqual({ error: "onboarding_required" });
    await completeOnboarding(requireAuthToken(verified));
    const coordinator = await callAPI("/api/coordinator", { headers });
    expect(await coordinator.json()).toEqual({
      ready: true,
      storage: "sqlite",
    });
    const row = await env.DB.prepare(
      'SELECT count(*) AS total FROM "session"',
    ).first<{ total: number }>();
    expect(row?.total).toBeGreaterThanOrEqual(1);
    const signOut = await callAPI("/api/auth/sign-out", {
      method: "POST",
      headers,
    });
    expect(signOut.status).toBe(200);
    expect((await callAPI("/api/me", { headers })).status).toBe(401);
  });
});
