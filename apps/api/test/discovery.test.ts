import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { discoveryPolicy } from "../src/discovery/discovery";
import {
  bearerHeaders,
  callAPI,
  postJSON,
  requireAuthToken,
  signInWithEmailCode,
} from "./helpers";

const ava = "seed-ava";
const ben = "seed-ben";
const noor = "seed-noor";

type Client = { id: string; headers: Record<string, string> };
type Lease = {
  sessionId: string;
  token: string;
  expiresAt: number;
  sessionExpiresAt: number;
  serverTime: number;
};
type Receipt = { status: "pending" | "recorded" | "noSharedInterests" };
type ConnectionView = {
  id: string;
  status: string;
  sharedInterests: string[];
  them: unknown;
};

beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM rate_limit"),
    env.DB.prepare("DELETE FROM discovery_session"),
    env.DB.prepare("DELETE FROM discovery_quota"),
  ]);
  await postJSON("/api/dev/reset", {});
  await postJSON("/api/dev/seed", {});
});

async function signInAs(userId: string): Promise<Client> {
  const response = await postJSON("/api/auth/sign-in/email", {
    email: `${userId.replace("seed-", "")}@seed.face2face.test`,
    password: "face2face-seed-password",
  });
  expect(response.status).toBe(200);
  return { id: userId, headers: bearerHeaders(requireAuthToken(response)) };
}

function post(client: Client, path: string, value: unknown) {
  return postJSON(`/api/discovery/${path}`, value, client.headers);
}

async function start(client: Client): Promise<Lease> {
  const response = await post(client, "start", {});
  expect(response.status).toBe(200);
  return response.json<Lease>();
}

function observe(
  client: Client,
  own: Lease,
  peer: Lease,
  observationId: string = crypto.randomUUID(),
) {
  return post(client, "observe", {
    sessionId: own.sessionId,
    peerToken: peer.token,
    observationId,
  });
}

async function receipt(response: Response) {
  expect(response.status).toBe(200);
  return response.json<Receipt>();
}

async function connections(client: Client) {
  const response = await callAPI("/api/connections", {
    headers: client.headers,
  });
  expect(response.status).toBe(200);
  return (await response.json<{ connections: ConnectionView[] }>()).connections;
}

async function encounterNotifications(userId: string) {
  const response = await callAPI(`/api/dev/users/${userId}/notifications`);
  const { notifications } = await response.json<{
    notifications: { kind: string; connectionId?: string }[];
  }>();
  return notifications.filter(
    (notification) => notification.kind === "encounter",
  );
}

async function count(table: string) {
  const row = await env.DB.prepare(
    `SELECT count(*) AS total FROM ${table}`,
  ).first<{ total: number }>();
  return row?.total;
}

async function pair() {
  const alice = await signInAs(ava);
  const bob = await signInAs(ben);
  return { alice, bob, a: await start(alice), b: await start(bob) };
}

