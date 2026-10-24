import { applyD1Migrations } from "cloudflare:test";
import { env, exports } from "cloudflare:workers";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import foundation from "../migrations/0000_past_cyclops.sql?raw";
import discovery from "../migrations/0001_streetpass-discovery.sql?raw";
import { discoveryPolicy } from "../src/discovery";

beforeAll(async () => {
  await applyD1Migrations(env.DB, [
    {
      name: "0000_past_cyclops",
      queries: foundation.split("--> statement-breakpoint"),
    },
    {
      name: "0001_streetpass-discovery",
      queries: discovery.split("--> statement-breakpoint"),
    },
  ]);
});
beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM user"),
    env.DB.prepare("DELETE FROM rate_limit"),
  ]);
});

const origin = "http://localhost:8787";
type Client = { id: string; email: string; headers: Record<string, string> };
type Lease = {
  sessionId: string;
  token: string;
  expiresAt: number;
  sessionExpiresAt: number;
  serverTime: number;
};
type Encounter = {
  id: string;
  peer: { id: string; name: string };
  source: string;
  firstSeenAt: number;
  lastSeenAt: number;
};
type Receipt = { status: "pending" | "recorded"; encounter: Encounter | null };

async function account(name: string): Promise<Client> {
  const email = crypto.randomUUID() + "@example.test";
  const response = await exports.default.fetch(
    origin + "/api/auth/sign-up/email",
    {
      method: "POST",
      headers: { "Content-Type": "application/json", Origin: "face2face://" },
      body: JSON.stringify({
        name,
        email,
        password: "test-password-123456",
      }),
    },
  );
  expect(response.status).toBe(200);
  const token = response.headers.get("set-auth-token");
  expect(token).toBeTruthy();
  const json = (await response.json()) as { user: { id: string } };
  return {
    id: json.user.id,
    email,
    headers: {
      Authorization: "Bearer " + token,
      Origin: "face2face://",
      "Content-Type": "application/json",
    },
  };
}
function post(client: Client, path: string, value: unknown) {
  return exports.default.fetch(origin + "/api/" + path, {
    method: "POST",
    headers: client.headers,
    body: JSON.stringify(value),
  });
}
async function start(client: Client): Promise<Lease> {
  const response = await post(client, "discovery/start", {});
  expect(response.status).toBe(200);
  return response.json() as Promise<Lease>;
}
function observe(
  client: Client,
  own: Lease,
  peer: Lease,
  observationId = crypto.randomUUID(),
) {
  return post(client, "encounters/observe", {
    sessionId: own.sessionId,
    peerToken: peer.token,
    observationId,
  });
}
async function history(client: Client): Promise<Encounter[]> {
  const response = await exports.default.fetch(origin + "/api/encounters", {
    headers: client.headers,
  });
  expect(response.status).toBe(200);
  return ((await response.json()) as { encounters: Encounter[] }).encounters;
}
async function pair() {
  const alice = await account("Alice");
  const bob = await account("Bob");
  return { alice, bob, a: await start(alice), b: await start(bob) };
}

