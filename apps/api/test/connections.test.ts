import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import {
  agreeToPublic,
  block,
  type Connection,
  decide,
} from "../src/connections/lifecycle";
import { orderPair } from "../src/connections/pair";
import app from "../src/index";
import {
  bearerHeaders,
  callAPI,
  nativeOrigin,
  postJSON,
  requireAuthToken,
} from "./helpers";

const ava = "seed-ava";
const ben = "seed-ben";
const noor = "seed-noor";

interface ConnectionView {
  id: string;
  status: string;
  sharedInterests: string[];
  you: { decision: string | null; publicAt: string | null };
  them: { name: string; age: number; interests: string[] } | null;
}

interface EncounterResponse {
  simulated: boolean;
  outcome: string;
  connection: { id: string; status: string; sharedInterests: string[] } | null;
}

beforeEach(async () => {
  await env.DB.prepare("DELETE FROM rate_limit").run();
  await postJSON("/api/dev/reset", {});
  await postJSON("/api/dev/seed", {});
});

async function signInAs(userId: string): Promise<Record<string, string>> {
  const response = await postJSON("/api/auth/sign-in/email", {
    email: `${userId.replace("seed-", "")}@seed.face2face.test`,
    password: "face2face-seed-password",
  });
  return bearerHeaders(requireAuthToken(response));
}

async function simulateEncounter(firstUserId: string, secondUserId: string) {
  const response = await postJSON("/api/dev/encounters", {
    firstUserId,
    secondUserId,
  });
  return response.json<EncounterResponse>();
}

async function listConnections(headers: Record<string, string>) {
  const response = await callAPI("/api/connections", { headers });
  expect(response.status).toBe(200);
  return (await response.json<{ connections: ConnectionView[] }>()).connections;
}

function act(
  headers: Record<string, string>,
  connectionId: string,
  action: "decision" | "public" | "block",
  body: unknown = {},
) {
  return postJSON(`/api/connections/${connectionId}/${action}`, body, headers);
}

async function inbox(userId: string) {
  const response = await callAPI(`/api/dev/users/${userId}/notifications`);
  return (await response.json<{ notifications: Record<string, unknown>[] }>())
    .notifications;
}

describe("connection lifecycle rules", () => {
  const now = new Date("2026-10-24T12:00:00Z");
  const pending: Connection = {
    id: "c1",
    userLowId: "a",
    userHighId: "b",
    status: "pending",
    sharedInterests: [],
    lowDecision: null,
    lowDecidedAt: null,
    highDecision: null,
    highDecidedAt: null,
    lowPublicAt: null,
    highPublicAt: null,
    blockedBy: null,
    createdAt: now,
    expiresAt: new Date(now.getTime() + 1000),
    resolvedAt: null,
  };

  it("orders a pair the same way whichever person reports it", () => {
    expect(orderPair("b", "a")).toEqual(orderPair("a", "b"));
  });

  it("opens a private connection only after both people accept", () => {
    const first = decide(pending, "low", "accepted", now);
    expect(first).toMatchObject({
      ok: true,
      changes: { lowDecision: "accepted" },
    });
    expect(first.ok && first.changes.status).toBeUndefined();
    const both = decide(
      { ...pending, lowDecision: "accepted" },
      "high",
      "accepted",
      now,
    );
    expect(both).toMatchObject({ ok: true, changes: { status: "private" } });
  });

  it("ends the chance as expired when either person declines", () => {
    expect(decide(pending, "high", "declined", now)).toMatchObject({
      ok: true,
      changes: { status: "expired", highDecision: "declined", resolvedAt: now },
    });
  });

  it("refuses a second answer from the same person", () => {
    expect(
      decide({ ...pending, lowDecision: "accepted" }, "low", "declined", now),
    ).toEqual({ ok: false, error: "already_decided" });
  });

  it("goes public only when both people agree", () => {
    const connected = {
      ...pending,
      status: "private" as const,
      lowDecision: "accepted" as const,
      highDecision: "accepted" as const,
    };
    expect(agreeToPublic(pending, "low", now)).toEqual({
      ok: false,
      error: "not_connected",
    });
    expect(agreeToPublic(connected, "low", now)).toEqual({
      ok: true,
      changes: { lowPublicAt: now },
    });
    expect(
      agreeToPublic({ ...connected, lowPublicAt: now }, "high", now),
    ).toMatchObject({ ok: true, changes: { status: "public" } });
  });

  it("records which side blocked", () => {
    expect(block(pending, "high", now)).toEqual({
      ok: true,
      changes: { status: "blocked", blockedBy: "high", resolvedAt: now },
    });
  });
});