describe("StreetPass discovery", () => {
  it("requires a session for every discovery endpoint", async () => {
    for (const path of ["start", "rotate", "stop", "observe"]) {
      const response = await postJSON(`/api/discovery/${path}`, {});
      expect(response.status).toBe(401);
    }
  });

  it("requires a finished profile", async () => {
    const token = await signInWithEmailCode(
      `${crypto.randomUUID()}@example.test`,
    );
    const response = await postJSON(
      "/api/discovery/start",
      {},
      bearerHeaders(token),
    );
    expect(response.status).toBe(403);
    expect(await response.json()).toEqual({ error: "onboarding_required" });
  });

  it("issues expiring tokens bound to the auth session and stores only hashes", async () => {
    const alice = await signInAs(ava);
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

  it("opens one pending chance after reciprocal reports and never names the peer", async () => {
    const { alice, bob, a, b } = await pair();
    const first = await observe(alice, a, b);
    const firstBody = await first.text();
    expect(JSON.parse(firstBody)).toEqual({ status: "pending" });
    expect(await connections(alice)).toEqual([]);

    const reciprocal = await observe(bob, b, a);
    const reciprocalBody = await reciprocal.text();
    expect(JSON.parse(reciprocalBody)).toMatchObject({ status: "recorded" });
    const { matchId } = JSON.parse(reciprocalBody) as { matchId: string };
    expect(matchId).toMatch(/^[0-9a-f]{64}$/);
    expect(matchId).not.toContain(a.sessionId);
    for (const body of [firstBody, reciprocalBody]) {
      expect(body).not.toContain(ava);
      expect(body).not.toContain(ben);
      expect(body).not.toMatch(/Ava|Ben/);
    }

    const [aliceChance] = await connections(alice);
    const [bobChance] = await connections(bob);
    expect(aliceChance?.status).toBe("pending");
    expect(aliceChance?.id).toBe(bobChance?.id);
    expect(aliceChance?.them).toBeNull();
    expect(aliceChance?.sharedInterests.length).toBeGreaterThan(0);

    const [aliceNote] = await encounterNotifications(ava);
    const [bobNote] = await encounterNotifications(ben);
    expect(aliceNote?.connectionId).toBe(aliceChance?.id);
    expect(bobNote?.connectionId).toBe(aliceChance?.id);
  });

  it("reports an earlier observation as recorded once the peer reciprocates", async () => {
    const { alice, bob, a, b } = await pair();
    const id = crypto.randomUUID();
    expect(await receipt(await observe(alice, a, b, id))).toEqual({
      status: "pending",
    });
    const theirs = await receipt(await observe(bob, b, a));
    expect(await receipt(await observe(alice, a, b, id))).toEqual(theirs);
  });

  it("creates one chance for simultaneous reports", async () => {
    const { alice, bob, a, b } = await pair();
    const responses = await Promise.all([
      observe(alice, a, b),
      observe(bob, b, a),
    ]);
    expect(responses.map((response) => response.status)).toEqual([200, 200]);
    const [chance] = await connections(alice);
    expect(await count("connection")).toBe(1);
    const notes = await encounterNotifications(ava);
    expect(
      notes.filter((note) => note.connectionId === chance?.id),
    ).toHaveLength(1);
  });

  it("records one encounter per pair of leases, even after a decline", async () => {
    const { alice, bob, a, b } = await pair();
    await observe(alice, a, b);
    await observe(bob, b, a);
    const [chance] = await connections(alice);
    const decline = await postJSON(
      `/api/connections/${chance?.id}/decision`,
      { decision: "declined" },
      alice.headers,
    );
    expect(decline.status).toBe(200);
    expect(await receipt(await observe(alice, a, b))).toMatchObject({
      status: "recorded",
    });
    expect(await receipt(await observe(bob, b, a))).toMatchObject({
      status: "recorded",
    });
    expect(await count("connection")).toBe(1);
    expect(await connections(alice)).toEqual([]);
  });

  it("accepts an idempotent retry after the peer token expires", async () => {
    const { alice, bob, a, b } = await pair();
    const id = crypto.randomUUID();
    await observe(alice, a, b, id);
    await observe(bob, b, a);
    await env.DB.prepare(
      "UPDATE discovery_token SET expires_at = 0 WHERE session_id = ?",
    )
      .bind(b.sessionId)
      .run();
    expect(await receipt(await observe(alice, a, b, id))).toMatchObject({
      status: "recorded",
    });
    expect(await count("discovery_observation")).toBe(2);
  });

  it("rejects reusing an observation ID for a different peer token", async () => {
    const { alice, a, b } = await pair();
    const carol = await signInAs(noor);
    const c = await start(carol);
    const id = crypto.randomUUID();
    expect((await observe(alice, a, b, id)).status).toBe(200);
    expect((await observe(alice, a, c, id)).status).toBe(409);
  });

  it("rotates with overlap and keeps one chance across tokens", async () => {
    const { alice, bob, a, b } = await pair();
    await observe(alice, a, b);
    await observe(bob, b, a);
    const rotation = await post(alice, "rotate", { sessionId: a.sessionId });
    expect(rotation.status).toBe(200);
    const rotated = await rotation.json<Lease>();
    expect(rotated.token).not.toBe(a.token);
    expect(rotated.sessionId).toBe(a.sessionId);
    expect(rotated.sessionExpiresAt).toBe(a.sessionExpiresAt);
    const before = await receipt(await observe(bob, b, a));
    const after = await receipt(await observe(bob, b, rotated));
    const mine = await receipt(await observe(alice, rotated, b));
    expect(after).toEqual(before);
    expect(mine).toEqual(before);
    expect(await count("connection")).toBe(1);
  });

  it("revokes tokens on Stop and makes repeated Stop safe", async () => {
    const { alice, bob, a, b } = await pair();
    for (let attempt = 0; attempt < 2; attempt++) {
      const stop = await post(alice, "stop", { sessionId: a.sessionId });
      expect(stop.status).toBe(200);
    }
    expect((await observe(bob, b, a)).status).toBe(410);
    expect(
      (await post(alice, "rotate", { sessionId: a.sessionId })).status,
    ).toBe(410);
    const tokens = await env.DB.prepare(
      "SELECT count(*) AS total FROM discovery_token WHERE session_id = ?",
    )
      .bind(a.sessionId)
      .first<{ total: number }>();
    expect(tokens?.total).toBe(0);
  });

  it("ends the previous lease on Start and requires fresh reports", async () => {
    const { alice, bob, a, b } = await pair();
    await observe(alice, a, b);
    const fresh = await start(alice);
    expect(fresh.sessionId).not.toBe(a.sessionId);
    expect((await observe(bob, b, a)).status).toBe(410);
    expect(await receipt(await observe(bob, b, fresh))).toEqual({
      status: "pending",
    });
    expect(await receipt(await observe(alice, fresh, b))).toMatchObject({
      status: "recorded",
    });
  });

  it("revokes the lease when its auth session signs out", async () => {
    const { alice, bob, a, b } = await pair();
    expect(
      (await postJSON("/api/auth/sign-out", {}, alice.headers)).status,
    ).toBe(200);
    expect((await observe(bob, b, a)).status).toBe(410);
    const row = await env.DB.prepare(
      "SELECT count(*) AS total FROM discovery_session WHERE id = ?",
    )
      .bind(a.sessionId)
      .first<{ total: number }>();
    expect(row?.total).toBe(0);
  });

  it("does not let a second auth session use the first session's lease", async () => {
    const { alice, bob, a, b } = await pair();
    const second = await signInAs(ava);
    expect(
      (await post(second, "rotate", { sessionId: a.sessionId })).status,
    ).toBe(410);
    expect((await observe(second, a, b)).status).toBe(410);
    expect((await observe(alice, a, b)).status).toBe(200);
    const fresh = await start(second);
    expect(
      (await post(alice, "rotate", { sessionId: a.sessionId })).status,
    ).toBe(410);
    expect((await observe(bob, b, fresh)).status).toBe(200);
  });

  it("does not let one account rotate, use, or stop another account's lease", async () => {
    const { alice, bob, a, b } = await pair();
    expect(
      (await post(alice, "rotate", { sessionId: b.sessionId })).status,
    ).toBe(410);
    expect((await observe(alice, b, a)).status).toBe(410);
    expect((await post(alice, "stop", { sessionId: b.sessionId })).status).toBe(
      200,
    );
    expect((await observe(bob, b, a)).status).toBe(200);
    expect(await connections(alice)).toEqual([]);
  });

  it("rejects self, unknown, and expired tokens and expired leases", async () => {
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
      (await post(alice, "rotate", { sessionId: a.sessionId })).status,
    ).toBe(410);
    expect(await connections(bob)).toEqual([]);
  });

  it("requires reciprocal reports within the window", async () => {
    const { alice, bob, a, b } = await pair();
    await observe(alice, a, b);
    await env.DB.prepare("UPDATE discovery_observation SET received_at = ?")
      .bind(Date.now() - discoveryPolicy.reciprocalWindow - 1000)
      .run();
    expect(await receipt(await observe(bob, b, a))).toEqual({
      status: "pending",
    });
    expect(await connections(alice)).toEqual([]);
    expect(await receipt(await observe(alice, a, b))).toMatchObject({
      status: "recorded",
    });
  });

  it("hides a block from the reporter and opens no chance", async () => {
    await env.DB.prepare(
      "INSERT INTO block (blocker_id, blocked_id, created_at) VALUES (?, ?, ?)",
    )
      .bind(ben, ava, Date.now())
      .run();
    const inboxBefore = (await encounterNotifications(ava)).length;
    const { alice, bob, a, b } = await pair();
    await observe(alice, a, b);
    expect(await receipt(await observe(bob, b, a))).toMatchObject({
      status: "recorded",
    });
    expect(await count("connection")).toBe(0);
    expect(await encounterNotifications(ava)).toHaveLength(inboxBefore);
    expect(await connections(alice)).toEqual([]);
  });

  it("opens no chance for a pair that shares no interests", async () => {
    const alice = await signInAs(ava);
    const carol = await signInAs(noor);
    const a = await start(alice);
    const c = await start(carol);
    const id = crypto.randomUUID();
    const inboxBefore = (await encounterNotifications(ava)).length;
    expect(await receipt(await observe(alice, a, c, id))).toEqual({
      status: "pending",
    });
    const theirs = await receipt(await observe(carol, c, a));
    expect(theirs).toMatchObject({ status: "noSharedInterests" });
    expect(await receipt(await observe(alice, a, c, id))).toEqual(theirs);
    expect(await count("connection")).toBe(0);
    expect(await encounterNotifications(ava)).toHaveLength(inboxBefore);
    expect(await connections(alice)).toEqual([]);
    expect(await connections(carol)).toEqual([]);
  });

  it("still opens a chance through the dev route without shared interests", async () => {
    const response = await postJSON("/api/dev/encounters", {
      firstUserId: ava,
      secondUserId: noor,
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ outcome: "created" });
  });

  it("does not show a chance to a third account", async () => {
    const { alice, bob, a, b } = await pair();
    await observe(alice, a, b);
    await observe(bob, b, a);
    expect(await connections(await signInAs(noor))).toEqual([]);
  });

  it("rejects extra fields, malformed identifiers, and invalid JSON", async () => {
    const { alice, a, b } = await pair();
    expect(
      (await post(alice, "start", { userId: "someone-else" })).status,
    ).toBe(400);
    expect(
      (
        await post(alice, "observe", {
          sessionId: a.sessionId,
          peerToken: b.token,
          observationId: crypto.randomUUID(),
          source: "verified",
        })
      ).status,
    ).toBe(400);
    expect((await post(alice, "rotate", { sessionId: "bad" })).status).toBe(
      400,
    );
    expect((await post(alice, "stop", [])).status).toBe(400);
    const invalid = await callAPI("/api/discovery/start", {
      method: "POST",
      headers: { ...alice.headers, "Content-Type": "application/json" },
      body: "{",
    });
    expect(invalid.status).toBe(400);
  });

  it("rate-limits new observations before resolving guessed tokens", async () => {
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
