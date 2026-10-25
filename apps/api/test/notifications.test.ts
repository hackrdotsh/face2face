import { runInDurableObject } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import {
  type PushAlert,
  type PushEnvironment,
  type PushResult,
  signProviderToken,
} from "../src/notifications/apns";
import { pushTextFor } from "../src/notifications/notification";
import { bearerHeaders, callAPI, postJSON, requireAuthToken } from "./helpers";

const ava = "seed-ava";
const ben = "seed-ben";
const avaToken = "a".repeat(64);
const staleToken = "b".repeat(64);

interface Inbox {
  notifications: { id: string; kind: string }[];
  unreadCount: number;
}

interface SentPush {
  token: string;
  environment: PushEnvironment;
  alert: PushAlert;
}

beforeEach(async () => {
  await env.DB.prepare("DELETE FROM rate_limit").run();
  await env.DB.prepare("DELETE FROM push_device").run();
  await postJSON("/api/dev/reset", {});
  await postJSON("/api/dev/seed", {});
  for (const userId of [ava, ben]) {
    await runInDurableObject(
      env.USER_COORDINATORS.getByName(userId),
      async (coordinator) => {
        await coordinator.clearNotifications();
        await coordinator.markSeen();
        for (const device of await coordinator.listDevices()) {
          await coordinator.unregisterDevice(device.token);
        }
        coordinator.pushSender = null;
      },
    );
  }
});

async function signInAs(userId: string): Promise<Record<string, string>> {
  const response = await postJSON("/api/auth/sign-in/email", {
    email: `${userId.replace("seed-", "")}@seed.face2face.test`,
    password: "face2face-seed-password",
  });
  return bearerHeaders(requireAuthToken(response));
}

async function simulateEncounter() {
  const response = await postJSON("/api/dev/encounters", {
    firstUserId: ava,
    secondUserId: ben,
  });
  expect(response.status).toBe(200);
  return (await response.json<{ connection: { id: string } }>()).connection;
}

async function readInbox(headers: Record<string, string>): Promise<Inbox> {
  const response = await callAPI("/api/notifications", { headers });
  expect(response.status).toBe(200);
  return response.json<Inbox>();
}

/** Records pushes for one person instead of calling APNs. */
async function capturePushes(
  userId: string,
  results: Record<string, PushResult> = {},
): Promise<SentPush[]> {
  const sent: SentPush[] = [];
  await runInDurableObject(
    env.USER_COORDINATORS.getByName(userId),
    (coordinator) => {
      coordinator.pushSender = {
        async send(token, environment, alert) {
          sent.push({ token, environment, alert });
          return results[token] ?? "sent";
        },
      };
    },
  );
  return sent;
}

function registerDevice(
  headers: Record<string, string>,
  token: string,
  environment: string,
) {
  return callAPI(`/api/notifications/devices/${token}`, {
    method: "PUT",
    headers: { ...headers, "Content-Type": "application/json" },
    body: JSON.stringify({ environment }),
  });
}

describe("unread count", () => {
  it("counts new notifications until the inbox is seen", async () => {
    const headers = await signInAs(ava);
    expect((await readInbox(headers)).unreadCount).toBe(0);
    await simulateEncounter();
    expect((await readInbox(headers)).unreadCount).toBe(1);

    const seen = await postJSON("/api/notifications/seen", {}, headers);
    expect(await seen.json()).toEqual({ unreadCount: 0 });
    const inbox = await readInbox(headers);
    expect(inbox.unreadCount).toBe(0);
    expect(inbox.notifications).toHaveLength(1);
  });

  it("is kept for each person separately", async () => {
    await simulateEncounter();
    await postJSON("/api/notifications/seen", {}, await signInAs(ava));
    expect((await readInbox(await signInAs(ben))).unreadCount).toBe(1);
  });
});