describe("simulated encounters", () => {
  it("creates one pending chance with the interests both people share", async () => {
    const result = await simulateEncounter(ben, ava);
    expect(result).toMatchObject({
      simulated: true,
      outcome: "created",
      connection: { status: "pending", sharedInterests: ["coffee", "hiking"] },
    });
    const again = await simulateEncounter(ava, ben);
    expect(again.outcome).toBe("alreadyActive");
    expect(again.connection?.id).toBe(result.connection?.id);
  });

  it("allows a pair with no shared interests", async () => {
    const result = await simulateEncounter(ava, noor);
    expect(result.connection?.sharedInterests).toEqual([]);
  });

  it("tells both people what they share without saying who it was", async () => {
    const { connection } = await simulateEncounter(ava, ben);
    for (const userId of [ava, ben]) {
      const [notification] = await inbox(userId);
      expect(notification).toMatchObject({
        kind: "encounter",
        connectionId: connection?.id,
        sharedInterests: ["coffee", "hiking"],
      });
      expect(JSON.stringify(notification)).not.toMatch(/seed-|Ava|Ben/);
    }
  });

  it("opens a new chance after the previous one expires", async () => {
    const first = await simulateEncounter(ava, ben);
    await postJSON(`/api/dev/connections/${first.connection?.id}/expire`, {});
    const second = await simulateEncounter(ava, ben);
    expect(second.outcome).toBe("created");
    expect(second.connection?.id).not.toBe(first.connection?.id);
    const avaConnections = await listConnections(await signInAs(ava));
    expect(avaConnections.map((view) => view.id)).toEqual([
      second.connection?.id,
    ]);
  });

  it("rejects unknown people and self-encounters", async () => {
    const unknown = await postJSON("/api/dev/encounters", {
      firstUserId: ava,
      secondUserId: "nobody",
    });
    expect(unknown.status).toBe(404);
    const self = await postJSON("/api/dev/encounters", {
      firstUserId: ava,
      secondUserId: ava,
    });
    expect(self.status).toBe(400);
  });

  it("hides dev routes when DEV_TOOLS is off", async () => {
    const response = await app.request(
      "/api/dev/users",
      {},
      { ...env, DEV_TOOLS: "false" },
    );
    expect(response.status).toBe(404);
  });
});

describe("connections API", () => {
  it("requires a session", async () => {
    expect((await callAPI("/api/connections")).status).toBe(401);
  });

  it("shows only shared interests until both people go public", async () => {
    const { connection } = await simulateEncounter(ava, ben);
    const id = connection?.id ?? "";
    const avaHeaders = await signInAs(ava);
    const benHeaders = await signInAs(ben);

    await act(avaHeaders, id, "decision", { decision: "accepted" });
    const [waiting] = await listConnections(avaHeaders);
    expect(waiting).toMatchObject({
      status: "pending",
      you: { decision: "accepted" },
      them: null,
    });
    expect(JSON.stringify(await listConnections(benHeaders))).not.toMatch(
      /accepted|Ava/,
    );

    const accepted = await act(benHeaders, id, "decision", {
      decision: "accepted",
    });
    expect(
      (await accepted.json<{ connection: ConnectionView }>()).connection,
    ).toMatchObject({ status: "private", them: null });
    expect((await inbox(ava))[0]).toMatchObject({
      kind: "connected",
      connectionId: id,
    });

    await act(avaHeaders, id, "public");
    const [halfPublic] = await listConnections(benHeaders);
    expect(halfPublic).toMatchObject({ status: "private", them: null });

    const madePublic = await act(benHeaders, id, "public");
    const { connection: publicView } = await madePublic.json<{
      connection: ConnectionView;
    }>();
    expect(publicView.status).toBe("public");
    expect(publicView.them).toMatchObject({
      name: "Ava",
      avatar: { seed: expect.any(String), photo: null },
      interests: ["climbing", "coffee", "film", "hiking", "photography"],
    });
    expect((await inbox(ava))[0]).toMatchObject({ kind: "public" });
  });

  it("removes a declined chance from both lists", async () => {
    const { connection } = await simulateEncounter(ava, ben);
    const id = connection?.id ?? "";
    const declined = await act(await signInAs(ava), id, "decision", {
      decision: "declined",
    });
    expect(
      (await declined.json<{ connection: ConnectionView }>()).connection.status,
    ).toBe("expired");
    expect(await listConnections(await signInAs(ava))).toEqual([]);
    expect(await listConnections(await signInAs(ben))).toEqual([]);
  });

  it("refuses answers after the chance expires", async () => {
    const { connection } = await simulateEncounter(ava, ben);
    const id = connection?.id ?? "";
    await postJSON(`/api/dev/connections/${id}/expire`, {});
    expect(await listConnections(await signInAs(ava))).toEqual([]);
    const late = await act(await signInAs(ava), id, "decision", {
      decision: "accepted",
    });
    expect(late.status).toBe(409);
    expect(await late.json()).toEqual({ error: "not_pending" });
  });

  it("hides a block from the blocked person and stops new chances", async () => {
    const { connection } = await simulateEncounter(ava, ben);
    const id = connection?.id ?? "";
    const blocked = await act(await signInAs(ben), id, "block");
    expect(blocked.status).toBe(200);

    expect(await listConnections(await signInAs(ava))).toEqual([]);
    const avaAction = await act(await signInAs(ava), id, "decision", {
      decision: "accepted",
    });
    expect(avaAction.status).toBe(404);
    expect((await simulateEncounter(ava, ben)).outcome).toBe("ignored");
  });

  it("does not let a stranger see or change someone else's connection", async () => {
    const { connection } = await simulateEncounter(ava, ben);
    const stranger = await act(
      await signInAs(noor),
      connection?.id ?? "",
      "block",
    );
    expect(stranger.status).toBe(404);
  });

  it("rejects an unknown decision", async () => {
    const { connection } = await simulateEncounter(ava, ben);
    const response = await act(
      await signInAs(ava),
      connection?.id ?? "",
      "decision",
      {
        decision: "maybe",
      },
    );
    expect(response.status).toBe(400);
  });
});