describe("StreetPass discovery contract", () => {
  it("requires authentication for all discovery and encounter endpoints", async () => {
    for (const path of [
      "discovery/start",
      "discovery/rotate",
      "discovery/stop",
      "encounters/observe",
    ]) {
      expect(
        (
          await exports.default.fetch(origin + "/api/" + path, {
            method: "POST",
            body: "{}",
          })
        ).status,
      ).toBe(401);
    }
    expect(
      (await exports.default.fetch(origin + "/api/encounters")).status,
    ).toBe(401);
  });

  it("issues expiring UUID tokens, bound to auth sessions, and stores only token hashes", async () => {
    const alice = await account("Alice");
    const lease = await start(alice);
    expect(lease.token).toMatch(/^[0-9a-f-]{36}$/);
    expect(lease.expiresAt - lease.serverTime).toBe(discoveryPolicy.tokenTTL);
    expect(lease.sessionExpiresAt - lease.serverTime).toBe(
      discoveryPolicy.sessionTTL,
    );
    const row = await env.DB.prepare(
      "SELECT hash FROM discovery_token WHERE session_id = ?",
    )
      .bind(lease.sessionId)
      .first<{ hash: string }>();
    expect(row?.hash).toMatch(/^[0-9a-f]{64}$/);
    expect(row?.hash).not.toContain(lease.token);
  });

  it("keeps identity hidden until both sessions report the exchange", async () => {
    const { alice, bob, a, b } = await pair();
    const first = await observe(alice, a, b);
    expect(first.status).toBe(200);
    expect(await first.json()).toEqual({ status: "pending", encounter: null });
    expect(await history(alice)).toEqual([]);
    expect(await history(bob)).toEqual([]);
    const reciprocal = await observe(bob, b, a);
    expect(reciprocal.status).toBe(200);
    const receipt = (await reciprocal.json()) as Receipt;
    expect(receipt.status).toBe("recorded");
    expect(receipt.encounter?.peer).toEqual({ id: alice.id, name: "Alice" });
    expect(receipt.encounter?.source).toBe("client_reported_bluetooth");
    const aliceHistory = await history(alice);
    const bobHistory = await history(bob);
    expect(aliceHistory).toHaveLength(1);
    expect(bobHistory).toHaveLength(1);
    expect(aliceHistory[0]?.id).toBe(bobHistory[0]?.id);
    expect(aliceHistory[0]?.peer).toEqual({ id: bob.id, name: "Bob" });
    expect(JSON.stringify(aliceHistory)).not.toContain(b.token);
  });

  it("deduplicates simultaneous reports into one shared encounter", async () => {
    const { alice, bob, a, b } = await pair();
    const responses = await Promise.all([
      observe(alice, a, b),
      observe(bob, b, a),
    ]);
    expect(responses.map((response) => response.status)).toEqual([200, 200]);
    expect(await history(alice)).toHaveLength(1);
    expect(await history(bob)).toHaveLength(1);
    const row = await env.DB.prepare(
      "SELECT count(*) AS total FROM encounter",
    ).first<{ total: number }>();
    expect(row?.total).toBe(1);
  });

  it("accepts an idempotent retry after token expiry without changing encounter timestamps", async () => {
    const { alice, bob, a, b } = await pair();
    const id = crypto.randomUUID();
    expect((await observe(alice, a, b, id)).status).toBe(200);
    expect((await observe(bob, b, a)).status).toBe(200);
    const initial = (await history(alice))[0];
    await env.DB.prepare(
      "UPDATE discovery_token SET expires_at = 0 WHERE session_id = ?",
    )
      .bind(b.sessionId)
      .run();
    // History cleanup also removes expired tokens; the accepted observation keeps its receipt.
    expect(await history(alice)).toHaveLength(1);
    const retry = await observe(alice, a, b, id);
    expect(retry.status).toBe(200);
    expect(((await retry.json()) as Receipt).encounter).toEqual(initial);
    const count = await env.DB.prepare(
      "SELECT count(*) AS total FROM discovery_observation",
    ).first<{ total: number }>();
    expect(count?.total).toBe(2);
  });

  it("rejects reusing an observation ID for a different peer token", async () => {
    const { alice, a, b } = await pair();
    const carol = await account("Carol");
    const c = await start(carol);
    const id = crypto.randomUUID();
    expect((await observe(alice, a, b, id)).status).toBe(200);
    expect((await observe(alice, a, c, id)).status).toBe(409);
    expect(await history(carol)).toEqual([]);
  });

  it("rotates with overlap and keeps the encounter ID stable across tokens", async () => {
    const { alice, bob, a, b } = await pair();
    await observe(alice, a, b);
    await observe(bob, b, a);
    const initial = (await history(alice))[0];
    const rotation = await post(alice, "discovery/rotate", {
      sessionId: a.sessionId,
    });
    expect(rotation.status).toBe(200);
    const rotated = (await rotation.json()) as Lease;
    expect(rotated.token).not.toBe(a.token);
    expect(rotated.sessionId).toBe(a.sessionId);
    expect(rotated.sessionExpiresAt).toBe(a.sessionExpiresAt);
    expect((await observe(bob, b, a)).status).toBe(200);
    expect((await observe(bob, b, rotated)).status).toBe(200);
    expect((await observe(alice, rotated, b)).status).toBe(200);
    const result = await history(alice);
    expect(result).toHaveLength(1);
    expect(result[0]?.id).toBe(initial?.id);
    expect(result[0]?.firstSeenAt).toBe(initial?.firstSeenAt);
  });

  it("revokes tokens on Stop and makes repeated Stop safe", async () => {
    const { alice, bob, a, b } = await pair();
    expect(
      (await post(alice, "discovery/stop", { sessionId: a.sessionId })).status,
    ).toBe(200);
    expect(
      (await post(alice, "discovery/stop", { sessionId: a.sessionId })).status,
    ).toBe(200);
    expect((await observe(bob, b, a)).status).toBe(410);
    expect(
      (await post(alice, "discovery/rotate", { sessionId: a.sessionId }))
        .status,
    ).toBe(410);
    const tokens = await env.DB.prepare(
      "SELECT count(*) AS total FROM discovery_token WHERE session_id = ?",
    )
      .bind(a.sessionId)
      .first<{ total: number }>();
    expect(tokens?.total).toBe(0);
  });

  it("revokes the previous account session on Start and requires fresh reciprocity", async () => {
    const { alice, bob, a, b } = await pair();
    await observe(alice, a, b);
    const fresh = await start(alice);
    expect(fresh.sessionId).not.toBe(a.sessionId);
    expect((await observe(bob, b, a)).status).toBe(410);
    const oneSided = await observe(bob, b, fresh);
    expect(await oneSided.json()).toEqual({
      status: "pending",
      encounter: null,
    });
    const reciprocal = await observe(alice, fresh, b);
    expect(((await reciprocal.json()) as Receipt).status).toBe("recorded");
  });

  it("binds discovery to the auth session and revokes it on sign-out", async () => {
    const { alice, bob, a, b } = await pair();
    expect((await post(alice, "auth/sign-out", {})).status).toBe(200);
    expect((await observe(bob, b, a)).status).toBe(410);
    const row = await env.DB.prepare(
      "SELECT count(*) AS total FROM discovery_session WHERE id = ?",
    )
      .bind(a.sessionId)
      .first<{ total: number }>();
    expect(row?.total).toBe(0);
  });

  it("does not let a second auth session use the first session's discovery lease", async () => {
    const { alice, bob, a, b } = await pair();
    const response = await exports.default.fetch(
      origin + "/api/auth/sign-in/email",
      {
        method: "POST",
        headers: { "Content-Type": "application/json", Origin: "face2face://" },
        body: JSON.stringify({
          email: alice.email,
          password: "test-password-123456",
        }),
      },
    );
    expect(response.status).toBe(200);
    const token = response.headers.get("set-auth-token");
    expect(token).toBeTruthy();
    const second: Client = {
      ...alice,
      headers: { ...alice.headers, Authorization: "Bearer " + token },
    };
    expect(
      (await post(second, "discovery/rotate", { sessionId: a.sessionId }))
        .status,
    ).toBe(410);
    expect((await observe(second, a, b)).status).toBe(410);
    expect((await observe(alice, a, b)).status).toBe(200);
    const fresh = await start(second);
    expect(
      (await post(alice, "discovery/rotate", { sessionId: a.sessionId }))
        .status,
    ).toBe(410);
    expect((await observe(bob, b, fresh)).status).toBe(200);
  });

  it("does not let one account rotate, use, or stop another account's discovery session", async () => {
    const { alice, bob, a, b } = await pair();
    expect(
      (await post(alice, "discovery/rotate", { sessionId: b.sessionId }))
        .status,
    ).toBe(410);
    expect((await observe(alice, b, a)).status).toBe(410);
    expect(
      (await post(alice, "discovery/stop", { sessionId: b.sessionId })).status,
    ).toBe(200);
    expect((await observe(bob, b, a)).status).toBe(200);
    expect(await history(alice)).toEqual([]);
  });

  it("rejects self, unknown, and expired tokens and expired local sessions", async () => {
    const { alice, bob, a, b } = await pair();
    expect((await observe(alice, a, a)).status).toBe(400);
    expect(
      (await observe(alice, a, { ...b, token: crypto.randomUUID() })).status,
    ).toBe(410);
    await env.DB.prepare(
      "UPDATE discovery_token SET expires_at = 0 WHERE session_id = ?",
    )
      .bind(b.sessionId)
      .run();
    expect((await observe(alice, a, b)).status).toBe(410);
    await env.DB.prepare(
      "UPDATE discovery_session SET expires_at = 0 WHERE id = ?",
    )
      .bind(a.sessionId)
      .run();
    expect(
      (await post(alice, "discovery/rotate", { sessionId: a.sessionId }))
        .status,
    ).toBe(410);
    expect(await history(bob)).toEqual([]);
  });

  it("requires reciprocal reports within the configured window", async () => {
    const { alice, bob, a, b } = await pair();
    await observe(alice, a, b);
    await env.DB.prepare("UPDATE discovery_observation SET received_at = ?")
      .bind(Date.now() - discoveryPolicy.reciprocalWindow - 1000)
      .run();
    const expired = await observe(bob, b, a);
    expect(await expired.json()).toEqual({
      status: "pending",
      encounter: null,
    });
    expect(await history(alice)).toEqual([]);
    expect(
      ((await (await observe(alice, a, b)).json()) as Receipt).status,
    ).toBe("recorded");
  });

  it("never returns another account's encounters", async () => {
    const { alice, bob, a, b } = await pair();
    await observe(alice, a, b);
    await observe(bob, b, a);
    const carol = await account("Carol");
    expect(await history(carol)).toEqual([]);
  });

  it("rejects caller-supplied identities, sources, malformed identifiers, and invalid JSON", async () => {
    const { alice, a, b } = await pair();
    expect(
      (await post(alice, "discovery/start", { userId: "someone-else" })).status,
    ).toBe(400);
    expect(
      (
        await post(alice, "encounters/observe", {
          sessionId: a.sessionId,
          peerToken: b.token,
          observationId: crypto.randomUUID(),
          source: "verified",
        })
      ).status,
    ).toBe(400);
    expect(
      (await post(alice, "discovery/rotate", { sessionId: "bad" })).status,
    ).toBe(400);
    expect((await post(alice, "discovery/stop", [])).status).toBe(400);
    const invalid = await exports.default.fetch(
      origin + "/api/discovery/start",
      {
        method: "POST",
        headers: alice.headers,
        body: "{",
      },
    );
    expect(invalid.status).toBe(400);
  });

  it("rate-limits new observations before resolving guessed peer tokens", async () => {
    const { alice, a, b } = await pair();
    const minute = Math.floor(Date.now() / 60_000);
    for (const bucket of [minute, minute + 1]) {
      await env.DB.prepare(
        "INSERT INTO discovery_quota (user_id, action, minute, count) VALUES (?, 'observe', ?, 120)",
      )
        .bind(alice.id, bucket)
        .run();
    }
    const limited = await observe(alice, a, b);
    expect(limited.status).toBe(429);
    expect(limited.headers.get("Retry-After")).toBe("60");
  });
});