describe("dismissing notifications", () => {
  it("deletes one notification and lowers the count", async () => {
    const headers = await signInAs(ava);
    await simulateEncounter();
    const [notification] = (await readInbox(headers)).notifications;
    if (!notification) throw new Error("Expected an encounter notification");

    const response = await callAPI(`/api/notifications/${notification.id}`, {
      method: "DELETE",
      headers,
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ unreadCount: 0 });
    expect((await readInbox(headers)).notifications).toEqual([]);
  });

  it("cannot delete another person's notification", async () => {
    await simulateEncounter();
    const [bens] = (await readInbox(await signInAs(ben))).notifications;
    if (!bens) throw new Error("Expected an encounter notification");
    const response = await callAPI(`/api/notifications/${bens.id}`, {
      method: "DELETE",
      headers: await signInAs(ava),
    });
    expect(response.status).toBe(404);
    expect((await readInbox(await signInAs(ben))).notifications).toHaveLength(
      1,
    );
  });

  it("clears the whole inbox", async () => {
    const headers = await signInAs(ava);
    await simulateEncounter();
    const response = await callAPI("/api/notifications", {
      method: "DELETE",
      headers,
    });
    expect(await response.json()).toEqual({ unreadCount: 0 });
    expect(await readInbox(headers)).toEqual({
      notifications: [],
      unreadCount: 0,
    });
  });

  it("requires a session", async () => {
    const response = await callAPI("/api/notifications", { method: "DELETE" });
    expect(response.status).toBe(401);
  });
});

describe("push devices", () => {
  it("reports setup only for the signed-in person's devices, without tokens or provider secrets", async () => {
    expect((await callAPI("/api/notifications/push-status")).status).toBe(401);
    const headers = await signInAs(ava);
    await registerDevice(await signInAs(ben), staleToken, "production");
    const before = await callAPI(
      `/api/notifications/push-status?userId=${ben}`,
      { headers },
    );
    expect(await before.json()).toMatchObject({
      providerConfigured: false,
      registeredDeviceCount: 0,
    });
    await registerDevice(headers, avaToken, "sandbox");
    await capturePushes(ava);
    const response = await callAPI("/api/notifications/push-status", {
      headers,
    });
    const text = await response.text();
    expect(JSON.parse(text)).toMatchObject({
      providerConfigured: true,
      registeredDeviceCount: 1,
    });
    expect(text).not.toContain(avaToken);
    expect(text).not.toContain(staleToken);
    expect(text).not.toMatch(/privateKey|APNS_PRIVATE_KEY/);
  });
  it("sends a new pending connection to registered phones", async () => {
    const headers = await signInAs(ava);
    expect((await registerDevice(headers, avaToken, "sandbox")).status).toBe(
      204,
    );
    const sent = await capturePushes(ava);
    const connection = await simulateEncounter();

    expect(sent).toHaveLength(1);
    expect(sent[0]).toMatchObject({
      token: avaToken,
      environment: "sandbox",
      alert: {
        title: "A new hello",
        badge: 1,
        data: { kind: "encounter", connectionId: connection.id },
      },
    });
    expect(JSON.stringify(sent)).not.toMatch(/seed-|\bAva\b|\bBen\b/);
  });

  it("sends when both people say yes", async () => {
    await registerDevice(await signInAs(ava), avaToken, "production");
    const connection = await simulateEncounter();
    const sent = await capturePushes(ava);
    for (const userId of [ava, ben]) {
      await postJSON(
        `/api/connections/${connection.id}/decision`,
        { decision: "accepted" },
        await signInAs(userId),
      );
    }
    expect(sent.map((push) => push.alert.title)).toEqual(["It's a connection"]);
    expect(sent[0]?.alert.badge).toBe(2);
  });

  it("forgets a token that APNs no longer accepts", async () => {
    const headers = await signInAs(ava);
    await registerDevice(headers, avaToken, "sandbox");
    await registerDevice(headers, staleToken, "sandbox");
    const sent = await capturePushes(ava, { [staleToken]: "unregistered" });
    await simulateEncounter();

    expect(sent).toHaveLength(2);
    const devices = await runInDurableObject(
      env.USER_COORDINATORS.getByName(ava),
      (coordinator) => coordinator.listDevices(),
    );
    expect(devices).toEqual([{ token: avaToken, environment: "sandbox" }]);
  });

  it("stops sending after the phone unregisters", async () => {
    const headers = await signInAs(ava);
    await registerDevice(headers, avaToken.toUpperCase(), "sandbox");
    const removed = await callAPI(`/api/notifications/devices/${avaToken}`, {
      method: "DELETE",
      headers,
    });
    expect(removed.status).toBe(204);
    const sent = await capturePushes(ava);
    await simulateEncounter();
    expect(sent).toEqual([]);
  });

  it("moves a phone to whoever signed in on it last", async () => {
    await registerDevice(await signInAs(ava), avaToken, "sandbox");
    const bensHeaders = await signInAs(ben);
    expect(
      (await registerDevice(bensHeaders, avaToken, "sandbox")).status,
    ).toBe(204);
    const toAva = await capturePushes(ava);
    const toBen = await capturePushes(ben);
    await simulateEncounter();

    expect(toAva).toEqual([]);
    expect(toBen.map((push) => push.token)).toEqual([avaToken]);
    const owners = await env.DB.prepare(
      "SELECT user_id, token_hash FROM push_device",
    ).all<{ user_id: string; token_hash: string }>();
    expect(owners.results.map((row) => row.user_id)).toEqual([ben]);
    expect(owners.results[0]?.token_hash).not.toBe(avaToken);
  });

  it("does not let a former owner unregister the new owner's phone", async () => {
    const avasHeaders = await signInAs(ava);
    await registerDevice(avasHeaders, avaToken, "sandbox");
    await registerDevice(await signInAs(ben), avaToken, "sandbox");
    await callAPI(`/api/notifications/devices/${avaToken}`, {
      method: "DELETE",
      headers: avasHeaders,
    });
    const toBen = await capturePushes(ben);
    await simulateEncounter();
    expect(toBen).toHaveLength(1);
  });

  it("rejects malformed tokens and environments", async () => {
    const headers = await signInAs(ava);
    expect((await registerDevice(headers, "not-hex", "sandbox")).status).toBe(
      400,
    );
    expect((await registerDevice(headers, avaToken, "staging")).status).toBe(
      400,
    );
  });
});