describe("interest member counts", () => {
  async function memberCount(id: string) {
    const row = await env.DB.prepare(
      "SELECT member_count AS count FROM interest WHERE id = ?",
    )
      .bind(id)
      .first<{ count: number }>();
    return row?.count;
  }

  it("follows profile_interest rows, including deleted accounts", async () => {
    const before = await memberCount("coffee");
    await env.DB.prepare(
      "INSERT INTO user (id, name, email, email_verified, created_at, updated_at) VALUES ('count-test', 'Count', 'count@example.test', 1, 0, 0)",
    ).run();
    await env.DB.prepare(
      "INSERT INTO profile_interest (user_id, interest_id, created_at) VALUES ('count-test', 'coffee', 0)",
    ).run();
    expect(await memberCount("coffee")).toBe((before ?? 0) + 1);
    await env.DB.prepare("DELETE FROM user WHERE id = 'count-test'").run();
    expect(await memberCount("coffee")).toBe(before);
  });

  it("does not double count when seeding again", async () => {
    const before = await memberCount("hiking");
    await postJSON("/api/dev/seed", {});
    expect(await memberCount("hiking")).toBe(before);
  });
});

describe("notification socket", () => {
  async function ticketFor(headers: Record<string, string>) {
    const response = await postJSON("/api/notifications/ticket", {}, headers);
    expect(response.status).toBe(200);
    return (await response.json<{ ticket: string }>()).ticket;
  }

  function openSocket(ticket: string) {
    return callAPI(
      `/api/notifications/socket?ticket=${encodeURIComponent(ticket)}`,
      { headers: { Upgrade: "websocket", Origin: nativeOrigin } },
    );
  }

  it("pushes a new encounter to an open socket", async () => {
    const ticket = await ticketFor(await signInAs(ava));
    const response = await openSocket(ticket);
    expect(response.status).toBe(101);
    const socket = response.webSocket;
    if (!socket) throw new Error("No WebSocket in the upgrade response");
    const messages: { type: string; notification?: { kind: string } }[] = [];
    socket.addEventListener("message", (event) => {
      messages.push(JSON.parse(String(event.data)));
    });
    socket.accept();

    await simulateEncounter(ava, ben);
    await expect
      .poll(() => messages.map((message) => message.notification?.kind))
      .toContain("encounter");
    socket.close();
  });

  it("serves the same notifications from the inbox endpoint", async () => {
    await simulateEncounter(ava, ben);
    const response = await callAPI("/api/notifications", {
      headers: await signInAs(ben),
    });
    const { notifications } = await response.json<{
      notifications: { kind: string }[];
    }>();
    expect(notifications[0]?.kind).toBe("encounter");
  });

  it("rejects a forged or missing ticket", async () => {
    const ticket = await ticketFor(await signInAs(ava));
    const [payload] = ticket.split(".");
    expect((await openSocket(`${payload}.forged`)).status).toBe(401);
    expect((await openSocket("")).status).toBe(401);
  });
});
