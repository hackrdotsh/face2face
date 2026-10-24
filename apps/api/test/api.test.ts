import { applyD1Migrations } from "cloudflare:test";
import { env, exports } from "cloudflare:workers";
import { beforeAll, describe, expect, it } from "vitest";
import migration from "../migrations/0000_past_cyclops.sql?raw";

beforeAll(async () => {
  await applyD1Migrations(env.DB, [
    {
      name: "0000_past_cyclops",
      queries: migration.split("--> statement-breakpoint"),
    },
  ]);
});

const origin = "http://localhost:8787";

describe("API foundation", () => {
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

  it("registers, persists a session in D1, calls a user-scoped Durable Object, and signs out", async () => {
    const response = await exports.default.fetch(
      `${origin}/api/auth/sign-up/email`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Origin: "http://localhost:8081",
        },
        body: JSON.stringify({
          name: "Test person",
          email: "person@example.test",
          password: "test-password-123456",
        }),
      },
    );
    expect(response.status).toBe(200);
    const cookies = response.headers
      .getSetCookie()
      .map((cookie) => cookie.split(";")[0])
      .join("; ");
    expect(cookies).toContain("better-auth.session_token");
    const headers = { Cookie: cookies, Origin: "http://localhost:8081" };
    const me = await exports.default.fetch(`${origin}/api/me`, { headers });
    expect(me.status).toBe(200);
    expect(me.headers.get("Cache-Control")).toBe("no-store");
    expect(await me.json()).toMatchObject({ user: { name: "Test person" } });
    const coordinator = await exports.default.fetch(
      `${origin}/api/coordinator`,
      { headers },
    );
    expect(await coordinator.json()).toEqual({
      ready: true,
      storage: "sqlite",
    });
    const row = await env.DB.prepare(
      'SELECT count(*) AS total FROM "session"',
    ).first<{ total: number }>();
    expect(row?.total).toBe(1);
    const signOut = await exports.default.fetch(`${origin}/api/auth/sign-out`, {
      method: "POST",
      headers,
    });
    expect(signOut.status).toBe(200);
    expect(
      (await exports.default.fetch(`${origin}/api/me`, { headers })).status,
    ).toBe(401);
  });
});