describe("push text", () => {
  it("only covers connection events", () => {
    expect(
      pushTextFor({
        kind: "encounter",
        connectionId: "c",
        sharedInterests: ["music", "coffee"],
        expiresAt: "2026-10-26T00:00:00Z",
      })?.body,
    ).toBe("A new chance to connect over music and coffee.");
    expect(pushTextFor({ kind: "public", connectionId: "c" })?.title).toBe(
      "A little more face to face",
    );
    expect(
      pushTextFor({ kind: "post_rsvp", postId: "p", forumId: "f" }),
    ).toBeNull();
  });
});

describe("APNs provider token", () => {
  it("is an ES256 JWT that verifies with the key's public half", async () => {
    const pair = (await crypto.subtle.generateKey(
      { name: "ECDSA", namedCurve: "P-256" },
      true,
      ["sign", "verify"],
    )) as CryptoKeyPair;
    const pkcs8 = new Uint8Array(
      (await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer,
    );
    const body = btoa(String.fromCharCode(...pkcs8));
    const pem = `-----BEGIN PRIVATE KEY-----\n${body.match(/.{1,64}/g)?.join("\n")}\n-----END PRIVATE KEY-----`;

    const now = Date.parse("2026-10-25T12:00:00Z");
    const jwt = await signProviderToken(
      { teamId: "GFQG7YBAYY", keyId: "ABC123DEFG", privateKey: pem },
      now,
    );
    const [header, claims, signature] = jwt.split(".");
    if (!header || !claims || !signature) throw new Error("Malformed JWT");
    const decode = (segment: string) =>
      Uint8Array.from(
        atob(segment.replaceAll("-", "+").replaceAll("_", "/")),
        (character) => character.charCodeAt(0),
      );
    expect(JSON.parse(new TextDecoder().decode(decode(header)))).toEqual({
      alg: "ES256",
      kid: "ABC123DEFG",
    });
    expect(JSON.parse(new TextDecoder().decode(decode(claims)))).toEqual({
      iss: "GFQG7YBAYY",
      iat: now / 1000,
    });
    const valid = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      pair.publicKey,
      decode(signature),
      new TextEncoder().encode(`${header}.${claims}`),
    );
    expect(valid).toBe(true);
  });
});
